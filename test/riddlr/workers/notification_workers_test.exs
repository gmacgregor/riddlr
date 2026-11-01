defmodule Riddlr.Workers.NotificationWorkersTest do
  use Riddlr.DataCase, async: true
  use Oban.Testing, repo: Riddlr.Repo

  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  alias Riddlr.Notifications.RiddleNotification
  alias Riddlr.Workers.{NotificationFanOutWorker, SendNotificationWorker}

  setup do
    user_fixture() |> Ecto.Changeset.change(notify_email: true) |> Repo.update!()
    riddle = scheduled_riddle_fixture()
    {:ok, riddle} = Riddlr.Games.transition(riddle.id, :ready)
    %{riddle: riddle}
  end

  test "fan-out then send emails the player once", %{riddle: riddle} do
    args = %{"riddle_id" => riddle.id, "lead_time" => "lobby_open"}
    assert :ok = perform_job(NotificationFanOutWorker, args)

    [row] = Repo.all(from n in RiddleNotification, where: n.riddle_id == ^riddle.id)
    assert :ok = perform_job(SendNotificationWorker, %{"notification_id" => row.id})
    assert {:cancel, _} = perform_job(SendNotificationWorker, %{"notification_id" => row.id})

    assert_received {:email, %{subject: "Kriddle riddle No. " <> _}}
    refute_received {:email, %{subject: "Kriddle riddle No. " <> _}}
  end

  test "a finished fan-out does not block a new one for the same riddle", %{riddle: riddle} do
    args = %{"riddle_id" => riddle.id, "lead_time" => "lobby_open"}
    {:ok, first} = args |> NotificationFanOutWorker.new() |> Oban.insert()
    Repo.update_all(from(j in Oban.Job, where: j.id == ^first.id), set: [state: "completed"])

    {:ok, second} = args |> NotificationFanOutWorker.new() |> Oban.insert()

    refute second.conflict?
  end

  test "fan-out cancels for an unscheduled riddle", %{riddle: riddle} do
    {:ok, _} = Riddlr.Games.save_riddle(riddle, %{"publish_status" => "draft"})

    assert {:cancel, _} =
             perform_job(NotificationFanOutWorker, %{
               "riddle_id" => riddle.id,
               "lead_time" => "lobby_open"
             })
  end
end
