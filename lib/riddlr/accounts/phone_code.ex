defmodule Riddlr.Accounts.PhoneCode do
  @moduledoc """
  One code texted to a player to prove they own a phone number.

  The row holds the pending number (encrypted) until the right code comes
  back or the code expires. Only then does the number reach `users`. See
  `docs/adr/0002-phone-storage.md`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Riddlr.Accounts.User

  @type t :: %__MODULE__{}

  @code_digits 6
  @max_attempts 5
  @ttl_seconds 10 * 60

  @doc "How many minutes a code works for."
  @spec ttl_minutes() :: pos_integer()
  def ttl_minutes, do: div(@ttl_seconds, 60)
  @user_hourly_limit 3

  @doc "How many codes one player may get per hour."
  @spec user_hourly_limit() :: pos_integer()
  def user_hourly_limit, do: @user_hourly_limit

  @number_daily_limit 5

  @doc "How many codes one number may get per day, across all accounts."
  @spec number_daily_limit() :: pos_integer()
  def number_daily_limit, do: @number_daily_limit

  @doc "How many wrong tries a code allows."
  @spec max_attempts() :: pos_integer()
  def max_attempts, do: @max_attempts

  @doc """
  Checks `code` against a pending row. `:invalid_code` means a wrong guess that
  should use up a try; the other errors use none.
  """
  @spec check(t() | nil, String.t()) ::
          :ok | {:error, :no_code | :expired | :too_many_attempts | :invalid_code}
  def check(%__MODULE__{phone: phone, code_hash: code_hash} = phone_code, code)
      when is_binary(phone) and is_binary(code_hash) do
    cond do
      expired?(phone_code) -> {:error, :expired}
      phone_code.attempts >= @max_attempts -> {:error, :too_many_attempts}
      Plug.Crypto.secure_compare(hash_code(code), code_hash) -> :ok
      true -> {:error, :invalid_code}
    end
  end

  def check(_phone_code, _code), do: {:error, :no_code}

  @doc "Whether the code is past its #{div(@ttl_seconds, 60)}-minute window."
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{inserted_at: sent_at}) do
    DateTime.diff(Riddlr.Clock.utc_now(), sent_at) >= @ttl_seconds
  end

  @doc "Whether the code has had every wrong try it allows."
  @spec used_up?(t()) :: boolean()
  def used_up?(%__MODULE__{attempts: attempts}), do: attempts >= @max_attempts

  @doc "The send time before which codes have expired."
  @spec expiry_cutoff() :: DateTime.t()
  def expiry_cutoff, do: DateTime.add(Riddlr.Clock.utc_now(), -@ttl_seconds, :second)

  schema "phone_codes" do
    belongs_to :user, User
    field :phone, Riddlr.Encrypted.Binary, redact: true
    field :phone_hash, Riddlr.Hashed.HMAC, redact: true
    field :code_hash, :binary, redact: true
    field :attempts, :integer, default: 0

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  A changeset for a new code to the number in `attrs["phone"]`. The number
  must be a valid Canadian number; it is stored in E.164 form.
  """
  @spec request_changeset(t(), map()) :: Ecto.Changeset.t()
  def request_changeset(phone_code, attrs) do
    phone_code
    |> cast(attrs, [:phone])
    |> validate_required([:phone], message: "Invalid phone number")
    |> validate_canadian_phone()
  end

  defp validate_canadian_phone(%{changes: %{phone: raw}} = changeset) do
    case parse_canadian(raw) do
      {:ok, e164} ->
        changeset
        |> put_change(:phone, e164)
        |> put_change(:phone_hash, e164)

      {:error, message} ->
        add_error(changeset, :phone, message)
    end
  end

  defp validate_canadian_phone(changeset), do: changeset

  @doc """
  A new random #{@code_digits}-digit code, as a string with leading zeros.
  """
  @spec generate_code() :: String.t()
  def generate_code do
    <<n::unsigned-64>> = :crypto.strong_rand_bytes(8)

    n
    |> rem(Integer.pow(10, @code_digits))
    |> Integer.to_string()
    |> String.pad_leading(@code_digits, "0")
  end

  @doc "The stored form of a code."
  @spec hash_code(String.t()) :: binary()
  def hash_code(code), do: :crypto.hash(:sha256, code)

  @doc """
  Parses a number as typed into E.164. Numbers with no country code are read
  as Canadian.
  """
  @spec parse_canadian(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_canadian(raw) when is_binary(raw) do
    error_msg = "Provide a Canadian phone number"

    with {:ok, number} <- ExPhoneNumber.parse(raw, "CA"),
         true <- ExPhoneNumber.is_valid_number?(number) do
      if ExPhoneNumber.Metadata.get_region_code_for_number(number) == "CA" do
        {:ok, ExPhoneNumber.format(number, :e164)}
      else
        {:error, error_msg}
      end
    else
      _ -> {:error, error_msg}
    end
  end
end
