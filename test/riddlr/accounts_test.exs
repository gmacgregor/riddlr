defmodule Riddlr.AccountsTest do
  use Riddlr.DataCase
  use Oban.Testing, repo: Riddlr.Repo

  alias Riddlr.Accounts

  import Riddlr.AccountsFixtures
  alias Riddlr.Clock.Frozen
  alias Riddlr.Accounts.{NotificationConsent, User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "does not return a banned user" do
      user = user_fixture() |> set_password() |> put_status(:banned)

      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "get_user/1" do
    test "returns nil if the user does not exist" do
      refute Accounts.get_user(-1)
    end

    test "returns the user with the given id" do
      %{id: id} = user_fixture()
      assert %User{id: ^id} = Accounts.get_user(id)
    end
  end

  describe "notifiable?/2" do
    setup do
      now = DateTime.utc_now(:second)

      %{
        email: %User{notify_email: true, account_status: :active, confirmed_at: now},
        sms: %User{notify_sms: true, account_status: :active, phone_confirmed_at: now}
      }
    end

    test "is true for an active player with the channel on and confirmed", players do
      assert Accounts.notifiable?(players.email, :email)
      assert Accounts.notifiable?(players.sms, :sms)
    end

    test "is false with the channel off", players do
      refute Accounts.notifiable?(%{players.email | notify_email: false}, :email)
      refute Accounts.notifiable?(%{players.sms | notify_sms: false}, :sms)
    end

    test "is false with the email or number not confirmed", players do
      refute Accounts.notifiable?(%{players.email | confirmed_at: nil}, :email)
      refute Accounts.notifiable?(%{players.sms | phone_confirmed_at: nil}, :sms)
    end

    test "is false for a banned or suspended player", players do
      refute Accounts.notifiable?(%{players.email | account_status: :banned}, :email)
      refute Accounts.notifiable?(%{players.sms | account_status: :suspended}, :sms)
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates username uniqueness, ignoring case" do
      %{username: username} = user_fixture()

      {:error, changeset} =
        Accounts.register_user(valid_user_attributes(username: username))

      assert "has already been taken" in errors_on(changeset).username

      {:error, changeset} =
        Accounts.register_user(valid_user_attributes(username: String.upcase(username)))

      assert "has already been taken" in errors_on(changeset).username
    end

    test "registers users without password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end

    test "opting in to email writes one granted consent" do
      {:ok, user} = Accounts.register_user(valid_user_attributes(notify_email: true))

      assert [%NotificationConsent{channel: :email, action: :granted}] = consents(user)
    end

    test "ticking Text holds the number, sends nothing and logs no consent" do
      attrs = valid_user_attributes(text_requested: true, signup_phone: "(416) 555-0123")
      {:ok, user} = Accounts.register_user(attrs)

      assert user.text_requested
      assert user.signup_phone == "+14165550123"
      assert user.phone == nil
      refute user.notify_sms
      assert consents(user) == []
      assert Repo.all(Riddlr.Accounts.PhoneCode) == []
      refute_enqueued(worker: Riddlr.Workers.SendSmsConfirmationWorker)
      refute_received {:sms, _}
    end

    test "ticking Text needs a Canadian number" do
      for phone <- [nil, "", "(212) 555-0123"] do
        attrs = valid_user_attributes(text_requested: true, signup_phone: phone)
        assert {:error, changeset} = Accounts.register_user(attrs)
        assert errors_on(changeset)[:signup_phone]
      end
    end

    test "leaving Text off drops the number" do
      attrs = valid_user_attributes(text_requested: false, signup_phone: "(416) 555-0123")
      {:ok, user} = Accounts.register_user(attrs)

      assert user.signup_phone == nil
    end

    test "leaving email off writes no consent" do
      {:ok, user} = Accounts.register_user(valid_user_attributes(notify_email: false))

      assert consents(user) == []
    end
  end

  describe "update_user_notifications/2" do
    test "writes one consent row per email on/off change" do
      user = user_fixture()

      {:ok, user} = Accounts.update_user_notifications(user, %{notify_email: true})
      {:ok, user} = Accounts.update_user_notifications(user, %{notify_email: false})

      assert [%{action: :granted}, %{action: :withdrawn}] = consents(user)
    end

    test "writes no consent when email does not change" do
      user = user_fixture()

      {:ok, user} =
        Accounts.update_user_notifications(user, %{
          notify_email: false,
          notification_lead_time: :min_30
        })

      assert consents(user) == []
    end

    test "checks the stored opt-in, not a stale copy" do
      stale = %{user_fixture() | notify_email: true}
      Repo.update_all(from(u in User, where: u.id == ^stale.id), set: [notify_email: true])

      {:ok, _} = Accounts.update_user_notifications(stale, %{notify_email: false})
      {:ok, _} = Accounts.update_user_notifications(stale, %{notify_email: false})

      assert [%{action: :withdrawn}] = consents(stale)
    end

    test "writes no consent when the save fails" do
      user = user_fixture()

      {:error, _changeset} =
        Accounts.update_user_notifications(user, %{
          notify_email: true,
          notification_lead_time: "bogus"
        })

      assert consents(user) == []
      refute Repo.reload!(user).notify_email
    end
  end

  describe "sudo_mode?/2" do
    test "expires as the clock moves past the sudo window" do
      now = ~U[2026-08-01 12:00:00.000000Z]
      Frozen.freeze(now)
      user = %User{authenticated_at: now}

      Frozen.advance(19, :minute)
      assert Accounts.sudo_mode?(user)

      Frozen.advance(2, :minute)
      refute Accounts.sudo_mode?(user)
    end

    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end

    test "does not return a banned user", %{user: user, token: token} do
      put_status(user, :banned)

      refute Accounts.get_user_by_session_token(token)
    end

    test "still returns a suspended user", %{user: user, token: token} do
      put_status(user, :suspended)

      assert {%User{}, _} = Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_magic_link_token(token)
    end

    test "does not return a banned user", %{user: user, token: token} do
      put_status(user, :banned)

      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}], nil}} =
               Accounts.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "first log-in texts a code to the number held from sign-up" do
      user =
        unconfirmed_user_fixture(%{text_requested: true, signup_phone: "(416) 555-0123"})

      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, _tokens, {:code_sent, %{phone: "+14165550123"}}}} =
               Accounts.login_user_by_magic_link(encoded_token)

      assert_received {:sms, %{to: "+14165550123"}}
      assert Accounts.get_user!(user.id).signup_phone == nil
    end

    test "first log-in asks for a number when Text was ticked but none is held" do
      user =
        unconfirmed_user_fixture(%{text_requested: true, signup_phone: "(416) 555-0123"})

      Repo.update!(Ecto.Changeset.change(user, signup_phone: nil))
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {_user, _tokens, :add_number}} =
               Accounts.login_user_by_magic_link(encoded_token)

      refute_received {:sms, _}
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, [], nil}} = Accounts.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed user has password set" do
      user = unconfirmed_user_fixture()
      import Ecto.Query

      {1, nil} =
        Repo.update_all(from(u in User, where: u.id == ^user.id),
          set: [hashed_password: "hashed"]
        )

      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_user_by_magic_link(encoded_token)
      end
    end

    test "neither logs in nor confirms a banned user" do
      user = unconfirmed_user_fixture() |> put_status(:banned)
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
      refute Accounts.get_user!(user.id).confirmed_at
    end
  end

  describe "set_user_status/2" do
    test "a ban deletes the user's tokens and returns them" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {:ok, {%User{account_status: :banned}, tokens}} =
               Accounts.set_user_status(user, :banned)

      assert token in Enum.map(tokens, & &1.token)
      refute Repo.exists?(from t in UserToken, where: t.user_id == ^user.id)
    end

    test "a ban still tells the user's LiveViews" do
      user = user_fixture()
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "user:#{user.id}")

      {:ok, _} = Accounts.set_user_status(user, :banned)

      assert_receive {:user_status_changed, :banned}
    end

    test "any other status keeps the tokens" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {:ok, {%User{account_status: :suspended}, []}} =
               Accounts.set_user_status(user, :suspended)

      assert Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end

    test "sends from the configured address", %{user: user} do
      {:ok, email} = Accounts.deliver_login_instructions(user, &"[TOKEN]#{&1}[TOKEN]")

      assert email.from == Application.fetch_env!(:riddlr, :mail_from)
    end
  end

  describe "resend_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends a login link when none went out recently", %{user: user} do
      assert {:ok, email} = Accounts.resend_login_instructions(user, &"[TOKEN]#{&1}[TOKEN]")
      assert email.to == [{"", user.email}]
      assert Repo.get_by(UserToken, user_id: user.id, context: "login")
    end

    test "refuses while the last link is less than a minute old", %{user: user} do
      {:ok, _} = Accounts.deliver_login_instructions(user, &"[TOKEN]#{&1}[TOKEN]")

      assert {:error, :too_soon} =
               Accounts.resend_login_instructions(user, &"[TOKEN]#{&1}[TOKEN]")

      assert Repo.aggregate(from(t in UserToken, where: t.user_id == ^user.id), :count) == 1
    end

    test "sends again once the last link is over a minute old", %{user: user} do
      {_encoded, hashed} = generate_user_magic_link_token(user)
      offset_user_token(hashed, -61, :second)

      assert {:ok, _email} = Accounts.resend_login_instructions(user, &"[TOKEN]#{&1}[TOKEN]")
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  defp put_status(user, status) do
    user |> Ecto.Changeset.change(account_status: status) |> Repo.update!()
  end
end
