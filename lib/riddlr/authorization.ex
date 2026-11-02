defmodule Riddlr.Authorization do
  @moduledoc """
  Role-based authorization for Riddlr.
  Permissions are hierarchical: super_admin > moderator > editor > viewer > player
  """

  alias Riddlr.Accounts.User

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

  @type permission ::
          :manage_riddles | :manage_users | :moderate_content | :ban_players | :view_analytics

  @doc """
  Returns true if the user's role grants `permission`. Only an `:active` user
  holds any permission; a banned or suspended user, or a guest, holds none.
  """
  @spec has_permission?(User.t() | nil, permission() | atom()) :: boolean()
  def has_permission?(%User{account_status: :active, role: role}, permission) do
    permission in Map.get(@role_permissions, role, [])
  end

  def has_permission?(_user, _permission), do: false

  @doc """
  Returns `:ok` if the user holds `permission`, else `{:error, :unauthorized}`.
  """
  @spec authorize(User.t() | nil, permission() | atom()) :: :ok | {:error, :unauthorized}
  def authorize(user, permission) do
    if has_permission?(user, permission), do: :ok, else: {:error, :unauthorized}
  end

  @doc """
  Returns true if the user may enter the admin pages: an `:active` super
  admin, moderator or editor.
  """
  @spec admin?(User.t() | nil) :: boolean()
  def admin?(%User{account_status: :active, role: role}),
    do: role in [:super_admin, :moderator, :editor]

  def admin?(_user), do: false

  @doc """
  Lists the permissions a role grants, whatever the user's status.
  """
  @spec permissions_for_role(atom()) :: [permission()]
  def permissions_for_role(role), do: Map.get(@role_permissions, role, [])
end
