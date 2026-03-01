defmodule Riddlr.Workers.ReadyRiddleTransitionWorker do
  @moduledoc """
  Worker to transition a riddle from scheduled to ready state (5 min before live).
  Idempotent: cancels if riddle is not in scheduled state.
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
        if riddle.play_status == "scheduled" do
          case Games.ready_riddle(id) do
            {:ok, _riddle} -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          {:cancel, "Already transitioned (current: #{riddle.play_status})"}
        end
    end
  end
end
