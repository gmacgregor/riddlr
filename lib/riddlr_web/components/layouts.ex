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
  Renders the shell for every screen outside admin: the player screens
  (Home, Lobby, Play, Results) and the account screens.

  A full-height grid with the topbar on top and a scrolling `main` below.
  Styled by `assets/css/game.css`.

  ## Examples

      <Layouts.game flash={@flash} current_scope={@current_scope}>
        <:status><GameComponents.status_pill kind={:lobby} number={@riddle.number} /></:status>
        <h1>Content</h1>
      </Layouts.game>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :locked, :boolean,
    default: false,
    doc: "stops `main` scrolling, for screens that scroll their own parts (Play)"

  slot :status,
    doc: "the riddle status shown in the middle of the topbar, a `GameComponents.status_pill/1`"

  slot :inner_block, required: true

  @spec game(map()) :: Phoenix.LiveView.Rendered.t()
  def game(assigns) do
    ~H"""
    <div class="rg-app">
      <.topbar current_scope={@current_scope} live>{render_slot(@status)}</.topbar>

      <main class={["rg-main", @locked && "is-locked"]}>
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  # The topbar: brand mark, a middle slot and the account controls. Shared by
  # `game/1` and the admin layout so every screen has the same header.
  attr :current_scope, :map, default: nil
  attr :live, :boolean, default: false, doc: "announces changes to the middle slot"
  slot :inner_block, doc: "content for the middle of the bar"

  @spec topbar(map()) :: Phoenix.LiveView.Rendered.t()
  defp topbar(assigns) do
    ~H"""
    <header class="rg-topbar">
      <div class="rg-topbar__in">
        <.link id="topbar-brand" navigate={~p"/"} class="rg-brand" aria-label="Riddlr home">
          <span class="rg-brand__mark" aria-hidden="true">
            <span class="rg-brand__q">?</span><span class="rg-brand__word">riddlr</span>
          </span>
        </.link>
        <div class="rg-topbar__mid" aria-live={@live && "polite"}>{render_slot(@inner_block)}</div>
        <.topbar_account current_scope={@current_scope} />
      </div>
    </header>
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
end
