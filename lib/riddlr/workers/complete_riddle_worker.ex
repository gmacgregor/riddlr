defmodule Riddlr.Workers.CompleteRiddleWorker do
  @moduledoc """
  Worker to complete a live riddle once its solve_time expires. Guards live in
  `Games.transition/3`, which refuses to complete a `live_until_solved` riddle
  on this (solver-less) path.
  """
  use Oban.Worker,
    queue: :game_lifecycle,
    max_attempts: 3,
    unique: [period: {1, :hour}, keys: [:riddle_id]]

  alias Riddlr.Gameplay
  alias Riddlr.Workers.Transition

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"riddle_id" => id}}) do
    Transition.run(id, :completed, Gameplay.get_completion_stats(id))
  end
end
