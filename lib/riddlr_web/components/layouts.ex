defmodule RiddlrWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use RiddlrWeb, :html

  alias RiddlrWeb.GameComponents
  alias RiddlrWeb.Theme

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

      <Layouts.game flash={@flash} current_scope={@current_scope} theme={@theme}>
        <:status><GameComponents.status_pill kind={:lobby} number={@riddle.number} /></:status>
        <h1>Content</h1>
      </Layouts.game>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :theme, :string,
    required: true,
    doc: "the colour mode, checked in the topbar switch (see `RiddlrWeb.Theme`)"

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
      <.topbar current_scope={@current_scope} theme={@theme} live>
        {render_slot(@status)}
      </.topbar>

      <main class={["rg-main", @locked && "is-locked"]}>
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  # The topbar: brand mark, a middle slot and the account controls. The admin
  # has its own frozen copy in `RiddlrWeb.AdminComponents`.
  attr :current_scope, :map, default: nil
  attr :theme, :string, required: true
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
        <.theme_switch theme={@theme} />
        <.topbar_account current_scope={@current_scope} />
      </div>
    </header>
    """
  end

  # The colour mode switch: a doodled eye, open for light and shut for dark.
  # Each press flips the mode (see `assets/js/app.js`): JS sets `data-theme`
  # on <html>, writes the `theme` cookie and sets the `theme-color` meta, so
  # it works mid-game with no server round trip. The one SVG holds both
  # drawings and CSS shows the one that matches <html data-theme>, so the eye
  # never goes stale. Each drawing carries the button label and browser bar
  # colour for its mode, which JS copies onto the page.
  # `phx-update="ignore"` keeps LiveView from undoing the player's pick.
  attr :theme, :string, required: true

  @spec theme_switch(map()) :: Phoenix.LiveView.Rendered.t()
  defp theme_switch(assigns) do
    ~H"""
    <button
      id="theme-switch"
      type="button"
      class="rg-theme"
      aria-label={theme_switch_label(@theme)}
      phx-update="ignore"
    >
      <svg class="rg-theme__eye" viewBox="0 0 40 30" aria-hidden="true" focusable="false">
        <g
          class="rg-theme__eye--light"
          data-theme-icon="light"
          data-label={theme_switch_label("light")}
          data-color={Theme.theme_color("light")}
        >
          <path d="M3 15.5 C9.5 4.5 30 4 37.2 14.6 C30.5 26 10 26.5 3 15.5 Z" />
          <circle cx="20.2" cy="15.2" r="6.2" />
          <circle class="rg-theme__pupil" cx="20.4" cy="15.4" r="2.7" />
          <circle class="rg-theme__glint" cx="21.6" cy="14" r="1" />
          <path d="M8.5 9.6 L5.3 5 M13.4 6.6 L11.8 1.4 M20 5.6 L20.2 0.6 M26.6 6.7 L28.4 1.6 M31.7 9.8 L35 5.4" />
        </g>
        <g
          class="rg-theme__eye--dark"
          data-theme-icon="dark"
          data-label={theme_switch_label("dark")}
          data-color={Theme.theme_color("dark")}
        >
          <path d="M3 13 C9.5 22.5 30 23 37.2 12.8" />
          <path d="M8.6 18.4 L5.8 23.2 M13.6 20.4 L12.2 25.6 M20 21.4 L20.2 26.6 M26.6 20.6 L28.2 25.8 M31.6 18.4 L34.8 22.8" />
        </g>
      </svg>
    </button>
    """
  end

  @spec theme_switch_label(Theme.t()) :: String.t()
  defp theme_switch_label(theme) do
    "Colour mode: #{Theme.label(theme)}. Switch to #{Theme.label(Theme.next(theme))}"
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
