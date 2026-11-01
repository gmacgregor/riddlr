defmodule Riddlr.Encrypted.Binary do
  @moduledoc "An Ecto type stored encrypted by `Riddlr.Vault`."
  use Cloak.Ecto.Binary, vault: Riddlr.Vault
end
