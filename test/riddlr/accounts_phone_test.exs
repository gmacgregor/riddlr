defmodule Riddlr.AccountsPhoneTest do
  # Some tests freeze the global clock, so this module cannot run async.
  use Riddlr.DataCase, async: false

  import Riddlr.AccountsFixtures

  alias Riddlr.Accounts

  # A valid Toronto number and a valid New York one. Both start with +1.
  @ca "(416) 555-0123"
  @us "(212) 555-0123"

  setup do
    %{user: user_fixture()}
  end

  describe "send_phone_code/2" do
    test "refuses a number that is not a phone number", %{user: user} do
      assert {:error, changeset} = Accounts.send_phone_code(user, %{"phone" => "12345"})
      assert "Only Canadian phone numbers are accepted" in errors_on(changeset).phone
    end

    test "texts a 6-digit code and leaves the account without a number", %{user: user} do
      assert {:ok, _} = Accounts.send_phone_code(user, %{"phone" => @ca})

      assert_received {:sms, %{to: "+14165550123", body: body}}
      assert body =~ ~r/\b\d{6}\b/

      user = Accounts.get_user!(user.id)
      assert user.phone == nil
      assert user.phone_confirmed_at == nil
    end

    test "refuses a number another account holds, without texting it", %{user: user} do
      confirm!(user_fixture(), @ca)

      assert {:error, changeset} = Accounts.send_phone_code(user, %{"phone" => @ca})
      assert "is already used by another account" in errors_on(changeset).phone
      refute_received {:sms, _}
    end

    test "counts a refused taken number toward the hourly limit", %{user: user} do
      confirm!(user_fixture(), @ca)
      for _ <- 1..3, do: {:error, _} = Accounts.send_phone_code(user, %{"phone" => @ca})

      assert {:error, :rate_limited} =
               Accounts.send_phone_code(user, %{"phone" => "(613) 555-0199"})
    end

    test "allows 3 codes per player per hour", %{user: user} do
      Riddlr.Clock.Frozen.freeze()
      for _ <- 1..3, do: send_code!(user, @ca)

      assert {:error, :rate_limited} = Accounts.send_phone_code(user, %{"phone" => @ca})
      refute_received {:sms, _}

      Riddlr.Clock.Frozen.advance(1, :hour)
      assert send_code!(user, @ca)
    end

    test "allows 5 codes per number per day, across accounts", %{user: user} do
      Riddlr.Clock.Frozen.freeze()
      for _ <- 1..3, do: send_code!(user, @ca)
      Riddlr.Clock.Frozen.advance(1, :hour)
      for _ <- 1..2, do: send_code!(user, @ca)
      Riddlr.Clock.Frozen.advance(1, :hour)

      other = user_fixture()
      assert {:error, :rate_limited} = Accounts.send_phone_code(other, %{"phone" => @ca})
      assert send_code!(other, "(613) 555-0199")

      Riddlr.Clock.Frozen.advance(1, :day)
      assert send_code!(other, @ca)
    end

    test "a failed text keeps the earlier code working", %{user: user} do
      code = send_code!(user, @ca)
      fail_sms()

      assert {:error, :provider_down} =
               Accounts.send_phone_code(user, %{"phone" => "(613) 555-0199"})

      assert {:ok, %{phone: "+14165550123"}} = Accounts.confirm_phone(user, code)
    end

    test "refuses a valid number from outside Canada", %{user: user} do
      assert {:error, changeset} = Accounts.send_phone_code(user, %{"phone" => @us})
      assert "must be a Canadian number" in errors_on(changeset).phone
    end
  end

  describe "resend_phone_code/1" do
    test "texts a new code to the pending number; only the new code works", %{user: user} do
      old = send_code!(user, @ca)

      assert {:ok, _} = Accounts.resend_phone_code(user)
      assert_received {:sms, %{to: "+14165550123", body: body}}
      [new] = Regex.run(~r/\b\d{6}\b/, body)

      if old != new, do: assert({:error, _} = Accounts.confirm_phone(user, old))
      assert {:ok, %{phone: "+14165550123"}} = Accounts.confirm_phone(user, new)
    end

    test "fails with no pending number", %{user: user} do
      assert {:error, :no_code} = Accounts.resend_phone_code(user)
    end

    test "fails once the pending code has expired", %{user: user} do
      Riddlr.Clock.Frozen.freeze()
      send_code!(user, @ca)
      Riddlr.Clock.Frozen.advance(10, :minute)

      assert {:error, :no_code} = Accounts.resend_phone_code(user)
      refute_received {:sms, _}
    end
  end

  describe "remove_phone/1" do
    test "wipes the number, any pending number, and turns texts off", %{user: user} do
      user = confirm!(user, @ca)
      send_code!(user, "(613) 555-0199")
      user = user |> Ecto.Changeset.change(notify_sms: true) |> Repo.update!()

      assert {:ok, user} = Accounts.remove_phone(user)
      assert %{phone: nil, phone_hash: nil, phone_confirmed_at: nil, notify_sms: false} = user

      %{rows: rows} =
        Repo.query!(
          "SELECT phone, phone_hash, code_hash FROM phone_codes WHERE user_id = $1",
          [user.id]
        )

      assert Enum.all?(rows, &(&1 == [nil, nil, nil]))
      assert {:error, :no_code} = Accounts.resend_phone_code(user)
    end
  end

  describe "confirm_phone/2" do
    test "the right code puts the number on the account, unreadable at rest", %{user: user} do
      code = send_code!(user, @ca)

      assert {:ok, user} = Accounts.confirm_phone(user, code)
      assert user.phone == "+14165550123"
      assert user.phone_confirmed_at

      %{rows: [[stored]]} =
        Repo.query!("SELECT phone FROM users WHERE id = $1", [user.id])

      refute stored =~ "4165550123"
    end

    test "a pending new number leaves the confirmed one in place until it checks out",
         %{user: user} do
      user = confirm!(user, @ca)

      code = send_code!(user, "(613) 555-0199")
      assert Accounts.get_user!(user.id).phone == "+14165550123"

      assert {:ok, user} = Accounts.confirm_phone(user, code)
      assert user.phone == "+16135550199"
    end

    test "fails when another account confirmed the number first", %{user: user} do
      code = send_code!(user, @ca)
      confirm!(user_fixture(), @ca)

      assert {:error, %Ecto.Changeset{}} = Accounts.confirm_phone(user, code)
      assert Accounts.get_user!(user.id).phone == nil
    end

    test "a wrong code fails and leaves the account without a number", %{user: user} do
      code = send_code!(user, @ca)

      assert {:error, :invalid_code} = Accounts.confirm_phone(user, wrong(code))
      assert Accounts.get_user!(user.id).phone == nil
    end

    test "a code fails once 10 minutes have passed", %{user: user} do
      Riddlr.Clock.Frozen.freeze()
      code = send_code!(user, @ca)

      Riddlr.Clock.Frozen.advance(9, :minute)
      assert {:error, :invalid_code} = Accounts.confirm_phone(user, wrong(code))

      Riddlr.Clock.Frozen.advance(61, :second)
      assert {:error, :expired} = Accounts.confirm_phone(user, code)
      assert Accounts.get_user!(user.id).phone == nil
    end

    test "the 5th wrong try ends the code; the right code fails after it", %{user: user} do
      code = send_code!(user, @ca)

      for _ <- 1..4,
          do: assert({:error, :invalid_code} = Accounts.confirm_phone(user, wrong(code)))

      assert {:error, :too_many_attempts} = Accounts.confirm_phone(user, wrong(code))
      assert {:error, _} = Accounts.confirm_phone(user, code)
      assert Accounts.get_user!(user.id).phone == nil
    end

    test "5 wrong tries block new codes for 24 hours", %{user: user} do
      Riddlr.Clock.Frozen.freeze()
      code = send_code!(user, @ca)
      for _ <- 1..5, do: Accounts.confirm_phone(user, wrong(code))

      Riddlr.Clock.Frozen.advance(2, :hour)
      assert {:error, :locked} = Accounts.send_phone_code(user, %{"phone" => "(613) 555-0199"})
      assert {:error, :locked} = Accounts.resend_phone_code(user)
      refute_received {:sms, _}

      Riddlr.Clock.Frozen.advance(22, :hour)
      assert send_code!(user, @ca)
    end
  end

  defp wrong(code), do: if(code == "000000", do: "111111", else: "000000")

  defmodule FailingSMS do
    @moduledoc false
    @behaviour Riddlr.SMS
    @impl Riddlr.SMS
    def deliver(_message), do: {:error, :provider_down}
  end

  defp fail_sms do
    original = Application.get_env(:riddlr, Riddlr.SMS)
    Application.put_env(:riddlr, Riddlr.SMS, adapter: FailingSMS)
    on_exit(fn -> Application.put_env(:riddlr, Riddlr.SMS, original) end)
  end

  defp confirm!(user, phone) do
    {:ok, user} = Accounts.confirm_phone(user, send_code!(user, phone))
    user
  end

  # Sends a code to `phone` and returns the code from the text.
  defp send_code!(user, phone) do
    {:ok, _} = Accounts.send_phone_code(user, %{"phone" => phone})
    assert_received {:sms, %{body: body}}
    [code] = Regex.run(~r/\b\d{6}\b/, body)
    code
  end
end
