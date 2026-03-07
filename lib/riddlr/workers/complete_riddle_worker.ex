defmodule Riddlr.Workers.CompleteRiddleWorker do
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

          riddle.play_status != "live" ->
            {:cancel, "Already transitioned (current: #{riddle.play_status})"}

          riddle.live_until_solved ->
            {:cancel, "live_until_solved is set, skipping auto-complete"}

          riddle.first_solver_id != nil ->
            {:cancel, "Riddle already solved by user #{riddle.first_solver_id}"}

          true ->
            case Games.complete_riddle(id) do
              {:ok, _riddle} -> :ok
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end
end
