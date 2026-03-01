defmodule Riddlr.Workers.ArchiveRiddleTransitionWorker do
  @moduledoc """
  Worker to transition a riddle from completed to archived state.
  Idempotent: cancels if riddle is not in completed state.
  """
  use Oban.Worker,
    queue: :game_lifecycle,
    max_attempts: 3,
    unique: [period: {1, :hour}, keys: [:riddle_id]]

  alias Riddlr.{Games, Repo}
  alias Riddlr.Games.Riddle

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"riddle_id" => id}}) do
    case Repo.get(Riddle, id) do
      nil ->
        {:cancel, "Riddle #{id} not found"}

      riddle ->
        if riddle.play_status == "completed" do
          case Games.archive_riddle(id) do
            {:ok, _riddle} -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          {:cancel, "Already transitioned (current: #{riddle.play_status})"}
        end
    end
  end
end
