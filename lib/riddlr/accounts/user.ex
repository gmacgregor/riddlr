defmodule Riddlr.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type notification_lead_time :: :lobby_open | :min_30 | :min_60

  schema "users" do
    field :email, :string
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    field :role, Ecto.Enum,
      values: [:super_admin, :moderator, :editor, :viewer, :player],
      default: :player

    field :account_status, Ecto.Enum, values: [:active, :banned, :suspended], default: :active

    field :notify_email, :boolean, default: false
    field :notify_sms, :boolean, default: false

    # Set only once a texted code proves the player owns the number. See
    # docs/adr/0002-phone-storage.md.
    field :phone, Riddlr.Encrypted.Binary, redact: true
    field :phone_hash, Riddlr.Hashed.HMAC, redact: true
    field :phone_confirmed_at, :utc_datetime

    field :notification_lead_time, Ecto.Enum,
      values: [:lobby_open, :min_30, :min_60],
      default: :lobby_open

    timestamps(type: :utc_datetime)
  end

  @doc """
  A general changeset for admin-controlled updates including role assignment.
  This should NOT be used for user-facing registration.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_inclusion(:role, [:super_admin, :moderator, :editor, :viewer, :player])
  end

  @doc """
  A changeset for a moderator setting `account_status`.
  """
  def status_changeset(user, attrs) do
    cast(user, attrs, [:account_status])
  end

  @doc """
  A changeset for a player's own notification choices.

  Casts `notify_email`, `notify_sms` and `notification_lead_time`. Text can
  turn on only with a confirmed number; turning it off keeps the number.
  """
  @spec notification_changeset(t(), map()) :: Ecto.Changeset.t()
  def notification_changeset(user, attrs) do
    user
    |> cast(attrs, [:notify_email, :notify_sms, :notification_lead_time])
    |> validate_change(:notify_sms, fn :notify_sms, on? ->
      if on? and is_nil(user.phone_confirmed_at),
        do: [notify_sms: "confirm a mobile number first"],
        else: []
    end)
  end

  @doc """
  Makes `e164` the player's confirmed number, replacing any old one. Call
  only after a texted code checks out.

  A first number turns Text on: the player reached the number step by
  ticking Text. A changed number keeps Text as it was, so paused stays paused.
  """
  @spec confirm_phone_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def confirm_phone_changeset(user, e164) do
    now = Riddlr.Clock.utc_now() |> DateTime.truncate(:second)
    notify_sms = is_nil(user.phone_confirmed_at) or user.notify_sms

    user
    |> change(phone: e164, phone_hash: e164, phone_confirmed_at: now, notify_sms: notify_sms)
    |> unique_constraint(:phone_hash,
      error_key: :phone,
      message: "is already used by another account"
    )
  end

  @doc "Wipes the player's number and turns texts off."
  @spec remove_phone_changeset(t()) :: Ecto.Changeset.t()
  def remove_phone_changeset(user) do
    change(user, phone: nil, phone_hash: nil, phone_confirmed_at: nil, notify_sms: false)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  @doc """
  A user changeset for registration.

  It requires email and username. Password is optional (used for password-based auth).
  The player may opt in to email notifications here; it stays off unless sent.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of fields, useful when displaying live validations.
      Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :username, :notify_email])
    |> validate_username(opts)
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Riddlr.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  defp trim_username(username) when is_binary(username), do: String.trim(username)
  defp trim_username(username), do: username

  # Words of letters, numbers, underscores and dashes, one space between
  # words. A single space only, so "a b" and "a  b" cannot both be taken.
  @username_format ~r/^[a-zA-Z0-9_-]+( [a-zA-Z0-9_-]+)*$/

  defp validate_username(changeset, opts) do
    changeset =
      changeset
      |> update_change(:username, &trim_username/1)
      |> validate_required([:username])
      |> validate_length(:username, min: 3, max: 25)
      |> validate_format(:username, @username_format,
        message: "must contain only letters, numbers, spaces, dashes and underscores"
      )

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:username, Riddlr.Repo)
      |> unique_constraint(:username)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = Riddlr.Clock.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Riddlr.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
