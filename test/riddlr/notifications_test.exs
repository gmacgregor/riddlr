defmodule Riddlr.NotificationsTest do
  # Freezes the global test clock, so not async.
  use Riddlr.DataCase, async: false
  use Oban.Testing, repo: Riddlr.Repo

  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  alias Riddlr.Notifications
  alias Riddlr.Notifications.RiddleNotification
  alias Riddlr.Workers.SendNotificationWorker

  defp opted_in(attrs \\ %{}) do
    user_fixture()
    |> Ecto.Changeset.change(Map.merge(%{notify_email: true}, attrs))
    |> Repo.update!()
  end

  defp ready_riddle do
    riddle = scheduled_riddle_fixture()
    {:ok, ready} = Riddlr.Games.transition(riddle.id, :ready)
    ready
  end

  describe "fan_out/2" do
    test "queues one send job per eligible player" do
      riddle = ready_riddle()
      alice = opted_in()
      bob = opted_in()

      assert {:ok, 2} = Notifications.fan_out(riddle.id, :lobby_open)

      for user <- [alice, bob] do
        row = Repo.get_by!(RiddleNotification, riddle_id: riddle.id, user_id: user.id)
        assert row.channel == :email
        assert row.sent_at == nil
        assert_enqueued(worker: SendNotificationWorker, args: %{"notification_id" => row.id})
      end
    end

    test "skips banned, suspended, unconfirmed, opted-out and other lead time players" do
      riddle = ready_riddle()
      opted_in(%{account_status: :banned})
      opted_in(%{account_status: :suspended})
      opted_in(%{notification_lead_time: :min_30})
      user_fixture()

      unconfirmed_user_fixture()
      |> Ecto.Changeset.change(notify_email: true)
      |> Repo.update!()

      assert {:ok, 0} = Notifications.fan_out(riddle.id, :lobby_open)
      refute_enqueued(worker: SendNotificationWorker)
    end

    test "a second run adds no rows and queues no jobs" do
      riddle = ready_riddle()
      opted_in()

      assert {:ok, 1} = Notifications.fan_out(riddle.id, :lobby_open)
      assert {:ok, 0} = Notifications.fan_out(riddle.id, :lobby_open)

      assert [_one] = all_enqueued(worker: SendNotificationWorker)
    end

    test "after Unschedule and a new Schedule, an unsent player is queued again" do
      riddle = ready_riddle()
      opted_in()
      assert {:ok, 1} = Notifications.fan_out(riddle.id, :lobby_open)

      {:ok, riddle} = Riddlr.Games.save_riddle(riddle, %{"publish_status" => "draft"})
      assert Repo.all(RiddleNotification) == []

      later = DateTime.utc_now() |> DateTime.add(7200, :second) |> DateTime.truncate(:second)

      {:ok, riddle} =
        Riddlr.Games.save_riddle(riddle, %{"publish_status" => "published", "live_date" => later})

      {:ok, _} = Riddlr.Games.transition(riddle.id, :ready)
      assert {:ok, 1} = Notifications.fan_out(riddle.id, :lobby_open)
    end

    test "skips a riddle that is no longer upcoming" do
      riddle = ready_riddle()
      opted_in()
      {:ok, _} = Riddlr.Games.save_riddle(riddle, %{"publish_status" => "draft"})

      assert {:skip, _reason} = Notifications.fan_out(riddle.id, :lobby_open)
      assert {:skip, _reason} = Notifications.fan_out(-1, :lobby_open)
      refute_enqueued(worker: SendNotificationWorker)
    end
  end

  describe "unsubscribe/1" do
    test "turns email off for the player in the token" do
      user = opted_in()
      other = opted_in()

      assert {:ok, %{notify_email: false}} =
               user |> Notifications.unsubscribe_token() |> Notifications.unsubscribe()

      refute Repo.reload!(user).notify_email
      assert Repo.reload!(other).notify_email
    end

    test "rejects a bad token" do
      assert {:error, :invalid} = Notifications.unsubscribe("nope")

      login_salted = Phoenix.Token.sign(RiddlrWeb.Endpoint, "other salt", opted_in().id)
      assert {:error, :invalid} = Notifications.unsubscribe(login_salted)
    end
  end

  describe "deliver/1" do
    alias Riddlr.Clock.Frozen

    setup do
      riddle = ready_riddle() |> Repo.preload(:category)
      user = opted_in()
      {:ok, 1} = Notifications.fan_out(riddle.id, :lobby_open)
      row = Repo.get_by!(RiddleNotification, riddle_id: riddle.id, user_id: user.id)
      Frozen.freeze(DateTime.add(riddle.live_date, -600, :second))

      %{riddle: riddle, user: user, row: row}
    end

    test "emails the player and stamps sent_at", %{riddle: riddle, user: user, row: row} do
      assert {:ok, sent} = Notifications.deliver(row.id)
      assert sent.sent_at

      assert_received {:email, %{subject: "Riddle No. " <> _} = email}
      assert email.to == [{"", user.email}]
      assert email.subject == "Riddle No. #{riddle.number} goes live in 10 min"
      assert email.text_body =~ "/game/#{riddle.id}/lobby"
      assert email.text_body =~ riddle.category.name
      assert email.text_body =~ "/notifications/unsubscribe/"
      refute email.text_body =~ riddle.description

      assert email.headers["List-Unsubscribe"] =~ "/notifications/unsubscribe/"
      assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
    end

    test "sends once, however often it runs", %{row: row} do
      assert {:ok, _} = Notifications.deliver(row.id)
      assert {:skip, _} = Notifications.deliver(row.id)

      assert_received {:email, %{subject: "Riddle No. " <> _}}
      refute_received {:email, %{subject: "Riddle No. " <> _}}
    end

    test "skips an unscheduled riddle", %{riddle: riddle, row: row} do
      {:ok, _} = Riddlr.Games.save_riddle(riddle, %{"publish_status" => "draft"})

      assert {:skip, _} = Notifications.deliver(row.id)
      refute_received {:email, %{subject: "Riddle No. " <> _}}
    end

    test "skips once the Live date has passed", %{riddle: riddle, row: row} do
      Frozen.freeze(riddle.live_date)

      assert {:skip, _} = Notifications.deliver(row.id)
      refute_sent_notification(row)
    end

    test "skips a player who opted out or was banned since", %{user: user, row: row} do
      user |> Ecto.Changeset.change(notify_email: false) |> Repo.update!()
      assert {:skip, _} = Notifications.deliver(row.id)

      user
      |> Repo.reload!()
      |> Ecto.Changeset.change(notify_email: true, account_status: :banned)
      |> Repo.update!()

      assert {:skip, _} = Notifications.deliver(row.id)

      refute_sent_notification(row)
    end

    test "skips a row that no longer exists" do
      assert {:skip, _} = Notifications.deliver(-1)
    end

    test "returns the error and leaves the row unsent when delivery fails", %{row: row} do
      assert {:error, :provider_down} =
               Notifications.deliver(row.id, mailer_config: [adapter: __MODULE__.DownAdapter])

      assert Repo.reload!(row).sent_at == nil
    end
  end

  defmodule DownAdapter do
    use Swoosh.Adapter

    @impl true
    def deliver(_email, _config), do: {:error, :provider_down}
  end

  defp refute_sent_notification(row) do
    refute_received {:email, %{subject: "Riddle No. " <> _}}
    assert Repo.reload!(row).sent_at == nil
  end
end
