defmodule RiddlrWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use RiddlrWeb, :html

  alias RiddlrWeb.GameComponents

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header> --%>

    <%!-- <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main> --%>

    <main class="rg-viewport">
      <div class="rg-frame" role="main" aria-label="Riddlr game">
        <header class="rg-header">
          <.link navigate={~p"/"} class="rg-header__brand">
            <span aria-hidden="true">🧩</span> Riddlr
          </.link>
          <.auth_menu current_scope={@current_scope} />
        </header>

        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the shell for the player screens: Home, Lobby, Play and Results.

  A full-height grid with the topbar on top and a scrolling `main` below.
  Styled by `assets/css/game.css`. Account screens and admin keep `app/1`.

  ## Examples

      <Layouts.game flash={@flash} current_scope={@current_scope}>
        <:status><span class="rg-pill">Live</span></:status>
        <h1>Content</h1>
      </Layouts.game>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :status, doc: "the riddle status shown in the middle of the topbar"
  slot :inner_block, required: true

  @spec game(map()) :: Phoenix.LiveView.Rendered.t()
  def game(assigns) do
    ~H"""
    <div class="rg-app">
      <header class="rg-topbar">
        <div class="rg-topbar__in">
          <.link id="topbar-brand" navigate={~p"/"} class="rg-brand" aria-label="Riddlr home">
            <span class="rg-brand__mark" aria-hidden="true">
              <span class="rg-brand__q">?</span><span class="rg-brand__word">riddlr</span>
            </span>
          </.link>
          <div class="rg-topbar__mid" aria-live="polite">{render_slot(@status)}</div>
          <.topbar_account current_scope={@current_scope} />
        </div>
      </header>

      <main class="rg-main">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :current_scope, :map, default: nil

  @spec topbar_account(map()) :: Phoenix.LiveView.Rendered.t()
  defp topbar_account(assigns) do
    ~H"""
    <nav class="rg-topbar__account" aria-label="Account">
      <%= if user = @current_scope && @current_scope.user do %>
        <.link id="topbar-me-chip" navigate={~p"/users/settings"} class="rg-me-chip">
          <GameComponents.tile
            initial={GameComponents.initial(user.username)}
            tone={GameComponents.tone(user.username, user.username)}
            size="sm"
          />
          <span class="rg-me-chip__text">
            <span class="rg-me-chip__name">{user.username}</span>
          </span>
        </.link>
        <.link id="topbar-log-out" href={~p"/users/log-out"} method="delete" class="rg-link-btn">
          Log out
        </.link>
      <% else %>
        <.link id="topbar-log-in" navigate={~p"/users/log-in"} class="rg-link-btn">Log in</.link>
      <% end %>
    </nav>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="rg-flash-group" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
