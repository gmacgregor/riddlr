defmodule Riddlr.AuthorizationTest do
  use ExUnit.Case, async: true
  alias Riddlr.Authorization
  alias Riddlr.Accounts.User

  test "super_admin has all permissions" do
    user = %User{role: :super_admin}
    assert Authorization.has_permission?(user, :manage_riddles)
    assert Authorization.has_permission?(user, :ban_players)
  end

  test "editor can manage riddles only" do
    user = %User{role: :editor}
    assert Authorization.has_permission?(user, :manage_riddles)
    refute Authorization.has_permission?(user, :ban_players)
  end

  test "player has no permissions" do
    user = %User{role: :player}
    refute Authorization.has_permission?(user, :manage_riddles)
  end

  test "is_admin?/1 checks admin roles" do
    assert Authorization.is_admin?(%User{role: :editor})
    refute Authorization.is_admin?(%User{role: :player})
  end
end
