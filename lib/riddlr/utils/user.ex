defmodule Riddlr.Utils.User do
  @spec is_banned?(map()) :: boolean()
  def is_banned?(user) do
    user.account_status == :banned
  end
end
