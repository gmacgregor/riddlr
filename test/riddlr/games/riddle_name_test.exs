defmodule Riddlr.Games.RiddleNameTest do
  use ExUnit.Case, async: true

  alias Riddlr.Games.RiddleName

  doctest RiddleName

  describe "generate/0" do
    test "returns two capitalized words" do
      name = RiddleName.generate()

      assert name =~ ~r/^[A-Z][a-z]+ [A-Z][a-z]+$/
    end

    test "picks from the full list of names" do
      assert RiddleName.generate() in RiddleName.all()
    end
  end
end
