defmodule Riddlr.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Riddlr.Repo

  alias Riddlr.Accounts.{NotificationPreferences, Phone, PhoneCode, User, UserToken, UserNotifier}

  @typedoc "What to tell a player about texts at their first log-in."
  @type text_prompt :: {:code_sent, PhoneCode.t()} | :add_number | nil

  @typedoc "A saved user and the tokens deleted with the change."
  @type user_and_expired_tokens :: {User.t(), [UserToken.t()]}

  @typedoc "Builds the link sent in an email from an encoded token."
  @type url_fun :: (String.t() -> String.t())

  @typedoc "The result of asking for a login link again."
  @type resend_result :: UserNotifier.delivery() | {:error, :too_soon}

  # How long a player waits before they can ask for another login link.
  @resend_cooldown_seconds 60

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    # Checks the password first, so a banned account takes as long to refuse.
    if User.valid_password?(user, password) and not User.banned?(user), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_user!(term()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user, or `nil` if the User does not exist.
  """
  @spec get_user(term()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @doc "Returns true if the user is banned. A guest (`nil`) is not."
  @spec banned?(User.t() | nil) :: boolean()
  defdelegate banned?(user), to: User

  ## User registration

  @doc """
  Registers a user. Opting in to email also logs a consent row in the same
  transaction. The Text opt-in is ignored while texting is off.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    NotificationPreferences.save_with_consent(
      fn -> User.registration_changeset(%User{}, attrs, text: Riddlr.SMS.enabled?()) end,
      &Repo.insert/1
    )
  end

  @doc """
  Inside a transaction: reads the stored user row and locks it until the
  transaction ends, so two saves at once see each other's changes.
  """
  @spec lock_user!(integer()) :: User.t()
  def lock_user!(id) do
    User
    |> where(id: ^id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  @spec sudo_mode?(User.t() | nil, integer()) :: boolean()
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, Riddlr.Clock.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Riddlr.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_email(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc "Returns a blank user for a registration form."
  @spec new_user() :: User.t()
  def new_user, do: %User{}

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes.
  """
  @spec change_user_registration(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  @spec update_user_email(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, :transaction_aborted}
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Riddlr.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_password(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_user_password(User.t(), map()) ::
          {:ok, user_and_expired_tokens()} | {:error, Ecto.Changeset.t()}
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Notification preferences (Riddlr.Accounts.NotificationPreferences)

  @typedoc "A way to reach a player with a Notification."
  @type notification_channel :: NotificationPreferences.notification_channel()

  @spec change_user_notifications(User.t(), map()) :: Ecto.Changeset.t()
  defdelegate change_user_notifications(user, attrs \\ %{}), to: NotificationPreferences

  @spec update_user_notifications(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_user_notifications(user, attrs), to: NotificationPreferences

  @spec notification_recipients_query(atom(), notification_channel()) :: Ecto.Query.t()
  defdelegate notification_recipients_query(lead_time, channel), to: NotificationPreferences

  @spec notifiable?(User.t(), notification_channel()) :: boolean()
  defdelegate notifiable?(user, channel), to: NotificationPreferences

  ## Phone (Riddlr.Accounts.Phone)

  @spec phone_code_ttl_minutes() :: pos_integer()
  defdelegate phone_code_ttl_minutes, to: Phone

  @spec ask_for_number?(User.t()) :: boolean()
  defdelegate ask_for_number?(user), to: Phone

  @spec text_signup_phone(User.t()) :: {:ok, PhoneCode.t()} | {:error, term()} | :none
  defdelegate text_signup_phone(user), to: Phone

  @spec send_phone_code(User.t(), map()) ::
          {:ok, PhoneCode.t()}
          | {:error, Ecto.Changeset.t() | :locked | :rate_limited | term()}
  defdelegate send_phone_code(user, attrs), to: Phone

  @spec get_pending_phone_code(User.t()) :: PhoneCode.t() | nil
  defdelegate get_pending_phone_code(user), to: Phone

  @spec resend_phone_code(User.t()) ::
          {:ok, PhoneCode.t()} | {:error, :no_code | :locked | :rate_limited | term()}
  defdelegate resend_phone_code(user), to: Phone

  @spec confirm_phone(User.t(), String.t()) ::
          {:ok, User.t()}
          | {:error,
             :no_code | :expired | :invalid_code | :too_many_attempts | Ecto.Changeset.t()}
  defdelegate confirm_phone(user, code), to: Phone

  @spec remove_phone(User.t()) :: {:ok, User.t()}
  defdelegate remove_phone(user), to: Phone

  @spec prune_phone_codes() :: :ok
  defdelegate prune_phone_codes, to: Phone

  ## Session

  @doc """
  Generates a session token.
  """
  @spec generate_user_session_token(User.t()) :: binary()
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  @spec get_user_by_session_token(binary()) :: {User.t(), DateTime.t()} | nil
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  @spec get_user_by_magic_link_token(String.t()) :: User.t() | nil
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.

  The third item is the text prompt, set only at the first log-in (case 2)
  for a player who ticked Text at sign-up:

    * `{:code_sent, phone_code}` - a code went to the number they gave.
    * `:add_number` - no code went out; they should add a number.
    * `nil` - nothing to say.
  """
  @spec login_user_by_magic_link(String.t()) ::
          {:ok, {User.t(), [UserToken.t()], text_prompt()}} | {:error, :not_found}
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        with {:ok, {user, tokens}} <-
               user
               |> User.confirm_changeset()
               |> update_user_and_delete_all_tokens() do
          {:ok, {user, tokens, first_log_in_text(user)}}
        end

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, [], nil}}

      nil ->
        {:error, :not_found}
    end
  end

  # Runs after the confirm commits, so the text goes out of the transaction.
  @spec first_log_in_text(User.t()) :: text_prompt()
  defp first_log_in_text(user) do
    case text_signup_phone(user) do
      {:ok, phone_code} -> {:code_sent, phone_code}
      _not_sent -> if ask_for_number?(user), do: :add_number
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/profile/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_user_update_email_instructions(User.t(), String.t(), url_fun()) ::
          UserNotifier.delivery()
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  @spec deliver_login_instructions(User.t(), url_fun()) :: UserNotifier.delivery()
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Sends the magic link again, e.g. when a new player did not get the first one.

  Returns `{:error, :too_soon}` and sends nothing if the user got a login link
  less than #{@resend_cooldown_seconds} seconds ago. This limits how fast
  anyone can send email to one inbox.
  """
  @spec resend_login_instructions(User.t(), url_fun()) :: resend_result()
  def resend_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    if login_link_sent_recently?(user) do
      {:error, :too_soon}
    else
      deliver_login_instructions(user, magic_link_url_fun)
    end
  end

  @spec login_link_sent_recently?(User.t()) :: boolean()
  defp login_link_sent_recently?(%User{id: user_id}) do
    cutoff = DateTime.add(Riddlr.Clock.utc_now(), -@resend_cooldown_seconds, :second)

    Repo.exists?(
      from t in UserToken,
        where: t.user_id == ^user_id and t.context == "login" and t.inserted_at > ^cutoff
    )
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Moderation

  @doc """
  Updates a user's account_status and broadcasts the change to any connected sessions.

  Broadcasts `{:user_status_changed, status}` to `"user:{user_id}"` so live views
  can react immediately without polling the database.

  A ban also deletes all the user's tokens, in the same transaction, so the
  user is logged out everywhere. Returns `{:ok, {user, deleted_tokens}}`; pass
  the tokens to `RiddlrWeb.UserAuth.disconnect_sessions/1` to close open
  LiveViews. Any other status deletes no tokens and returns `[]`.
  """
  @spec set_user_status(User.t(), :active | :banned | :suspended) ::
          {:ok, {User.t(), [%UserToken{}]}} | {:error, Ecto.Changeset.t()}
  def set_user_status(%User{} = user, status) when status in [:active, :banned, :suspended] do
    changeset = User.status_changeset(user, %{account_status: status})

    result =
      if status == :banned,
        do: update_user_and_delete_all_tokens(changeset),
        else: with({:ok, user} <- Repo.update(changeset), do: {:ok, {user, []}})

    with {:ok, _} <- result do
      # Standings leave out banned and suspended players.
      Riddlr.Standings.invalidate()
      Phoenix.PubSub.broadcast(Riddlr.PubSub, "user:#{user.id}", {:user_status_changed, status})
      result
    end
  end

  ## Token helper

  @spec update_user_and_delete_all_tokens(Ecto.Changeset.t()) ::
          {:ok, user_and_expired_tokens()} | {:error, Ecto.Changeset.t()}
  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
