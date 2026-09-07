defmodule Riddlr.ModerationTest do
  use ExUnit.Case, async: true

  alias Riddlr.Moderation

  @mask Moderation.mask()
  @bad_word Riddlr.ModerationFixtures.bad_word()
  @bad_phrase Riddlr.ModerationFixtures.bad_phrase()

  describe "obfuscate/1" do
    test "returns clean text unchanged" do
      assert Moderation.obfuscate("the eiffel tower") == "the eiffel tower"
    end

    test "returns empty string for empty input" do
      assert Moderation.obfuscate("") == ""
    end

    test "masks a single banned word" do
      assert Moderation.obfuscate("this is #{@bad_word}") == "this is #{@mask}"
    end

    test "matching is case-insensitive" do
      assert Moderation.obfuscate("THIS IS #{@bad_word}") == "THIS IS #{@mask}"
    end

    test "does not mask a word that merely contains a banned word as a substring" do
      assert Moderation.obfuscate("no#{@bad_word} allowed") == "no#{@bad_word} allowed"
    end

    test "masks a multi-word phrase, absorbing the space between its words" do
      assert Moderation.obfuscate("that was a #{@bad_phrase} idea") == "that was a #{@mask} idea"
    end

    test "masks a multi-word phrase across extra punctuation and whitespace" do
      assert Moderation.obfuscate("that was #{@bad_phrase} idea") == "that was #{@mask} idea"
    end

    test "prefers the longest matching phrase over a shorter one it contains" do
      assert Moderation.obfuscate("that was #{@bad_phrase}") == "that was #{@mask}"
    end

    test "still matches the shorter entry alone when the longer phrase isn't present" do
      assert Moderation.obfuscate("that was really #{@bad_phrase}") == "that was really #{@mask}"
    end
  end

  describe "check_external/1" do
    test "always passes (stub, fails open)" do
      assert Moderation.check_external("anything at all") == :ok
    end
  end
end
