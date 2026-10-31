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

    test "accepts spaces and dashes" do
      for name <- ["Riddle Master", "riddle-master", "the_riddle - master 2"] do
        changeset =
          User.registration_changeset(%User{}, valid_user_attributes(%{username: name}))

        assert changeset.valid?, "expected #{inspect(name)} to be valid"
      end
    end

    test "trims spaces from the ends" do
      changeset =
        User.registration_changeset(
          %User{},
          valid_user_attributes(%{username: "  Riddle Master "})
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :username) == "Riddle Master"
    end

    test "rejects double spaces and other symbols" do
      for name <- ["riddle  master", "riddle.master", "riddle!", "   "] do
        changeset =
          User.registration_changeset(%User{}, valid_user_attributes(%{username: name}))

        assert %{username: [_ | _]} = errors_on(changeset), "expected #{inspect(name)} to fail"
      end
    end

    test "allows up to 25 characters" do
      ok =
        User.registration_changeset(
          %User{},
          valid_user_attributes(%{username: String.duplicate("a", 25)})
        )

      assert ok.valid?

      too_long =
        User.registration_changeset(
          %User{},
          valid_user_attributes(%{username: String.duplicate("a", 26)})
        )

      assert %{username: [_]} = errors_on(too_long)
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
          "role" => "super_admin"
        })

      assert changeset.changes == %{}
    end

    test "notification_changeset/2 sets the lead time" do
      changeset = User.notification_changeset(%User{}, %{"notification_lead_time" => "min_30"})
      assert changeset.changes == %{notification_lead_time: :min_30}

      changeset = User.notification_changeset(%User{}, %{"notification_lead_time" => "min_5"})
      assert %{notification_lead_time: [_]} = errors_on(changeset)
    end
  end
end
