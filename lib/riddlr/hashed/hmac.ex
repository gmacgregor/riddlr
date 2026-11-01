defmodule Riddlr.Hashed.HMAC do
  @moduledoc """
  An Ecto type that stores an HMAC-SHA256 of its value: a blind index, so a
  field can be found by value without storing the value. The secret comes from
  `config :riddlr, Riddlr.Hashed.HMAC, secret: ...` and is kept apart from the
  `Riddlr.Vault` keys.
  """
  use Cloak.Ecto.HMAC, otp_app: :riddlr

  @impl Cloak.Ecto.HMAC
  def init(config) do
    {:ok, Keyword.put(config, :algorithm, :sha256)}
  end
end
