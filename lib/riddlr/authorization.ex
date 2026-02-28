defmodule Riddlr.Authorization do
  @moduledoc """
  Role-based authorization for Riddlr.
  Permissions are hierarchical: super_admin > moderator > editor > viewer > player
  """

  @role_permissions %{
    super_admin: [
      :manage_riddles,
      :manage_users,
      :moderate_content,
      :ban_players,
      :view_analytics
    ],
    moderator: [:moderate_content, :ban_players, :view_analytics],
    editor: [:manage_riddles],
    viewer: [:view_analytics],
    player: []
  }

  def has_permission?(%{role: role}, permission) do
    permission in Map.get(@role_permissions, role, [])
  end

  def has_permission?(nil, _permission), do: false

  def authorize(user, permission) do
    if has_permission?(user, permission), do: :ok, else: {:error, :unauthorized}
  end

  def is_admin?(%{role: role}), do: role in [:super_admin, :moderator, :editor]
  def is_admin?(nil), do: false

  def permissions_for_role(role), do: Map.get(@role_permissions, role, [])
end
