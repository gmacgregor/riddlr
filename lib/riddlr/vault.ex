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

  # Cloak picks the key to decrypt by the tag stored with each value, so two
  # keys with one tag make the second key unreachable.
  @labels [:default, :old]

  @impl GenServer
  def init(config) do
    keys = Keyword.fetch!(config, :keys)
    tags = Enum.map(keys, &elem(&1, 0))

    if length(keys) > length(@labels) do
      raise ArgumentError, "Riddlr.Vault takes at most #{length(@labels)} keys"
    end

    if Enum.uniq(tags) != tags do
      raise ArgumentError, "Riddlr.Vault keys need distinct tags, got: #{inspect(tags)}"
    end

    ciphers =
      @labels
      |> Enum.zip(keys)
      |> Enum.map(fn {label, {tag, key}} ->
        {label, {Cloak.Ciphers.AES.GCM, tag: tag, key: Base.decode64!(key), iv_length: 12}}
      end)

    {:ok, Keyword.put(config, :ciphers, ciphers)}
  end
end
