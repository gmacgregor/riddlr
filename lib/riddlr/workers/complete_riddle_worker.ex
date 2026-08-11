defmodule Riddlr.Workers.CompleteRiddleWorker do
  @moduledoc """
  Worker to complete a live riddle once its solve_time expires. Every riddle has
  a solve_time, so this is the only thing that ends a round. Guards live in
  `Games.transition/3`.
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
