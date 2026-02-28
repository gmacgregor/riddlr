# Phase 5: Admin Area & Riddle Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create admin-only CRUD UI for riddle management with role-based authorization.

**Architecture:** Single LiveView with live patches for all CRUD operations. Authorization via on_mount hooks (follows UserAuth pattern). Hierarchical role system: super_admin > moderator > editor > viewer > player. Admin layout with separate styling.

**Tech Stack:** Phoenix LiveView 0.20+, Ecto Enums, on_mount hooks, streams for table rendering

---

## Task 1: Add Role Field to Users

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_role_to_users.exs`
- Modify: `lib/riddlr/accounts/user.ex` (schema + changeset)
- Create: `test/riddlr/accounts/user_test.exs` (role tests)

**Step 1: Generate migration**

Run: `mix ecto.gen.migration add_role_to_users`
Expected: Migration file created in `priv/repo/migrations/`

**Step 2: Write migration**

In the generated migration file:

```elixir
defmodule Riddlr.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    create_query = "CREATE TYPE user_role AS ENUM ('super_admin', 'moderator', 'editor', 'viewer', 'player')"
    drop_query = "DROP TYPE user_role"
    execute(create_query, drop_query)

    alter table(:users) do
      add :role, :user_role, default: "player", null: false
    end

    create index(:users, [:role])
  end
end
```

**Step 3: Update User schema**

In `lib/riddlr/accounts/user.ex`, add to schema block:

```elixir
field :role, Ecto.Enum, values: [:super_admin, :moderator, :editor, :viewer, :player], default: :player
```

**Step 4: Add role to registration changeset**

In `lib/riddlr/accounts/user.ex`, update `registration_changeset/3`:

```elixir
def registration_changeset(user, attrs, opts \\ []) do
  user
  |> cast(attrs, [:email, :username, :role])  # Add :role
  |> validate_username(opts)
  |> validate_email(opts)
end
```

**Step 5: Write role validation tests**

Create tests in `test/riddlr/accounts/user_test.exs`:

```elixir
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
```

**Step 6: Run migration**

Run: `mix ecto.migrate`
Expected: Migration successful, user_role type and role column created

**Step 7: Run tests**

Run: `mix test test/riddlr/accounts/user_test.exs`
Expected: Role tests pass

**Step 8: Commit**

Run: `git add . && git commit -m "feat: add role field to users with enum validation"`
Expected: Commit successful

---

## Task 2: Create Authorization Module

**Files:**
- Create: `lib/riddlr/authorization.ex`
- Create: `test/riddlr/authorization_test.exs`

**Step 1: Create Authorization module**

Create `lib/riddlr/authorization.ex`:

```elixir
defmodule Riddlr.Authorization do
  @moduledoc """
  Role-based authorization for Riddlr.
  Permissions are hierarchical: super_admin > moderator > editor > viewer > player
  """

  @role_permissions %{
    super_admin: [:manage_riddles, :manage_users, :moderate_content, :ban_players, :view_analytics],
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
```

**Step 2: Write authorization tests**

Create `test/riddlr/authorization_test.exs`:

```elixir
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
```

**Step 3: Run tests**

Run: `mix test test/riddlr/authorization_test.exs`
Expected: All authorization tests pass

**Step 4: Commit**

Run: `git add . && git commit -m "feat: add Authorization module with role-based permissions"`
Expected: Commit successful

---

## Task 3: Create AdminAuth Module

**Files:**
- Create: `lib/riddlr_web/admin_auth.ex`
- Create: `test/riddlr_web/admin_auth_test.exs`

**Step 1: Create AdminAuth module**

Create `lib/riddlr_web/admin_auth.ex`:

```elixir
defmodule RiddlrWeb.AdminAuth do
  @moduledoc """
  Admin authentication on_mount hooks for LiveView.
  Follows the UserAuth.ex pattern.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias Riddlr.Accounts
  alias Riddlr.Authorization

  def on_mount(:require_admin, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns[:current_user] && Authorization.is_admin?(socket.assigns.current_user) do
      {:cont, socket}
    else
      socket = socket |> put_flash(:error, "You must be an admin to access this page.") |> redirect(to: ~p"/")
      {:halt, socket}
    end
  end

  def on_mount({:require_role, allowed_roles}, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns[:current_user] && socket.assigns.current_user.role in allowed_roles do
      {:cont, socket}
    else
      socket = socket |> put_flash(:error, "You don't have permission.") |> redirect(to: ~p"/")
      {:halt, socket}
    end
  end

  defp mount_current_user(socket, session) do
    case session do
      %{"user_token" => token} ->
        case Accounts.get_user_by_session_token(token) do
          {user, _} -> assign(socket, :current_user, user)
          nil -> assign(socket, :current_user, nil)
        end
      %{} -> assign(socket, :current_user, nil)
    end
  end
end
```

**Step 2: Write AdminAuth tests**

Create `test/riddlr_web/admin_auth_test.exs`:

```elixir
defmodule RiddlrWeb.AdminAuthTest do
  use RiddlrWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Riddlr.AccountsFixtures

  test "redirects non-admin user", %{conn: conn} do
    user = AccountsFixtures.user_fixture(%{role: :player})
    conn = log_in_user(conn, user)
    {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/riddles")
  end

  test "allows editor access", %{conn: conn} do
    user = AccountsFixtures.user_fixture(%{role: :editor})
    conn = log_in_user(conn, user)
    assert {:ok, _view, _html} = live(conn, "/admin/riddles")
  end
end
```

**Step 3: Update test fixtures**

In `test/support/fixtures/accounts_fixtures.ex`, modify `user_fixture/1`:

```elixir
def user_fixture(attrs \\ %{}) do
  role = Map.get(attrs, :role, :player)

  {:ok, user} =
    attrs
    |> Enum.into(%{
      email: unique_user_email(),
      username: unique_username(),
      password: valid_user_password(),
      role: role  # Add this
    })
    |> Riddlr.Accounts.register_user()

  user
end
```

**Step 4: Run tests**

Run: `mix test test/riddlr_web/admin_auth_test.exs`
Expected: Admin auth tests pass

**Step 5: Commit**

Run: `git add . && git commit -m "feat: add AdminAuth module with on_mount hooks"`
Expected: Commit successful

---

## Task 4: Create Admin Riddle LiveView

**Files:**
- Create: `lib/riddlr_web/live/admin/riddle_live/index.ex`
- Create: `lib/riddlr_web/live/admin/riddle_live/index.html.heex`
- Create: `test/riddlr_web/live/admin/riddle_live/index_test.exs`

**Step 1: Create directory structure**

Run: `mkdir -p lib/riddlr_web/live/admin/riddle_live`
Expected: Directory created

**Step 2: Create Index LiveView**

Create `lib/riddlr_web/live/admin/riddle_live/index.ex`:

```elixir
defmodule RiddlrWeb.Admin.RiddleLive.Index do
  use RiddlrWeb, :live_view
  alias Riddlr.Games
  alias Riddlr.Games.Riddle

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Manage Riddles") |> stream(:riddles, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> stream(:riddles, Games.list_riddles(), reset: true) |> assign(:riddle, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket |> assign(:riddle, %Riddle{}) |> assign(:page_title, "New Riddle")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    riddle = Games.get_riddle!(id)
    socket |> assign(:riddle, riddle) |> assign(:page_title, "Edit #{riddle.name}")
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    riddle = Games.get_riddle!(id)
    socket |> assign(:riddle, riddle) |> assign(:page_title, riddle.name)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    riddle = Games.get_riddle!(id)
    {:ok, _} = Games.delete_riddle(riddle)
    {:noreply, socket |> stream_delete(:riddles, riddle) |> put_flash(:info, "Riddle deleted")}
  end

  @impl true
  def handle_info({:riddle_saved, riddle}, socket) do
    {:noreply, stream_insert(socket, :riddles, riddle, at: 0)}
  end
end
```

**Step 3: Create Index template**

Create `lib/riddlr_web/live/admin/riddle_live/index.html.heex` (see full template in original plan - table with actions, modal for form, show panel)

**Step 4: Write index tests**

Create `test/riddlr_web/live/admin/riddle_live/index_test.exs`:

```elixir
defmodule RiddlrWeb.Admin.RiddleLive.IndexTest do
  use RiddlrWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    admin = Riddlr.AccountsFixtures.user_fixture(%{role: :editor})
    %{admin: admin}
  end

  test "lists riddles", %{conn: conn, admin: admin} do
    conn = log_in_user(conn, admin)
    riddle = Riddlr.GamesFixtures.riddle_fixture()
    {:ok, _live, html} = live(conn, ~p"/admin/riddles")
    assert html =~ riddle.name
  end

  test "redirects non-admin", %{conn: conn} do
    player = Riddlr.AccountsFixtures.user_fixture(%{role: :player})
    conn = log_in_user(conn, player)
    {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/riddles")
  end
end
```

**Step 5: Run tests**

Run: `mix test test/riddlr_web/live/admin/riddle_live/index_test.exs`
Expected: Tests pass

**Step 6: Commit**

Run: `git add . && git commit -m "feat: add admin riddle index LiveView with streams"`
Expected: Commit successful

---

## Task 5: Create Form Component

**Files:**
- Create: `lib/riddlr_web/live/admin/riddle_live/form_component.ex`
- Create: `test/riddlr_web/live/admin/riddle_live/form_component_test.exs`

**Step 1: Create FormComponent**

Create `lib/riddlr_web/live/admin/riddle_live/form_component.ex`:

```elixir
defmodule RiddlrWeb.Admin.RiddleLive.FormComponent do
  use RiddlrWeb, :live_component
  alias Riddlr.Games

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header><%= @title %></.header>
      <.simple_form for={@form} id="riddle-form" phx-target={@myself} phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:description]} type="textarea" label="Description" rows="4" required />
        <.input field={@form[:category]} type="text" label="Category" />
        <.input field={@form[:difficulty]} type="select" label="Difficulty"
                prompt="Choose" options={Riddlr.Games.Riddle.difficulties()} />
        <.input field={@form[:solve_time]} type="number" label="Solve Time (seconds)"
                min="10" step="10" required />
        <.input field={@form[:hint]} type="textarea" label="Hint" rows="2" />
        <.input field={@form[:hint_delay]} type="number" label="Hint Delay (seconds)" min="0" />
        <:actions>
          <.button phx-disable-with="Saving..." class="btn-primary">Save</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{riddle: riddle} = assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:title, title(assigns.action)) |> assign_form(Games.change_riddle(riddle))}
  end

  @impl true
  def handle_event("validate", %{"riddle" => params}, socket) do
    changeset = Games.change_riddle(socket.assigns.riddle, params) |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"riddle" => params}, socket) do
    save(socket, socket.assigns.action, params)
  end

  defp save(socket, :edit, params) do
    case Games.update_riddle(socket.assigns.riddle, params) do
      {:ok, riddle} ->
        send(self(), {:riddle_saved, riddle})
        {:noreply, socket |> put_flash(:info, "Updated") |> push_patch(to: socket.assigns.patch)}
      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :new, params) do
    case Games.create_riddle(params) do
      {:ok, riddle} ->
        send(self(), {:riddle_saved, riddle})
        {:noreply, socket |> put_flash(:info, "Created") |> push_patch(to: socket.assigns.patch)}
      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))
  defp title(:new), do: "New Riddle"
  defp title(:edit), do: "Edit Riddle"
end
```

**Step 2: Write form tests**

Create `test/riddlr_web/live/admin/riddle_live/form_component_test.exs` with create/edit tests

**Step 3: Run tests**

Run: `mix test test/riddlr_web/live/admin/riddle_live/form_component_test.exs`
Expected: Form tests pass

**Step 4: Commit**

Run: `git add . && git commit -m "feat: add riddle form component with validation"`
Expected: Commit successful

---

## Task 6: Add Admin Layout and Routes

**Files:**
- Create: `lib/riddlr_web/components/layouts/admin.html.heex`
- Modify: `lib/riddlr_web/router.ex`

**Step 1: Create admin layout**

Create `lib/riddlr_web/components/layouts/admin.html.heex`:

```heex
<header class="navbar bg-base-200">
  <div class="flex-1">
    <.link navigate={~p"/"} class="btn btn-ghost text-xl">Riddlr</.link>
    <span class="badge badge-primary ml-2">Admin</span>
  </div>
  <div class="flex-none">
    <ul class="menu menu-horizontal px-1">
      <li><.link navigate={~p"/admin/riddles"}>Riddles</.link></li>
      <li><.link navigate={~p"/"}>Back to Site</.link></li>
    </ul>
  </div>
</header>
<main class="container mx-auto px-4 py-8">
  <.flash_group flash={@flash} />
  <%= @inner_content %>
</main>
```

**Step 2: Add admin routes**

In `lib/riddlr_web/router.ex`, add after authentication routes:

```elixir
scope "/admin", RiddlrWeb.Admin do
  pipe_through [:browser, :require_authenticated_user]

  live_session :admin,
    on_mount: [{RiddlrWeb.AdminAuth, :require_admin}],
    layout: {RiddlrWeb.Layouts, :admin} do
    live "/riddles", RiddleLive.Index, :index
    live "/riddles/new", RiddleLive.Index, :new
    live "/riddles/:id/edit", RiddleLive.Index, :edit
    live "/riddles/:id", RiddleLive.Index, :show
  end
end
```

**Step 3: Update index template to use modal**

In `lib/riddlr_web/live/admin/riddle_live/index.html.heex`, add modal section:

```heex
<.modal :if={@live_action in [:new, :edit]} id="riddle-modal" show on_cancel={JS.patch(~p"/admin/riddles")}>
  <.live_component
    module={RiddlrWeb.Admin.RiddleLive.FormComponent}
    id={@riddle.id || :new}
    action={@live_action}
    riddle={@riddle}
    patch={~p"/admin/riddles"}
  />
</.modal>
```

**Step 4: Test routes**

Run: `iex -S mix phx.server`
Navigate: http://localhost:4000/admin/riddles (as admin)
Expected: Admin area loads with riddles table

**Step 5: Run full test suite**

Run: `mix test`
Expected: All tests pass

**Step 6: Commit**

Run: `git add . && git commit -m "feat: add admin layout and routes with live_session"`
Expected: Commit successful

---

## Task 7: Add Admin Seeds and Manual Verification

**Files:**
- Modify: `priv/repo/seeds.exs`

**Step 1: Add admin user to seeds**

In `priv/repo/seeds.exs`, add at the top:

```elixir
alias Riddlr.Accounts

# Create admin user for testing
{:ok, admin} = Accounts.register_user(%{
  email: "admin@example.com",
  username: "admin",
  password: "adminpassword123",
  role: :super_admin
})

IO.puts("Created admin user: admin@example.com / adminpassword123")

{:ok, player} = Accounts.register_user(%{
  email: "player@example.com",
  username: "player",
  password: "playerpassword123",
  role: :player
})

IO.puts("Created player user: player@example.com / playerpassword123")
```

**Step 2: Reset database and seed**

Run: `mix ecto.reset`
Expected: Database dropped, created, migrated, and seeded

**Step 3: Manual verification**

Run: `mix phx.server`

Test flow:
1. Login as admin (admin@example.com / adminpassword123)
2. Navigate to /admin/riddles
3. Create new riddle
4. Edit existing riddle
5. View riddle details
6. Delete riddle
7. Logout and login as player (player@example.com / playerpassword123)
8. Try to access /admin/riddles
9. Verify redirect to home with error message

Expected: All CRUD operations work for admin, player redirected

**Step 4: Run format and compile**

Run: `mix format && mix compile --warnings-as-errors`
Expected: Code formatted, no warnings

**Step 5: Final commit**

Run: `git add . && git commit -m "feat: add admin and player seeds for manual testing"`
Expected: Commit successful

---

## Verification Checklist

- [ ] Role enum added to users (super_admin, moderator, editor, viewer, player)
- [ ] Default role is player
- [ ] Authorization module with permission checks
- [ ] AdminAuth on_mount hooks redirect non-admin users
- [ ] Admin riddle index LiveView uses streams
- [ ] Form component validates riddle fields
- [ ] Admin layout with navigation
- [ ] Routes protected with live_session :admin
- [ ] Admin user can CRUD riddles
- [ ] Player user redirected from admin area
- [ ] All tests passing
- [ ] Code formatted

---

## Next Steps

After completing Phase 5:
- **Phase 6**: Tag System (optional - can skip to Phase 7)
- **Phase 7**: Game Lifecycle State Machine (Oban workers for auto-transitions)
- **Phase 8**: Game Lobby with Phoenix Presence

---

## Notes

- Single LiveView pattern (not multi-LiveView) for simpler routing
- Modal form preserves scroll position and user context
- Streams prevent memory issues with large riddle lists
- Role hierarchy allows future expansion (e.g., moderator role for Phase 15)
- Admin layout can be enhanced later with sidebar navigation
- Answer array handling deferred to form component (use inputs_for or custom JS)
