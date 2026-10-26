defmodule RiddlrWeb.GameComponents do
  @moduledoc """
  Building blocks for the player screens (Home, Lobby, Play).

  These render the `rg-` markup styled by `assets/css/game.css`.
  """
  use Phoenix.Component

  @tones ~w(hi mint sky rose paper red)

  @typedoc "A tile colour. Each one maps to a `data-tone` rule in `game.css`."
  @type tone :: String.t()

  @doc """
  Picks a tone for a name.

  Sums the name's char codes and takes the result mod the number of tones,
  so the same name always gets the same tone. Pass the current user's name
  as `me` to give that player `"hi"`.
  """
  @spec tone(String.t(), String.t() | nil) :: tone()
  def tone(name, me \\ nil)

  def tone(name, name) when is_binary(name), do: "hi"

  def tone(name, _me) when is_binary(name) do
    sum = name |> String.to_charlist() |> Enum.sum()
    Enum.at(@tones, rem(sum, length(@tones)))
  end

  @doc """
  The letter shown on a player's tile: the first letter or digit of the name,
  upper-cased, or `"?"` when there is none.
  """
  @spec initial(String.t()) :: String.t()
  def initial(name) when is_binary(name) do
    case Regex.run(~r/[[:alnum:]]/u, name) do
      [char] -> String.upcase(char)
      nil -> "?"
    end
  end

  @doc """
  A letter tile: one character on a coloured square.
  """
  attr :initial, :string, required: true
  attr :tone, :string, default: "paper", values: @tones
  attr :size, :string, default: nil, values: [nil, "sm", "lg"]

  @spec tile(map()) :: Phoenix.LiveView.Rendered.t()
  def tile(assigns) do
    ~H"""
    <span
      class={["rg-tile", @size && "rg-tile--#{@size}"]}
      data-tone={@tone}
      aria-hidden="true"
    >{@initial}</span>
    """
  end
end
