defmodule RiddlrWeb.CustomComponents do
  use Phoenix.Component
  use Gettext, backend: RiddlrWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: RiddlrWeb.Endpoint,
    router: RiddlrWeb.Router,
    statics: RiddlrWeb.static_paths()

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
end
