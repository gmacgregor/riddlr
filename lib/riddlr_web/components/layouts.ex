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

  # The topbar: brand mark, a middle slot and the account controls. Shared by
  # `game/1` and the admin layout so every screen has the same header.
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

  # The colour mode switch: one button that steps to the next mode on each
  # press (see `assets/js/app.js`). It sets `data-theme` on <html> and writes
  # the `theme` cookie in the browser, so it works mid-game with no server
  # round trip. The button holds one icon per mode and CSS shows the one that
  # matches <html data-theme>, so the icon never goes stale. Each icon carries
  # the button label for its mode, which JS copies onto the button.
  # `phx-update="ignore"` keeps LiveView from undoing the player's pick.
  attr :theme, :string, required: true

  @spec theme_switch(map()) :: Phoenix.LiveView.Rendered.t()
  defp theme_switch(assigns) do
    assigns = assign(assigns, :themes, Theme.themes())

    ~H"""
    <button
      id="theme-switch"
      type="button"
      class="rg-theme"
      aria-label={theme_switch_label(@theme)}
      phx-update="ignore"
    >
      <svg
        :for={theme <- @themes}
        class={["rg-theme__icon", "rg-theme__icon--#{theme}"]}
        data-theme-icon={theme}
        data-label={theme_switch_label(theme)}
        width="15"
        height="15"
        viewBox="0 0 15 15"
        fill="none"
        aria-hidden="true"
      >
        <path d={theme_icon_path(theme)} fill="currentColor" />
      </svg>
    </button>
    """
  end

  @spec theme_switch_label(Theme.t()) :: String.t()
  defp theme_switch_label(theme) do
    "Colour mode: #{Theme.label(theme)}. Switch to #{Theme.label(Theme.next(theme))}"
  end

  # Radix icons (https://www.radix-ui.com/icons): eye closed, eye none and
  # eye open, from darkest mode to lightest.
  @spec theme_icon_path(Theme.t()) :: String.t()
  defp theme_icon_path("dark"),
    do:
      "M5.58284 12.5867C5.5113 12.8531 5.23703 13.0113 4.97054 12.9402C4.70421 12.8686 4.54496 12.5943 4.61605 12.3279L5.58284 12.5867ZM10.3826 12.3279C10.4539 12.5945 10.2956 12.8686 10.0291 12.9402C9.76261 13.0113 9.48834 12.8531 9.41681 12.5867L10.3826 12.3279ZM14.1375 6.15505C14.2977 5.98633 14.5595 5.94799 14.7644 6.07595C14.9692 6.20395 15.0496 6.45576 14.9685 6.6736L14.9236 6.76442C14.4845 7.46696 13.962 8.1052 13.3689 8.66188L14.5711 9.86402L14.6355 9.94214C14.7636 10.1362 14.7419 10.4002 14.5711 10.571C14.4003 10.7419 14.1363 10.7636 13.9422 10.6355L13.8641 10.571L12.5994 9.3064C11.8032 9.90116 10.9077 10.3602 9.93243 10.6492L10.3826 12.3279L9.89923 12.4568L9.41681 12.5867L8.95783 10.8777C8.48648 10.958 7.99975 10.9998 7.49983 10.9998C6.9991 10.9998 6.51194 10.9563 6.03987 10.8757L5.58284 12.5867L5.09945 12.4568L4.61605 12.3279L5.06527 10.6492C4.09036 10.3601 3.19423 9.90202 2.39829 9.30738L1.1356 10.571C0.940342 10.7662 0.623806 10.7662 0.428567 10.571C0.233426 10.3758 0.233415 10.0593 0.428567 9.86402L1.62973 8.66188C1.10375 8.1681 0.633248 7.61 0.227396 6.99977L0.0760295 6.76442L0.0311078 6.6736C-0.0498844 6.45577 0.0304399 6.20394 0.235208 6.07595C0.440189 5.94795 0.701937 5.98637 0.862159 6.15505L0.923682 6.23513L1.20102 6.65114C2.63903 8.68678 4.86748 9.99974 7.49983 9.99976C10.3076 9.99976 12.6564 8.50638 14.076 6.23513L14.1375 6.15505Z"

  defp theme_icon_path("dusk"),
    do:
      "M12.6465 1.64651C12.8418 1.45125 13.1583 1.45125 13.3535 1.64651C13.5488 1.84177 13.5488 2.15828 13.3535 2.35354L11.6377 4.06838C12.9756 4.81468 14.0967 5.91192 14.9239 7.23537C15.0124 7.37719 15.0235 7.55204 14.9571 7.70217L14.9239 7.76467C13.3435 10.2933 10.6922 12 7.50002 12C6.36232 12 5.29371 11.7822 4.31741 11.3887L2.35354 13.3535C2.15828 13.5488 1.84177 13.5488 1.64651 13.3535C1.45125 13.1583 1.45125 12.8418 1.64651 12.6465L3.36135 10.9307C2.02399 10.1844 0.903113 9.08773 0.0761963 7.76467C-0.0249881 7.60262 -0.0249956 7.39742 0.0761963 7.23537L0.227563 7.00002C1.82294 4.60124 4.4078 3.00002 7.50002 3.00002C8.63727 3.00002 9.70568 3.21714 10.6817 3.61037L12.6465 1.64651ZM5.09573 10.6104C5.84657 10.8632 6.65217 11 7.50002 11C10.1963 11 12.4661 9.62071 13.8994 7.50002C13.1227 6.35087 12.0992 5.42186 10.8965 4.80959L5.09573 10.6104ZM7.50002 4.00002C4.80354 4.00002 2.53299 5.37907 1.09963 7.50002C1.87617 8.64906 2.89999 9.57724 4.10256 10.1895L9.90335 4.3887C9.15289 4.13599 8.34748 4.00002 7.50002 4.00002Z"

  defp theme_icon_path("light"),
    do:
      "M7.50002 3C10.6922 3 13.3435 4.70671 14.9239 7.23535C15.0124 7.37717 15.0235 7.55201 14.9571 7.70215L14.9239 7.76465C13.3435 10.2933 10.6922 12 7.50002 12C4.30788 12 1.65659 10.2933 0.0761963 7.76465C-0.0249881 7.6026 -0.0249956 7.3974 0.0761963 7.23535L0.227563 7C1.82294 4.60122 4.4078 3 7.50002 3ZM7.50002 4C4.80354 4 2.53299 5.37905 1.09963 7.5C2.53299 9.62094 4.80354 11 7.50002 11C10.1963 11 12.4661 9.62068 13.8994 7.5C12.4661 5.3793 10.1963 4 7.50002 4ZM7.50002 5.5C8.60459 5.5 9.50002 6.39543 9.50002 7.5C9.50002 8.60457 8.60459 9.5 7.50002 9.5C6.39545 9.5 5.50002 8.60457 5.50002 7.5C5.50002 6.39543 6.39545 5.5 7.50002 5.5Z"

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
  Returns `"page"` when `current_path` is `section_path` or a page under it,
  so the admin nav can mark the current section. Returns `nil` otherwise.
  """
  @spec admin_nav_current(String.t() | nil, String.t()) :: String.t() | nil
  def admin_nav_current(current_path, section_path) when is_binary(current_path) do
    if current_path == section_path or String.starts_with?(current_path, section_path <> "/"),
      do: "page"
  end

  def admin_nav_current(_current_path, _section_path), do: nil

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
