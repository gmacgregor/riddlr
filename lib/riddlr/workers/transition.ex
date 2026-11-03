defmodule Riddlr.Workers.Transition do
  @moduledoc """
  Oban plumbing for Play status transitions.

  Calls `Riddlr.Games.transition/3` and maps its result onto Oban's return
  contract. The three permanent failures — missing riddle, unpublished riddle,
  forbidden transition — cancel the job instead of burning retries. Only a
  failed write is retried.
  """

  alias Riddlr.Games
  alias Riddlr.Games.Transitions

  @typedoc "What a transition job returns to Oban."
  @type oban_result :: :ok | {:cancel, String.t()} | {:error, Ecto.Changeset.t()}

  @doc "Moves a riddle to the `to` play status and returns the result Oban expects."
  @spec run(integer(), Transitions.status(), map()) :: oban_result()
  def run(riddle_id, to, stats \\ %{}) do
    riddle_id
    |> Games.transition(to, stats)
    |> to_oban_result(riddle_id)
  end

  @spec to_oban_result(Transitions.result(), integer()) :: oban_result()
  defp to_oban_result({:ok, _riddle}, _riddle_id), do: :ok

  defp to_oban_result({:error, :not_found}, riddle_id),
    do: {:cancel, "Riddle #{riddle_id} not found"}

  defp to_oban_result({:unpublished, publish_status}, _riddle_id),
    do: {:cancel, "Riddle not published (current: #{publish_status})"}

  defp to_oban_result({:invalid, from, to}, _riddle_id),
    do: {:cancel, "cannot transition from #{from} to #{to}"}

  defp to_oban_result({:error, changeset}, _riddle_id), do: {:error, changeset}
end
