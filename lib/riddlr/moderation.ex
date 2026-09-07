defmodule Riddlr.Moderation do
  @moduledoc """
  Content moderation for player-submitted text — race guesses and post-game
  chat alike (`Riddlr.Gameplay.Answer` doesn't distinguish the two).

  Two layers, deliberately run at different speeds:

  1. `obfuscate/1` — local blocklist, synchronous. Runs on the submission
     path itself: whole-word/phrase match against `priv/moderation/banned_words.txt`
     (compiled in at build time), matched spans replaced with a fixed mask.
     A single pass over the message's tokens, so it's cheap enough to never
     be worth doing async — the text that gets stored and broadcast is
     already clean, nothing to retract later.

  2. `check_external/1` — a second layer for a hosted API (e.g. a toxicity
     or slur-detection service), for text the local list can't catch.
     Stubbed to always pass. Callers run it async and fail open on error —
     see `Riddlr.Gameplay.moderate_answer_async/1` — because gameplay must
     never wait on it.
  """

  @mask "🙈🤐🙈🤐"

  @external_resource "priv/moderation/banned_words.txt"

  @banned_by_length "priv/moderation/banned_words.txt"
                    |> File.read!()
                    |> String.split("\n", trim: true)
                    |> Enum.map(&String.trim/1)
                    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
                    |> Enum.map(fn phrase -> phrase |> String.downcase() |> String.split() end)
                    |> Enum.reject(&(&1 == []))
                    |> Enum.group_by(&length/1, &Enum.join(&1, " "))
                    |> Map.new(fn {len, phrases} -> {len, MapSet.new(phrases)} end)

  @max_phrase_len @banned_by_length |> Map.keys() |> Enum.max(fn -> 1 end)

  @word_regex ~r/([\p{L}\p{N}]+)/u

  # The seam `check_external/1` calls through — a real client swaps in here
  # without touching the call site in Gameplay.
  @external_check &__MODULE__.default_external_check/1

  @typedoc """
  One stretch of tokens: kept as-is (`:keep`, its index) or replaced by the
  mask (`:mask`, first index, last index — both inclusive).
  """
  @type span :: {:keep, non_neg_integer()} | {:mask, non_neg_integer(), non_neg_integer()}

  @doc """
  The fixed-width string a matched banned word or phrase is replaced with.
  """
  @spec mask() :: String.t()
  def mask, do: @mask

  @doc """
  Replaces every banned word or phrase in `text` with a fixed-width mask.

  Matching is whole-word and case-insensitive, and a multi-word entry
  matches its words in order regardless of what punctuation or whitespace
  sits between them — that gap is absorbed into the single mask along with
  the phrase. The longest matching entry at a position wins, so a phrase
  blocks its own shorter sub-entries from also firing.

  Runs synchronously — see the moduledoc for why that's fine.
  """
  @spec obfuscate(String.t()) :: String.t()
  def obfuscate(text) do
    # Regex.split with include_captures interleaves gap and token:
    # {gap_0, token_0, gap_1, token_1, ..., gap_n}. Tokens sit at the odd
    # indices, so token k reads at 2k + 1 and the gap that follows it at
    # 2k + 2 — that's the arithmetic below and in the reduce.
    parts = @word_regex |> Regex.split(text, include_captures: true) |> List.to_tuple()
    size = tuple_size(parts)

    if size <= 1 do
      text
    else
      token_count = div(size - 1, 2)

      tokens_lower =
        for k <- 0..(token_count - 1), do: parts |> elem(2 * k + 1) |> String.downcase()

      tokens_lower
      |> spans(@max_phrase_len)
      |> Enum.reduce([elem(parts, 0)], fn
        {:keep, k}, acc -> [elem(parts, 2 * k + 2), elem(parts, 2 * k + 1) | acc]
        {:mask, _first, last}, acc -> [elem(parts, 2 * last + 2), @mask | acc]
      end)
      |> Enum.reverse()
      |> IO.iodata_to_binary()
    end
  end

  @doc """
  Placeholder for a second, external moderation layer (e.g. a hosted
  toxicity/slur-detection API). The port a real client plugs into later —
  today it's wired to `default_external_check/1`, which always passes.
  Fails open: any real implementation must resolve errors to `:ok` too.
  """
  @spec check_external(String.t()) :: :ok | {:flagged, atom()}
  def check_external(text), do: @external_check.(text)

  @doc false
  def default_external_check(_text), do: :ok

  # Walks the lowercased tokens left to right, greedily matching the longest
  # banned phrase at each position. A match skips past its own length; a
  # miss keeps one token and steps forward by one.
  @spec spans([String.t()], non_neg_integer()) :: [span()]
  defp spans(tokens_lower, max_len) do
    n = length(tokens_lower)
    tokens = List.to_tuple(tokens_lower)
    do_spans(tokens, 0, n, max_len, [])
  end

  @spec do_spans(tuple(), non_neg_integer(), non_neg_integer(), non_neg_integer(), [span()]) ::
          [span()]
  defp do_spans(_tokens, i, n, _max_len, acc) when i >= n, do: Enum.reverse(acc)

  defp do_spans(tokens, i, n, max_len, acc) do
    case longest_match(tokens, i, min(max_len, n - i)) do
      nil -> do_spans(tokens, i + 1, n, max_len, [{:keep, i} | acc])
      len -> do_spans(tokens, i + len, n, max_len, [{:mask, i, i + len - 1} | acc])
    end
  end

  # Tries phrase lengths longest first so a longer banned phrase wins over a
  # shorter one it contains (e.g. "a b c" over "b c").
  @spec longest_match(tuple(), non_neg_integer(), non_neg_integer()) :: non_neg_integer() | nil
  defp longest_match(_tokens, _i, 0), do: nil

  defp longest_match(tokens, i, max_possible) do
    Enum.find_value(max_possible..1//-1, fn len ->
      candidate = i |> phrase(tokens, len) |> Enum.join(" ")

      if MapSet.member?(Map.get(@banned_by_length, len, MapSet.new()), candidate) do
        len
      end
    end)
  end

  @spec phrase(non_neg_integer(), tuple(), non_neg_integer()) :: [String.t()]
  defp phrase(i, tokens, len), do: for(k <- i..(i + len - 1), do: elem(tokens, k))
end
