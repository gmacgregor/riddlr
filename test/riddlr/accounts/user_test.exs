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

      assert {:error, changeset} =
               Accounts.register_user(%{
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

  describe "role" do
    test "defaults to player" do
      user = %User{}
      assert user.role == :player
    end

    test "validates role enum" do
      changeset = User.changeset(%User{}, %{role: :super_admin})
      assert changeset.valid?

      changeset = User.changeset(%User{}, %{role: :invalid})
      refute changeset.valid?
    end
  end

  describe "notification preferences" do
    test "default to off with lobby_open lead time" do
      user = user_fixture()

      assert %User{notify_email: false, notify_sms: false, notification_lead_time: :lobby_open} =
               Riddlr.Repo.reload!(user)
    end

    test "update_user_notifications/2 toggles email on and off" do
      user = user_fixture()

      assert {:ok, %User{notify_email: true} = user} =
               Accounts.update_user_notifications(user, %{"notify_email" => "true"})

      assert {:ok, %User{notify_email: false}} =
               Accounts.update_user_notifications(user, %{"notify_email" => "false"})
    end

    test "notification_changeset/2 ignores fields players cannot set yet" do
      changeset =
        User.notification_changeset(%User{}, %{
          "notify_sms" => "true",
          "notification_lead_time" => "min_30",
          "role" => "super_admin"
        })

      assert changeset.changes == %{}
    end
  end
end
