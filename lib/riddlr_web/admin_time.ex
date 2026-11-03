defmodule RiddlrWeb.AdminTime do
  @moduledoc """
  Converts times for the admin riddle pages. Admins read and type times in
  Eastern (America/New_York); the database holds UTC.

  Player screens use `RiddlrWeb.DropTime` instead.
  """

  @doc """
  Converts a datetime string from a datetime-local input to UTC.
  Assumes the input is in America/New_York timezone (EST/EDT).
  Handles both formats: "2026-03-10T14:27" and "2026-03-10T14:27:00"
  """
  @spec to_utc_datetime(term()) :: DateTime.t() | nil
  def to_utc_datetime(datetime_string) when is_binary(datetime_string) do
    # datetime-local inputs may send without seconds, so append ":00" if needed
    datetime_string_with_seconds =
      if String.length(datetime_string) == 16 do
        datetime_string <> ":00"
      else
        datetime_string
      end

    case NaiveDateTime.from_iso8601(datetime_string_with_seconds) do
      {:ok, naive_datetime} ->
        # datetime-local input provides time in user's local timezone (America/New_York for admins)
        # Convert from EST/EDT to UTC
        naive_datetime
        |> eastern_instant()
        |> DateTime.shift_zone!("Etc/UTC")

      _ ->
        nil
    end
  end

  def to_utc_datetime(_), do: nil

  # When the clocks go back, an hour happens twice: take the first one. When
  # they go forward, an hour never happens: take the moment after the jump.
  @spec eastern_instant(NaiveDateTime.t()) :: DateTime.t()
  defp eastern_instant(naive_datetime) do
    case DateTime.from_naive(naive_datetime, "America/New_York") do
      {:ok, datetime} -> datetime
      {:ambiguous, first, _second} -> first
      {:gap, _just_before, just_after} -> just_after
    end
  end

  @doc """
  Converts a UTC datetime to America/New_York timezone for datetime-local input.
  Returns ISO8601 string without timezone suffix (required by datetime-local).
  """
  @spec to_local_input(term()) :: String.t() | nil
  def to_local_input(datetime) when is_struct(datetime, DateTime) do
    case to_est_datetime(datetime) do
      nil -> nil
      est_datetime -> NaiveDateTime.to_iso8601(DateTime.to_naive(est_datetime))
    end
  end

  def to_local_input(_), do: nil

  @doc """
  Shifts a UTC datetime to America/New_York. Returns nil for anything else.
  """
  @spec to_est_datetime(term()) :: DateTime.t() | nil
  def to_est_datetime(datetime) when is_struct(datetime, DateTime) do
    case DateTime.shift_zone(datetime, "America/New_York") do
      {:ok, est_datetime} ->
        est_datetime

      _ ->
        nil
    end
  end

  def to_est_datetime(_), do: nil

  @doc """
  Formats a datetime as given, e.g. "Mar 10, 2026 14:27". Returns nil for
  anything else.
  """
  @spec ready_time_display(term()) :: String.t() | nil
  def ready_time_display(datetime) when is_struct(datetime, DateTime) do
    Calendar.strftime(datetime, "%b %-d, %Y %H:%M")
  end

  def ready_time_display(_), do: nil

  @doc """
  Formats a UTC datetime in Eastern, e.g. "Mar 10, 2026 2:27pm EDT".
  Returns nil for anything else.
  """
  @spec live_time_display(term()) :: String.t() | nil
  def live_time_display(datetime) when is_struct(datetime, DateTime) do
    case to_est_datetime(datetime) do
      nil ->
        nil

      est_datetime ->
        Calendar.strftime(est_datetime, "%b %-d, %Y %-I:%M%P %Z")
    end
  end

  def live_time_display(_), do: nil
end
