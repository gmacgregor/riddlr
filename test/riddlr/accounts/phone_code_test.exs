defmodule Riddlr.Accounts.PhoneCodeTest do
  use ExUnit.Case, async: true

  alias Riddlr.Accounts.PhoneCode

  describe "hash_code/1" do
    test "gives the same hash for the same code" do
      assert PhoneCode.hash_code("123456") == PhoneCode.hash_code("123456")
    end

    test "gives different hashes for different codes" do
      refute PhoneCode.hash_code("123456") == PhoneCode.hash_code("123457")
    end

    test "is keyed, not a plain SHA-256 of the code" do
      refute PhoneCode.hash_code("123456") == :crypto.hash(:sha256, "123456")
    end

    test "differs from the phone-number blind index of the same text" do
      {:ok, index} = Riddlr.Hashed.HMAC.dump("123456")

      refute PhoneCode.hash_code("123456") == index
    end
  end

  describe "check/2" do
    test "accepts the right code and refuses a wrong one" do
      phone_code = %PhoneCode{
        phone: "+14165550123",
        code_hash: PhoneCode.hash_code("123456"),
        attempts: 0,
        inserted_at: Riddlr.Clock.utc_now()
      }

      assert PhoneCode.check(phone_code, "123456") == :ok
      assert PhoneCode.check(phone_code, "654321") == {:error, :invalid_code}
    end
  end
end
