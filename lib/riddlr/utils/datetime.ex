defmodule Riddlr.Utils.Datetime do
  @doc """
  Converts a datetime string from a datetime-local input to UTC.
  Assumes the input is in America/New_York timezone (EST/EDT).
  Handles both formats: "2026-03-10T14:27" and "2026-03-10T14:27:00"
  """
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
        DateTime.from_naive!(naive_datetime, "America/New_York")
        |> DateTime.shift_zone!("Etc/UTC")

      _ ->
        nil
    end
  end

  def to_utc_datetime(_), do: nil

  @doc """
  Converts a UTC datetime to America/New_York timezone for datetime-local input.
  Returns ISO8601 string without timezone suffix (required by datetime-local).
  """
  def to_local_input(datetime) when is_struct(datetime, DateTime) do
    case to_est_datetime(datetime) do
      nil -> nil
      est_datetime -> NaiveDateTime.to_iso8601(DateTime.to_naive(est_datetime))
    end
  end

  def to_local_input(_), do: nil

  def to_est_datetime(datetime) when is_struct(datetime, DateTime) do
    case DateTime.shift_zone(datetime, "America/New_York") do
      {:ok, est_datetime} ->
        est_datetime

      _ ->
        nil
    end
  end

  def to_est_datetime(_), do: nil

  def ready_time_display(datetime) when is_struct(datetime, DateTime) do
    Calendar.strftime(datetime, "%b %-d, %Y %H:%M")
  end

  def ready_time_display(_), do: nil

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
