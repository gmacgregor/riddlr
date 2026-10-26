defmodule RiddlrWeb.CustomComponents do
  use Phoenix.Component
  use Gettext, backend: RiddlrWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: RiddlrWeb.Endpoint,
    router: RiddlrWeb.Router,
    statics: RiddlrWeb.static_paths()

  import Phoenix.LiveView.JS

  # ─── Helpers ──────────────────────────────────────────────────────────────────

  @doc "Ordinal for a finishing position: 1 -> \"1st\"."
  def placement_text(n), do: RiddlrWeb.GameCopy.ordinal(n)

  # ─── Solve Badge ──────────────────────────────────────────────────────────────

  @doc """
  Marks a correct answer in a feed.

  `text` is the answer itself and must stay `nil` while the round runs — the
  feed would otherwise hand the answer to everyone still guessing.
  """
  attr :placement, :integer, default: nil
  attr :text, :string, default: nil
  attr :class, :any, default: nil

  def game_solve_badge(assigns) do
    ~H"""
    <span class={["rg-solve-badge", @class]}>
      🎯 solved it{if @placement, do: " — #{placement_text(@placement)}"}{if @text, do: ": #{@text}"}
    </span>
    """
  end

  # ─── Nav Bar ──────────────────────────────────────────────────────────────────

  @doc "Bottom navigation bar shared across all game screens."
  attr :active, :atom, values: [:home, :riddle, :leaderboard], default: :riddle
  attr :game_id, :string, default: nil

  def game_nav(assigns) do
    ~H"""
    <nav class="rg-nav" aria-label="Game navigation">
      <%!-- Home --%>
      <.link
        href={~p"/"}
        class={["rg-nav__tab", @active == :home && "rg-nav__tab--active"]}
        aria-label="Home"
        aria-current={if @active == :home, do: "page"}
      >
        <svg
          class="rg-nav__icon"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
          focusable="false"
        >
          <path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8" />
          <path d="M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
        </svg>
        <span class="rg-nav__label">Home</span>
      </.link>

      <%!-- Riddle (current game) --%>
      <button
        class={["rg-nav__tab", @active == :riddle && "rg-nav__tab--active"]}
        aria-label="Riddle"
        aria-current={@active == :riddle && "page"}
        disabled={@active == :riddle}
        type="button"
      >
        <svg
          class="rg-nav__icon"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
          focusable="false"
        >
          <path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z" />
        </svg>
        <span class="rg-nav__label">Riddle</span>
        <span :if={@active == :riddle} class="rg-nav__dot" aria-hidden="true"></span>
      </button>

      <%!-- All-time Leaderboard (future route) --%>
      <button
        class="rg-nav__tab rg-nav__tab--disabled"
        aria-label="All-time Leaderboard (coming soon)"
        aria-disabled="true"
        type="button"
      >
        <svg
          class="rg-nav__icon"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
          focusable="false"
        >
          <path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6" />
          <path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18" />
          <path d="M4 22h16" />
          <path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22" />
          <path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22" />
          <path d="M18 2H6v7a6 6 0 0 0 12 0V2Z" />
        </svg>
        <span class="rg-nav__label">Leaderboard</span>
      </button>
    </nav>
    """
  end

  # ─── Tab Bar ──────────────────────────────────────────────────────────────────

  @doc "Leaderboard / Chat tab switcher for the post-game view."
  attr :active_tab, :atom, values: [:leaderboard, :chat], required: true
  attr :unread_chat, :integer, default: 0

  def game_tab_bar(assigns) do
    ~H"""
    <div id="tab-bar" class="rg-tab-bar" role="tablist" aria-label="Post-game content tabs">
      <button
        class={["rg-tab", @active_tab == :leaderboard && "rg-tab--active"]}
        role="tab"
        aria-selected={to_string(@active_tab == :leaderboard)}
        aria-controls="panel-board"
        type="button"
        phx-click={switch_tab("leaderboard")}
      >
        🏆 Leaderboard
        <span :if={@active_tab == :leaderboard} class="rg-tab__indicator" aria-hidden="true"></span>
      </button>
      <button
        class={["rg-tab", @active_tab == :chat && "rg-tab--active"]}
        role="tab"
        aria-selected={to_string(@active_tab == :chat)}
        aria-controls="panel-chat"
        type="button"
        phx-click={switch_tab("chat")}
      >
        <span class="rg-tab__row">
          💬 Chat
          <span
            :if={@unread_chat > 0}
            class="rg-tab__badge"
            aria-label={"#{@unread_chat} new messages"}
          >
            {@unread_chat}
          </span>
        </span>
        <span :if={@active_tab == :chat} class="rg-tab__indicator" aria-hidden="true"></span>
      </button>
    </div>
    """
  end

  defp panel_id("leaderboard"), do: "#panel-board"
  defp panel_id("chat"), do: "#panel-chat"

  defp switch_tab(tab) do
    other = if tab == "leaderboard", do: "chat", else: "leaderboard"

    remove_class("is-off", to: panel_id(tab))
    |> add_class("is-off", to: panel_id(other))
    |> push("switch_tab", value: %{tab: tab})
  end
end
