defmodule Riddlr.Clock.System do
  @moduledoc """
  The real clock — reads straight from the runtime. Used everywhere but tests.
  """

  @behaviour Riddlr.Clock

  @impl true
  def utc_now, do: DateTime.utc_now()

  @impl true
  def monotonic_us, do: System.monotonic_time(:microsecond)
end
