defmodule Riddlr.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Riddlr.Accounts.User
  alias Riddlr.Authorization

  @permissions [:manage_riddles, :manage_users, :moderate_content, :ban_players, :view_analytics]

  @granted %{
    super_admin: @permissions,
    moderator: [:moderate_content, :ban_players, :view_analytics],
    editor: [:manage_riddles],
    viewer: [:view_analytics],
    player: []
  }

  @admin_roles [:super_admin, :moderator, :editor]

  describe "has_permission?/2 for an active user" do
    for {role, granted} <- @granted, permission <- @permissions do
      @role role
      @permission permission

      if permission in granted do
        test "#{role} has #{permission}" do
          assert Authorization.has_permission?(user(@role, :active), @permission)
        end
      else
        test "#{role} lacks #{permission}" do
          refute Authorization.has_permission?(user(@role, :active), @permission)
        end
      end
    end

    test "an unknown permission is refused" do
      refute Authorization.has_permission?(user(:super_admin, :active), :launch_rockets)
    end
  end

  describe "has_permission?/2 for an inactive user" do
    for role <- Map.keys(@granted), status <- [:banned, :suspended] do
      @role role
      @status status

      test "a #{status} #{role} has no permission" do
        for permission <- @permissions do
          refute Authorization.has_permission?(user(@role, @status), permission)
        end
      end
    end
  end

  test "has_permission?/2 refuses a guest" do
    refute Authorization.has_permission?(nil, :view_analytics)
  end

  describe "admin?/1" do
    for role <- Map.keys(@granted), status <- [:active, :banned, :suspended] do
      @role role
      @status status

      if role in @admin_roles and status == :active do
        test "an #{status} #{role} is an admin" do
          assert Authorization.admin?(user(@role, @status))
        end
      else
        test "a #{status} #{role} is not an admin" do
          refute Authorization.admin?(user(@role, @status))
        end
      end
    end

    test "a guest is not an admin" do
      refute Authorization.admin?(nil)
    end
  end

  describe "authorize/2" do
    test "is :ok when the user has the permission" do
      assert Authorization.authorize(user(:editor, :active), :manage_riddles) == :ok
    end

    test "is an error when the user lacks it" do
      assert Authorization.authorize(user(:editor, :banned), :manage_riddles) ==
               {:error, :unauthorized}
    end
  end

  test "permissions_for_role/1 lists a role's permissions, and none for an unknown role" do
    assert Authorization.permissions_for_role(:editor) == [:manage_riddles]
    assert Authorization.permissions_for_role(:pirate) == []
  end

  defp user(role, status), do: %User{role: role, account_status: status}
end
