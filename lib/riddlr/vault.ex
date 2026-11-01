defmodule Riddlr.Vault do
  @moduledoc """
  Encrypts and decrypts sensitive fields (today: phone numbers) with
  AES-256-GCM. See `docs/adr/0002-phone-storage.md`.

  Keys come from `config :riddlr, Riddlr.Vault, keys: [...]`, a list of
  `{tag, base64_key}` pairs. The first key encrypts; every key decrypts. To
  rotate, put a new key with a new tag first, keep the old one after it, then
  re-encrypt rows with `mix cloak.migrate.ecto` and drop the old key.
  """
  use Cloak.Vault, otp_app: :riddlr

  @impl GenServer
  def init(config) do
    ciphers =
      config
      |> Keyword.fetch!(:keys)
      |> Enum.with_index()
      |> Enum.map(fn {{tag, key}, index} ->
        label = if index == 0, do: :default, else: String.to_atom(tag)
        {label, {Cloak.Ciphers.AES.GCM, tag: tag, key: Base.decode64!(key), iv_length: 12}}
      end)

    {:ok, Keyword.put(config, :ciphers, ciphers)}
  end
end
