defmodule Riddlr.Workers.LiveRiddleTransitionWorker do
  @moduledoc """
  Worker to transition a riddle from ready to live state (at scheduled live_date).
  Idempotent: cancels if riddle is not in ready state.
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
        cond do
          riddle.publish_status != "published" ->
            {:cancel, "Riddle not published (current: #{riddle.publish_status})"}

          riddle.play_status != "ready" ->
            {:cancel, "Already transitioned (current: #{riddle.play_status})"}

          true ->
            case Games.start_riddle(id) do
              {:ok, _riddle} -> :ok
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end
end
