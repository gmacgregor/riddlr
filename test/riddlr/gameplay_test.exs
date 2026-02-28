defmodule Riddlr.GameplayTest do
  use ExUnit.Case, async: true

  alias Riddlr.Gameplay

  test "context module exists" do
    assert Code.ensure_loaded?(Gameplay)
  end
end
