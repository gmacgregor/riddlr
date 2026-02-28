defmodule Riddlr.Accounts.UserTest do
  use Riddlr.DataCase
  import Riddlr.AccountsFixtures
  alias Riddlr.Accounts
  alias Riddlr.Accounts.User

  describe "username validation" do
    test "requires username" do
      changeset = User.registration_changeset(%User{}, valid_user_attributes(%{username: nil}))
      assert %{username: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires unique username" do
      _user = user_fixture(%{username: "testuser"})
      assert {:error, changeset} = Accounts.register_user(%{
        email: "other@example.com",
        username: "testuser",
        password: "password123password123"
      })
      assert %{username: ["has already been taken"]} = errors_on(changeset)
    end

    test "accepts valid username" do
      attrs = valid_user_attributes(%{username: "validuser"})
      changeset = User.registration_changeset(%User{}, attrs)
      assert changeset.valid?
    end
  end
end
