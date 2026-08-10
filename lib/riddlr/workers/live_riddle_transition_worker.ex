defmodule Riddlr.Workers.LiveRiddleTransitionWorker do
  @moduledoc """
  Worker to transition a riddle from ready to live state (at scheduled
  live_date). Guards live in `Games.transition/3`.
  """
  use Oban.Worker,
    queue: :game_lifecycle,
    max_attempts: 3,
    unique: [period: {1, :hour}, keys: [:riddle_id]]

  alias Riddlr.Workers.Transition

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"riddle_id" => id}}), do: Transition.run(id, :live)
end
