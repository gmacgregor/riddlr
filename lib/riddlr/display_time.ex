defmodule Riddlr.DisplayTime do
  @moduledoc """
  The display time zone (`:riddlr, :display_time_zone`, `America/Toronto` by
  default). Riddlr stores every instant in UTC and shows it to admins and
  players in this zone. A "day" in the game, such as a season's first or last
  day, is a calendar day in this zone.
  """

  @doc "The display time zone, e.g. `America/Toronto`."
  @spec zone() :: String.t()
  def zone, do: Application.fetch_env!(:riddlr, :display_time_zone)

  @doc """
  The UTC instant at which `date` starts in the display time zone.

      iex> Riddlr.DisplayTime.day_start(~D[2030-07-01])
      ~U[2030-07-01 04:00:00Z]
  """
  @spec day_start(Date.t()) :: DateTime.t()
  def day_start(%Date{} = date) do
    local =
      case DateTime.new(date, ~T[00:00:00], zone()) do
        {:ok, local} -> local
        # A clock change at midnight skips or repeats it. The day starts at
        # the first instant that exists.
        {:gap, _before, after_gap} -> after_gap
        {:ambiguous, first, _second} -> first
      end

    DateTime.shift_zone!(local, "Etc/UTC")
  end

  @doc """
  The calendar day, in the display time zone, that holds `instant`.

      iex> Riddlr.DisplayTime.to_date(~U[2030-07-01 03:59:59Z])
      ~D[2030-06-30]
  """
  @spec to_date(DateTime.t()) :: Date.t()
  def to_date(%DateTime{} = instant) do
    instant |> DateTime.shift_zone!(zone()) |> DateTime.to_date()
  end
end
