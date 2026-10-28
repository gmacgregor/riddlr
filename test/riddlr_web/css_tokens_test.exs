defmodule RiddlrWeb.CssTokensTest do
  # Colour tokens carry role names so they stay true in every colour mode.
  # This test fails if an old colour-named token or tile tone comes back.
  use ExUnit.Case, async: true

  @css_dir Path.expand("../../assets/css", __DIR__)

  @old_tokens ~w(--ink --paper --hi --red --mint --sky --rose --on-light --on-paper --line --muted --dim)
  @old_tones ~w(hi mint sky rose paper red)

  defp css_files, do: Path.wildcard(Path.join(@css_dir, "*.css"))

  test "no stylesheet uses an old colour token name" do
    for file <- css_files(), token <- @old_tokens do
      # Matches the name and any suffixed form (--ink-2, --hi-press).
      refute File.read!(file) =~ ~r/#{Regex.escape(token)}(?!\w)/,
             "#{Path.basename(file)} still uses #{token}"
    end
  end

  test "no stylesheet keys a tile on a colour name" do
    for file <- css_files(), tone <- @old_tones do
      refute File.read!(file) =~ ~s(data-tone="#{tone}"),
             "#{Path.basename(file)} still has data-tone=\"#{tone}\""
    end
  end
end
