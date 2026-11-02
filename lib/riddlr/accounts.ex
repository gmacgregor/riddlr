defmodule Riddlr.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Riddlr.Repo

  alias Riddlr.Accounts.{NotificationConsent, PhoneCode, User, UserToken, UserNotifier}
  alias Riddlr.Workers.SendSmsConfirmationWorker

  @typedoc "What to tell a player about texts at their first log-in."
  @type text_prompt :: {:code_sent, PhoneCode.t()} | :add_number | nil

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
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
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Returns a map of %{user_id => user} for the given list of IDs.
  Missing IDs are omitted from the result.
  """
  def get_users_by_ids(ids) when is_list(ids) do
    Repo.all(from u in User, where: u.id in ^ids) |> Map.new(&{&1.id, &1})
  end

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
    save_with_consent(
      fn -> User.registration_changeset(%User{}, attrs, text: Riddlr.SMS.enabled?()) end,
      &Repo.insert/1
    )
  end

  # Builds the changeset and saves the user inside one transaction, and logs
  # each channel turned on or off. Building inside the transaction lets
  # callers lock and read the stored row first, so two saves at once cannot
  # both log the same change.
  @typep save_result :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  @spec save_with_consent((-> Ecto.Changeset.t()), (Ecto.Changeset.t() -> save_result())) ::
          save_result()
  defp save_with_consent(build_changeset, save) do
    Repo.transaction(fn ->
      changeset = build_changeset.()

      with {:ok, user} <- save.(changeset) do
        log_channel_changes(user, changeset)
        user
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # Inside the caller's transaction: one consent row per channel turned on or
  # off, and the confirmation text when Text turns on.
  @spec log_channel_changes(User.t(), Ecto.Changeset.t()) :: :ok
  defp log_channel_changes(user, changeset) do
    user
    |> NotificationConsent.for_changes(changeset)
    |> Enum.each(&Repo.insert!/1)

    if Ecto.Changeset.get_change(changeset, :notify_sms) == true,
      do: Oban.insert!(SendSmsConfirmationWorker.new(%{"user_id" => user.id}))

    :ok
  end

  # Reads the stored user row and locks it until the transaction ends, so
  # two saves at once see each other's changes.
  @spec lock_user!(integer()) :: User.t()
  defp lock_user!(id) do
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
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes.
  """
  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
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
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc """
  Returns a changeset for the user's notification choices.
  """
  @spec change_user_notifications(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_notifications(%User{} = user, attrs \\ %{}) do
    User.notification_changeset(user, attrs)
  end

  @doc """
  Saves the user's notification choices. An email on/off change also logs a
  consent row in the same transaction.
  """
  @spec update_user_notifications(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_notifications(%User{id: id}, attrs) do
    save_with_consent(
      fn ->
        id
        |> lock_user!()
        |> User.notification_changeset(attrs)
      end,
      &Repo.update/1
    )
  end

  ## Phone

  @doc """
  Whether to ask the player for a mobile number: they ticked Text at sign-up
  and have no confirmed number yet. False while texting is off.
  """
  @spec ask_for_number?(User.t()) :: boolean()
  def ask_for_number?(%User{text_requested: requested, phone_confirmed_at: confirmed_at}),
    do: requested and is_nil(confirmed_at) and Riddlr.SMS.enabled?()

  @doc """
  Texts a code to the number the player gave at sign-up, then wipes it from
  the account whatever the result. Call at the first log-in. The usual send
  limits and the taken-number check apply. `:none` when no number is held or
  texting is off.

  Reads the stored row, not `user`, and takes the number off in one locked
  step, so two log-ins at once text it only once.
  """
  @spec text_signup_phone(User.t()) :: {:ok, PhoneCode.t()} | {:error, term()} | :none
  def text_signup_phone(%User{id: id} = user) do
    {:ok, phone} = Repo.transaction(fn -> take_signup_phone!(id) end)

    if phone && Riddlr.SMS.enabled?(),
      do: send_phone_code(user, %{"phone" => phone}),
      else: :none
  end

  # Inside a transaction: the held number, wiped from the locked row.
  @spec take_signup_phone!(integer()) :: String.t() | nil
  defp take_signup_phone!(id) do
    case lock_user!(id) do
      %User{signup_phone: nil} ->
        nil

      %User{signup_phone: phone} = locked ->
        Repo.update!(Ecto.Changeset.change(locked, signup_phone: nil))
        phone
    end
  end

  @doc """
  Texts a code to the Canadian number in `attrs["phone"]` so the player can
  prove they own it. The number stays pending, off the account, until
  `confirm_phone/2` gets the right code.

  Sends are limited to #{PhoneCode.user_hourly_limit()} per player per hour and
  #{PhoneCode.number_daily_limit()} per number per day. A code that used up all
  its tries blocks new codes (`:locked`) for a day after it was sent.
  """
  @spec send_phone_code(User.t(), map()) ::
          {:ok, PhoneCode.t()}
          | {:error, Ecto.Changeset.t() | :locked | :rate_limited | term()}
  def send_phone_code(%User{id: user_id}, attrs) do
    code = PhoneCode.generate_code()

    changeset =
      %PhoneCode{
        user_id: user_id,
        code_hash: PhoneCode.hash_code(code),
        inserted_at: Riddlr.Clock.utc_now() |> DateTime.truncate(:second)
      }
      |> PhoneCode.request_changeset(attrs)

    with {:ok, phone_code} <- insert_phone_code(changeset) do
      deliver_phone_code(phone_code, code)
    end
  end

  @doc """
  The player's pending number's code row, while its code is still live, or
  `nil`.
  """
  @spec get_pending_phone_code(User.t()) :: PhoneCode.t() | nil
  def get_pending_phone_code(%User{id: user_id}) do
    case latest_phone_code(user_id, lock: false) do
      %PhoneCode{phone: phone} = phone_code when is_binary(phone) ->
        if PhoneCode.expired?(phone_code) or PhoneCode.used_up?(phone_code),
          do: nil,
          else: phone_code

      _ ->
        nil
    end
  end

  @doc """
  Texts a new code to the player's pending number. Earlier codes stop
  working. Counts toward the same send limits as `send_phone_code/2`.
  """
  @spec resend_phone_code(User.t()) ::
          {:ok, PhoneCode.t()} | {:error, :no_code | :locked | :rate_limited | term()}
  def resend_phone_code(%User{id: user_id} = user) do
    cond do
      phone_locked?(user_id) -> {:error, :locked}
      pending = get_pending_phone_code(user) -> send_phone_code(user, %{"phone" => pending.phone})
      true -> {:error, :no_code}
    end
  end

  defp insert_phone_code(%{valid?: false} = changeset),
    do: Ecto.Changeset.apply_action(changeset, :insert)

  # Locks the player's row and the number, so two sends at once, from one
  # account or several, cannot both slip under a limit. Commits even when
  # it refuses, so a refused "number taken" still counts toward the limit.
  defp insert_phone_code(%{data: %PhoneCode{user_id: user_id} = data} = changeset) do
    e164 = Ecto.Changeset.fetch_change!(changeset, :phone_hash)

    {:ok, result} =
      Repo.transaction(fn ->
        Repo.one!(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE", select: u.id)
        Repo.query!("SELECT pg_advisory_xact_lock($1)", [:erlang.phash2({PhoneCode, e164})])

        cond do
          phone_locked?(user_id) ->
            {:error, :locked}

          rate_limited?(user_id, e164) ->
            {:error, :rate_limited}

          phone_taken?(user_id, e164) ->
            # Counted like a send, so this check cannot probe numbers freely.
            Repo.insert!(%PhoneCode{user_id: user_id, inserted_at: data.inserted_at})

            changeset
            |> Ecto.Changeset.add_error(:phone, "is already used by another account")
            |> Ecto.Changeset.apply_action(:insert)

          true ->
            {:ok, Repo.insert!(changeset)}
        end
      end)

    result
  end

  # A code that took every wrong try blocks new codes for a day after it was
  # sent. Rows are pruned at a day, so the block ends with them.
  defp phone_locked?(user_id) do
    day_ago = DateTime.add(Riddlr.Clock.utc_now(), -1, :day)

    Repo.exists?(
      from c in PhoneCode,
        where:
          c.user_id == ^user_id and c.attempts >= ^PhoneCode.max_attempts() and
            c.inserted_at > ^day_ago
    )
  end

  defp rate_limited?(user_id, e164) do
    now = Riddlr.Clock.utc_now()
    hour_ago = DateTime.add(now, -1, :hour)
    day_ago = DateTime.add(now, -1, :day)

    by_user = from c in PhoneCode, where: c.user_id == ^user_id and c.inserted_at > ^hour_ago
    by_number = from c in PhoneCode, where: c.phone_hash == ^e164 and c.inserted_at > ^day_ago

    Repo.aggregate(by_user, :count) >= PhoneCode.user_hourly_limit() or
      Repo.aggregate(by_number, :count) >= PhoneCode.number_daily_limit()
  end

  defp phone_taken?(user_id, e164) do
    Repo.exists?(from u in User, where: u.phone_hash == ^e164 and u.id != ^user_id)
  end

  # Only once the text goes out do older codes stop working. A failed text
  # wipes its own row, which still counts toward the limits.
  defp deliver_phone_code(%PhoneCode{id: id, user_id: user_id, phone: phone} = phone_code, code) do
    message = %Riddlr.SMS.Message{
      to: phone,
      body: "Your Riddlr code is #{code}. It expires in #{PhoneCode.ttl_minutes()} min."
    }

    case Riddlr.SMS.deliver(message) do
      :ok ->
        wipe_phone_codes(from c in PhoneCode, where: c.user_id == ^user_id and c.id != ^id)
        {:ok, phone_code}

      {:error, _reason} = error ->
        wipe_phone_codes(from c in PhoneCode, where: c.id == ^id)
        error
    end
  end

  defp wipe_phone_codes(query) do
    Repo.update_all(query, set: [phone: nil, code_hash: nil])
  end

  @doc """
  Checks `code` against the player's newest code. When it matches, the
  pending number becomes the account's confirmed number, replacing any old
  one, and the pending row is wiped.

  A wrong code uses up one of #{PhoneCode.max_attempts()} tries. The last
  wrong try returns `:too_many_attempts` and starts a day-long block on new
  codes.
  """
  @spec confirm_phone(User.t(), String.t()) ::
          {:ok, User.t()}
          | {:error,
             :no_code | :expired | :invalid_code | :too_many_attempts | Ecto.Changeset.t()}
  def confirm_phone(%User{id: user_id}, code) when is_binary(code) do
    # The transaction commits on a wrong code too, so the used try sticks.
    Repo.transaction(fn ->
      phone_code = latest_phone_code(user_id, lock: true)

      case PhoneCode.check(phone_code, code) do
        :ok ->
          apply_phone_code(phone_code)

        {:error, :invalid_code} = error ->
          attempts = phone_code.attempts + 1
          Repo.update!(Ecto.Changeset.change(phone_code, attempts: attempts))
          if attempts >= PhoneCode.max_attempts(), do: {:error, :too_many_attempts}, else: error

        error ->
          error
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, _changeset} = error -> error
    end
  end

  defp apply_phone_code(%PhoneCode{user_id: user_id, phone: phone} = phone_code) do
    Repo.update!(Ecto.Changeset.change(phone_code, phone: nil, code_hash: nil))

    changeset =
      user_id
      |> lock_user!()
      |> User.confirm_phone_changeset(phone)

    case Repo.update(changeset) do
      {:ok, user} ->
        log_channel_changes(user, changeset)
        {:ok, user}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  @doc """
  Wipes the player's number, confirmed or pending, and turns texts off,
  logging the withdrawal if Text was on. The player's sent-code rows stay,
  empty, so they still count toward the hourly
  send limit.
  """
  @spec remove_phone(User.t()) :: {:ok, User.t()}
  def remove_phone(%User{id: user_id}) do
    Repo.transact(fn ->
      Repo.update_all(
        from(c in PhoneCode, where: c.user_id == ^user_id),
        set: [phone: nil, phone_hash: nil, code_hash: nil]
      )

      changeset =
        user_id
        |> lock_user!()
        |> User.remove_phone_changeset()

      with {:ok, user} <- Repo.update(changeset) do
        log_channel_changes(user, changeset)
        {:ok, user}
      end
    end)
  end

  @doc """
  Wipes pending numbers and codes once their code has expired. Deletes rows
  older than a day, which the per-number send limit no longer needs. Wipes
  a number held from sign-up once the account is a day old. Runs hourly, so
  data can outlive these limits by up to an hour; codes still fail on time.
  """
  @spec prune_phone_codes() :: :ok
  def prune_phone_codes do
    expired_before = PhoneCode.expiry_cutoff()
    day_ago = DateTime.add(Riddlr.Clock.utc_now(), -1, :day)

    Repo.update_all(
      from(c in PhoneCode,
        where: c.inserted_at <= ^expired_before and not is_nil(c.phone)
      ),
      set: [phone: nil, code_hash: nil]
    )

    Repo.delete_all(from c in PhoneCode, where: c.inserted_at <= ^day_ago)

    # Only sign-up sets `signup_phone`, so the account's age is the number's.
    Repo.update_all(
      from(u in User, where: u.inserted_at <= ^day_ago and not is_nil(u.signup_phone)),
      set: [signup_phone: nil]
    )

    :ok
  end

  defp latest_phone_code(user_id, opts) do
    query =
      from c in PhoneCode,
        where: c.user_id == ^user_id and not is_nil(c.phone),
        order_by: [desc: c.inserted_at, desc: c.id],
        limit: 1

    query = if opts[:lock], do: lock(query, "FOR UPDATE"), else: query
    Repo.one(query)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
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
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
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
      Phoenix.PubSub.broadcast(Riddlr.PubSub, "user:#{user.id}", {:user_status_changed, status})
      result
    end
  end

  ## Token helper

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
