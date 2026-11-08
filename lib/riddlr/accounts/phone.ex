defmodule Riddlr.Accounts.Phone do
  @moduledoc """
  A player's mobile number: texting a code, confirming it, and removing it.

  A number stays pending, off the account, until the player types the code
  it was sent. Sends are rate limited per player and per number.
  `Riddlr.Accounts` delegates its phone functions here.
  """

  import Ecto.Query, warn: false

  alias Riddlr.Accounts
  alias Riddlr.Accounts.{NotificationPreferences, PhoneCode, User}
  alias Riddlr.Repo

  @doc "How many minutes a phone code works for."
  @spec phone_code_ttl_minutes() :: pos_integer()
  defdelegate phone_code_ttl_minutes, to: PhoneCode, as: :ttl_minutes

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
    case Accounts.lock_user!(id) do
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

  Sends are limited to #{PhoneCode.user_hourly_limit()} per player per hour,
  #{PhoneCode.user_daily_limit()} per player per day and
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

  @spec insert_phone_code(Ecto.Changeset.t()) ::
          {:ok, PhoneCode.t()} | {:error, Ecto.Changeset.t() | :locked | :rate_limited}
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
  @spec phone_locked?(integer()) :: boolean()
  defp phone_locked?(user_id) do
    day_ago = DateTime.add(Riddlr.Clock.utc_now(), -1, :day)

    Repo.exists?(
      from c in PhoneCode,
        where:
          c.user_id == ^user_id and c.attempts >= ^PhoneCode.max_attempts() and
            c.inserted_at > ^day_ago
    )
  end

  @spec rate_limited?(integer(), binary()) :: boolean()
  defp rate_limited?(user_id, e164) do
    now = Riddlr.Clock.utc_now()
    hour_ago = DateTime.add(now, -1, :hour)
    day_ago = DateTime.add(now, -1, :day)

    by_user = from c in PhoneCode, where: c.user_id == ^user_id and c.inserted_at > ^hour_ago
    by_user_day = from c in PhoneCode, where: c.user_id == ^user_id and c.inserted_at > ^day_ago
    by_number = from c in PhoneCode, where: c.phone_hash == ^e164 and c.inserted_at > ^day_ago

    Repo.aggregate(by_user, :count) >= PhoneCode.user_hourly_limit() or
      Repo.aggregate(by_user_day, :count) >= PhoneCode.user_daily_limit() or
      Repo.aggregate(by_number, :count) >= PhoneCode.number_daily_limit()
  end

  @spec phone_taken?(integer(), binary()) :: boolean()
  defp phone_taken?(user_id, e164) do
    Repo.exists?(from u in User, where: u.phone_hash == ^e164 and u.id != ^user_id)
  end

  # Only once the text goes out do older codes stop working. A failed text
  # wipes its own row, which still counts toward the limits.
  @spec deliver_phone_code(PhoneCode.t(), String.t()) :: {:ok, PhoneCode.t()} | {:error, term()}
  defp deliver_phone_code(%PhoneCode{id: id, user_id: user_id, phone: phone} = phone_code, code) do
    message = %Riddlr.SMS.Message{
      to: phone,
      body: "Your Kriddle code is #{code}. It expires in #{PhoneCode.ttl_minutes()} minutes."
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

  @spec wipe_phone_codes(Ecto.Query.t()) :: {non_neg_integer(), nil}
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

  @spec apply_phone_code(PhoneCode.t()) :: {:ok, User.t()}
  defp apply_phone_code(%PhoneCode{user_id: user_id, phone: phone} = phone_code) do
    Repo.update!(Ecto.Changeset.change(phone_code, phone: nil, code_hash: nil))

    changeset =
      user_id
      |> Accounts.lock_user!()
      |> User.confirm_phone_changeset(phone)

    case Repo.update(changeset) do
      {:ok, user} ->
        NotificationPreferences.log_channel_changes(user, changeset)
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
        |> Accounts.lock_user!()
        |> User.remove_phone_changeset()

      with {:ok, user} <- Repo.update(changeset) do
        NotificationPreferences.log_channel_changes(user, changeset)
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

  @spec latest_phone_code(integer(), keyword()) :: PhoneCode.t() | nil
  defp latest_phone_code(user_id, opts) do
    query =
      from c in PhoneCode,
        where: c.user_id == ^user_id and not is_nil(c.phone),
        order_by: [desc: c.inserted_at, desc: c.id],
        limit: 1

    query = if opts[:lock], do: lock(query, "FOR UPDATE"), else: query
    Repo.one(query)
  end
end
