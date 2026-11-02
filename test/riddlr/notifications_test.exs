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

  # A player with a confirmed number and Text on. Each gets their own number.
  defp texting(attrs \\ %{}) do
    last4 = rem(System.unique_integer([:positive]), 10_000)
    phone = "+1416555" <> String.pad_leading("#{last4}", 4, "0")

    user_fixture()
    |> Ecto.Changeset.change(
      Map.merge(
        %{
          notify_sms: true,
          phone: phone,
          phone_hash: phone,
          phone_confirmed_at: DateTime.utc_now(:second)
        },
        attrs
      )
    )
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

    test "adds an :sms row for each player with Text on and a confirmed number" do
      riddle = ready_riddle()
      both = texting(%{notify_email: true})
      text_only = texting()

      texting(%{phone: nil, phone_hash: nil, phone_confirmed_at: nil})
      texting(%{notify_sms: false})
      texting(%{account_status: :suspended})
      texting(%{account_status: :banned})
      texting(%{notification_lead_time: :min_30})

      assert {:ok, 3} = Notifications.fan_out(riddle.id, :lobby_open)

      rows = Repo.all(from n in RiddleNotification, select: {n.user_id, n.channel})

      assert Enum.sort(rows) ==
               Enum.sort([{both.id, :email}, {both.id, :sms}, {text_only.id, :sms}])

      assert [_, _, _] = all_enqueued(worker: SendNotificationWorker)
      assert {:ok, 0} = Notifications.fan_out(riddle.id, :lobby_open)
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

  describe "timed lead times" do
    test "a riddle scheduled 20 min out sends 30 min and 1 hour Notifications at once" do
      min_30 = opted_in(%{notification_lead_time: :min_30})
      min_60 = opted_in(%{notification_lead_time: :min_60})
      riddle = scheduled_riddle_fixture(%{live_date: from_now(20 * 60)})

      due_now = due_fan_outs(riddle.id)
      assert due_now |> Enum.map(& &1.args["lead_time"]) |> Enum.sort() == ["min_30", "min_60"]

      run_fan_outs_and_sends(due_now)

      assert_received {:email, %{subject: "Kriddle riddle No. " <> _, to: [{_, email_a}]}}
      assert_received {:email, %{subject: "Kriddle riddle No. " <> _, to: [{_, email_b}]}}
      assert Enum.sort([email_a, email_b]) == Enum.sort([min_30.email, min_60.email])
    end

    test "before the Lobby opens, the email links Home, not the Lobby" do
      opted_in(%{notification_lead_time: :min_60})
      riddle = scheduled_riddle_fixture(%{live_date: from_now(50 * 60)})
      run_fan_outs_and_sends(due_fan_outs(riddle.id))

      assert_received {:email, %{subject: "Kriddle riddle No. " <> _} = email}
      assert email.subject =~ "50 min"
      refute email.text_body =~ "/lobby"
      assert email.text_body =~ RiddlrWeb.Endpoint.url() <> "/\n"
    end

    test "a player notified when the Lobby opened gets nothing after switching to 30 min" do
      user = opted_in()
      riddle = ready_riddle()
      assert {:ok, 1} = Notifications.fan_out(riddle.id, :lobby_open)

      {:ok, _} =
        Riddlr.Accounts.update_user_notifications(user, %{notification_lead_time: :min_30})

      assert {:ok, 0} = Notifications.fan_out(riddle.id, :min_30)
    end

    test "a player already notified gets nothing after a Reschedule" do
      opted_in(%{notification_lead_time: :min_60})
      riddle = scheduled_riddle_fixture(%{live_date: from_now(20 * 60)})
      run_fan_outs_and_sends(due_fan_outs(riddle.id))
      assert_received {:email, %{subject: "Kriddle riddle No. " <> _}}

      {:ok, _} = Riddlr.Games.save_riddle(riddle, %{"live_date" => from_now(25 * 60)})

      run_fan_outs_and_sends(due_fan_outs(riddle.id))
      refute_received {:email, %{subject: "Kriddle riddle No. " <> _}}
    end
  end

  defp from_now(seconds),
    do: DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)

  # Fan-out jobs for the riddle that are due now.
  defp due_fan_outs(riddle_id) do
    now = DateTime.utc_now()

    all_enqueued(worker: Riddlr.Workers.NotificationFanOutWorker, args: %{riddle_id: riddle_id})
    |> Enum.filter(&(DateTime.compare(&1.scheduled_at, now) != :gt))
  end

  defp run_fan_outs_and_sends(fan_outs) do
    for job <- fan_outs do
      assert :ok = perform_job(Riddlr.Workers.NotificationFanOutWorker, job.args)
    end

    for job <- all_enqueued(worker: SendNotificationWorker) do
      perform_job(SendNotificationWorker, job.args)
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

      assert_received {:email, %{subject: "Kriddle riddle No. " <> _} = email}
      assert email.to == [{"", user.email}]
      assert email.subject == "Kriddle riddle No. #{riddle.number} goes live in 10 min"
      assert email.text_body =~ "/game/#{riddle.id}/lobby"
      assert email.text_body =~ riddle.category.name
      assert email.text_body =~ "/notifications/unsubscribe/"
      assert email.text_body =~ Application.fetch_env!(:riddlr, :info_url)
      refute email.text_body =~ riddle.description

      assert email.headers["List-Unsubscribe"] =~ "/notifications/unsubscribe/"
      assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
    end

    test "sends once, however often it runs", %{row: row} do
      assert {:ok, _} = Notifications.deliver(row.id)
      assert {:skip, _} = Notifications.deliver(row.id)

      assert_received {:email, %{subject: "Kriddle riddle No. " <> _}}
      refute_received {:email, %{subject: "Kriddle riddle No. " <> _}}
    end

    test "skips an unscheduled riddle", %{riddle: riddle, row: row} do
      {:ok, _} = Riddlr.Games.save_riddle(riddle, %{"publish_status" => "draft"})

      assert {:skip, _} = Notifications.deliver(row.id)
      refute_received {:email, %{subject: "Kriddle riddle No. " <> _}}
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

  describe "deliver/1 for Text" do
    alias Riddlr.Clock.Frozen

    # Every GSM-7 basic character; a text with only these fits 160 per segment.
    @gsm7 ~c"@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"

    setup do
      riddle = ready_riddle() |> Repo.preload(:category)
      user = texting()
      {:ok, 1} = Notifications.fan_out(riddle.id, :lobby_open)
      row = Repo.get_by!(RiddleNotification, riddle_id: riddle.id, user_id: user.id)
      Frozen.freeze(DateTime.add(riddle.live_date, -1800, :second))

      %{riddle: riddle, user: user, row: row}
    end

    test "texts the player once, in one GSM-7 segment, with no riddle text",
         %{riddle: riddle, user: user, row: row} do
      assert {:ok, %{sent_at: %DateTime{}}} = Notifications.deliver(row.id)
      assert {:skip, _} = Notifications.deliver(row.id)

      assert_received {:sms, %{to: to, body: body}}
      refute_received {:sms, _}

      assert to == user.phone
      assert body =~ "Riddle No. #{riddle.number} goes live in 30 min"
      assert body =~ "/game/#{riddle.id}/lobby"
      assert body =~ Application.fetch_env!(:riddlr, :info_url)
      assert body =~ "Reply STOP to end"
      refute body =~ riddle.description

      assert String.length(body) <= 160
      assert body |> String.to_charlist() |> Enum.all?(&(&1 in @gsm7))
    end

    test "skips a player who paused Text, removed the number, or was suspended",
         %{user: user, row: row} do
      eligible = Map.take(user, [:notify_sms, :phone, :phone_hash, :phone_confirmed_at])

      for change <- [
            %{notify_sms: false},
            %{phone: nil, phone_hash: nil, phone_confirmed_at: nil},
            %{account_status: :suspended}
          ] do
        user |> Ecto.Changeset.change(change) |> Repo.update!()
        assert {:skip, _} = Notifications.deliver(row.id)

        user
        |> Repo.reload!()
        |> Ecto.Changeset.change(Map.put(eligible, :account_status, :active))
        |> Repo.update!()
      end

      refute_received {:sms, _}
      assert Repo.reload!(row).sent_at == nil
    end

    test "skips after Unschedule", %{riddle: riddle, row: row} do
      {:ok, _} = Riddlr.Games.save_riddle(riddle, %{"publish_status" => "draft"})

      assert {:skip, _} = Notifications.deliver(row.id)
      refute_received {:sms, _}
    end
  end

  describe "deliver_sms_confirmation/1" do
    test "texts the player once Text is on" do
      user = texting()

      assert :ok = Notifications.deliver_sms_confirmation(user.id)
      assert_received {:sms, %{to: to, body: body}}
      assert to == user.phone
      assert body =~ "Kriddle"
      assert body =~ "Reply STOP to end"
    end

    test "skips a player with Text off, no number, or a banned account" do
      for user <- [
            texting(%{notify_sms: false}),
            texting(%{phone: nil, phone_hash: nil, phone_confirmed_at: nil}),
            texting(%{account_status: :banned})
          ] do
        assert {:skip, _} = Notifications.deliver_sms_confirmation(user.id)
      end

      refute_received {:sms, _}
    end
  end

  defmodule DownAdapter do
    use Swoosh.Adapter

    @impl true
    def deliver(_email, _config), do: {:error, :provider_down}
  end

  defp refute_sent_notification(row) do
    refute_received {:email, %{subject: "Kriddle riddle No. " <> _}}
    assert Repo.reload!(row).sent_at == nil
  end
end
