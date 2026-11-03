defmodule Riddlr.Authorization do
  @moduledoc """
  Role-based authorization for Riddlr.
  Permissions are hierarchical: super_admin > moderator > editor > viewer > player
  """

  alias Riddlr.Accounts
  alias Riddlr.Accounts.Scope
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
  Returns `:ok` if the caller holds `permission`, else `{:error, :unauthorized}`.

  The system scope holds every permission. For a user scope, this reads the
  user again from the database: a LiveView keeps the scope from its mount,
  and a role or status can change after that by iex or SQL, which tells no
  LiveView.
  """
  @spec authorize(Scope.t() | User.t() | nil, permission() | atom()) ::
          :ok | {:error, :unauthorized}
  def authorize(%Scope{system?: true}, _permission), do: :ok

  def authorize(%Scope{user: %User{id: id}}, permission) do
    id |> Accounts.get_user() |> authorize(permission)
  end

  def authorize(%Scope{}, _permission), do: {:error, :unauthorized}

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
