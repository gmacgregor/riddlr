defmodule Riddlr.Utils.User do
  @spec avatar_color(String.t()) :: String.t()
  def avatar_color(username) do
    colors = ~w(
      pink purple gold cyan indigo green hotpink
      orange teal violet lime amber sky rose emerald slate magenta
    )

    index = username |> String.upcase() |> String.first() |> String.to_charlist() |> hd()
    Enum.at(colors, rem(index, length(colors)))
  end

  @spec is_banned?(map()) :: boolean()
  def is_banned?(user) do
    user.account_status == :banned
  end
end
