defmodule Riddlr.Workers.Transition do
  @moduledoc """
  Oban plumbing for Play status transitions.

  Calls `Riddlr.Games.transition/3` and maps its result onto Oban's return
  contract. The three permanent failures — missing riddle, unpublished riddle,
  forbidden transition — cancel the job instead of burning retries. Only a
  failed write is retried.
  """

  alias Riddlr.Games

  def run(riddle_id, to, stats \\ %{}) do
    riddle_id
    |> Games.transition(to, stats)
    |> to_oban_result(riddle_id)
  end

  defp to_oban_result({:ok, _riddle}, _riddle_id), do: :ok

  defp to_oban_result({:error, :not_found}, riddle_id),
    do: {:cancel, "Riddle #{riddle_id} not found"}

  defp to_oban_result({:unpublished, publish_status}, _riddle_id),
    do: {:cancel, "Riddle not published (current: #{publish_status})"}

  defp to_oban_result({:invalid, from, to}, _riddle_id),
    do: {:cancel, "cannot transition from #{from} to #{to}"}

  defp to_oban_result({:error, changeset}, _riddle_id), do: {:error, changeset}
end
