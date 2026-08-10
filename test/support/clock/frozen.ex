defmodule Riddlr.Clock.Frozen do
  @moduledoc """
  The test clock. Reads pass through to the system clock until a test calls
  `freeze/1`, after which time only moves when `advance/2` says so.

      Frozen.freeze(riddle.live_date)
      Gameplay.submit_answer(riddle, user, "mouse")
      Frozen.advance(1, :second)
      Gameplay.submit_answer(riddle, user, "keyboard")

  The frozen instant lives in `:persistent_term` because the processes that
  read the clock — LiveViews, the lobby timer, moderation tasks — are not the
  process that froze it. That makes it global: **a test that freezes must be
  `async: false`**. `freeze/1` registers an `on_exit` that unfreezes, so the
  state never outlives the test that set it.
  """

  @behaviour Riddlr.Clock

  @key {__MODULE__, :frozen_at}

  @impl true
  def utc_now do
    case frozen_state() do
      %{utc: utc} -> utc
      nil -> DateTime.utc_now()
    end
  end

  @impl true
  def monotonic_us do
    case frozen_state() do
      %{monotonic_us: us} -> us
      nil -> System.monotonic_time(:microsecond)
    end
  end

  @doc """
  Holds time at `instant` (defaults to now) until the end of the test.

  The instant must be UTC — `Riddlr.Clock.utc_now/0` is a UTC contract, and a
  zoned or naive instant only surfaces much later, in display code or an Ecto
  cast, far from the `freeze/1` call that caused it.
  """
  def freeze(instant \\ DateTime.utc_now())

  def freeze(%DateTime{time_zone: "Etc/UTC"} = instant) do
    :persistent_term.put(@key, %{
      utc: instant,
      monotonic_us: System.monotonic_time(:microsecond)
    })

    ExUnit.Callbacks.on_exit(&unfreeze/0)
    :ok
  end

  def freeze(other) do
    raise ArgumentError,
          "freeze/1 expects a UTC DateTime, got: #{inspect(other)}"
  end

  @doc """
  Steps the frozen clock forward. Both readings move by the same amount.

  Accepts `System.time_unit()` plus `:minute`, `:hour` and `:day`.
  """
  def advance(amount, unit) do
    us = to_microseconds(amount, unit)
    state = frozen_state() || raise "advance/2 called on an unfrozen clock — call freeze/1 first"

    :persistent_term.put(@key, %{
      utc: DateTime.add(state.utc, us, :microsecond),
      monotonic_us: state.monotonic_us + us
    })

    :ok
  end

  @doc """
  Hands control back to the system clock.
  """
  def unfreeze do
    :persistent_term.erase(@key)
    :ok
  end

  @doc """
  Whether time is currently held still.
  """
  def frozen?, do: frozen_state() != nil

  defp frozen_state, do: :persistent_term.get(@key, nil)

  defp to_microseconds(amount, :minute), do: to_microseconds(amount * 60, :second)
  defp to_microseconds(amount, :hour), do: to_microseconds(amount * 3600, :second)
  defp to_microseconds(amount, :day), do: to_microseconds(amount * 86_400, :second)
  defp to_microseconds(amount, unit), do: System.convert_time_unit(amount, unit, :microsecond)
end
