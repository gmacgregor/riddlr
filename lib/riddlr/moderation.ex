defmodule Riddlr.Moderation do
  @moduledoc """
  Content moderation for player-submitted answer text.

  Two-layer check:
  1. Local blocklist — synchronous, instant
  2. External API — stubbed; fail-open on errors

  Both checks are called in `check/1`. If either flags the text, a
  `{:flagged, reason}` tuple is returned. External API errors are swallowed
  so gameplay is never blocked by API downtime.
  """

  @blocklist Application.compile_env(:riddlr, [__MODULE__, :blocklist], [
               "spam",
               "badword"
             ])

  @doc """
  Checks text for prohibited content.
  Returns `:ok` if clean, `{:flagged, reason}` if flagged.
  """
  def check(text) do
    with :ok <- local_blocklist_check(text),
         :ok <- external_api_check(text) do
      :ok
    end
  end

  defp local_blocklist_check(text) do
    normalized = String.downcase(text)

    if Enum.any?(@blocklist, &String.contains?(normalized, &1)) do
      {:flagged, :local_blocklist}
    else
      :ok
    end
  end

  # Stub — always passes. Replace with real API call (e.g. Google Perspective)
  # when ready. Fail-open: any error returns :ok.
  defp external_api_check(_text), do: :ok
end
