defmodule Riddlr.ModerationTest do
  use ExUnit.Case, async: true

  alias Riddlr.Moderation

  describe "check/1" do
    test "returns :ok for clean text" do
      assert Moderation.check("the eiffel tower") == :ok
    end

    test "flags text containing a blocklisted word" do
      assert Moderation.check("this is spam") == {:flagged, :local_blocklist}
    end

    test "blocklist check is case-insensitive" do
      assert Moderation.check("THIS IS SPAM") == {:flagged, :local_blocklist}
    end

    test "flags partial word match (substring)" do
      assert Moderation.check("nospam allowed") == {:flagged, :local_blocklist}
    end

    test "returns :ok for empty string" do
      assert Moderation.check("") == :ok
    end
  end
end
