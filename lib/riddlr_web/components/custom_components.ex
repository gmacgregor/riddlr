defmodule RiddlrWeb.CustomComponents do
  use Phoenix.Component
  use Gettext, backend: RiddlrWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: RiddlrWeb.Endpoint,
    router: RiddlrWeb.Router,
    statics: RiddlrWeb.static_paths()

  import Riddlr.Utils.User
  import Phoenix.LiveView.JS

  # ─── Helpers ──────────────────────────────────────────────────────────────────

  defp format_time(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> IO.iodata_to_binary()
  end

  defp format_countdown(seconds, :long) do
    days = div(seconds, 86_400)
    rem_day = rem(seconds, 86_400)
    hours = div(rem_day, 3600)
    minutes = div(rem(rem_day, 3600), 60)
    secs = rem(rem_day, 60)

    hms =
      :io_lib.format("~2..0B:~2..0B:~2..0B", [hours, minutes, secs])
      |> IO.iodata_to_binary()

    if days > 0 do
      day_label = if days == 1, do: "day", else: "days"
      "#{days} #{day_label}, #{hms}"
    else
      hms
    end
  end

  defp format_countdown(seconds, :short) do
    total_hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    total_hours_str = Integer.to_string(total_hours) |> String.pad_leading(2, "0")
    minutes_str = Integer.to_string(minutes) |> String.pad_leading(2, "0")
    secs_str = Integer.to_string(secs) |> String.pad_leading(2, "0")

    "#{total_hours_str}:#{minutes_str}:#{secs_str}"
  end

  # ─── Lobby / Pre-game ─────────────────────────────────────────────────────────

  @doc "Pre-game countdown shown in the lobby while waiting for a riddle to go live."
  attr :riddle, :map, required: true
  attr :time_remaining, :integer, required: true
  attr :format, :atom, values: [:long, :short], default: :long

  def game_countdown(assigns) do
    ~H"""
    <div
      :if={@riddle.play_status == "scheduled" || @riddle.play_status == "ready"}
      class="rg-pre-game"
      id="state-pregame"
    >
      <p class="rg-pre-game__label">🧩 Riddle drops in</p>
      <time
        id="countdown"
        phx-hook=".Countdown"
        data-seconds={@time_remaining}
        data-format={Atom.to_string(@format)}
        class="rg-countdown"
        aria-live="polite"
        aria-atomic="true"
      >
        {format_countdown(@time_remaining, @format)}
      </time>
      <p class="rg-pre-game__prompt">⚡ Get ready to guess!</p>
    </div>
    """
  end

  # ─── Active Game ──────────────────────────────────────────────────────────────

  @doc "Time-remaining bar shown during an active game."
  attr :time_remaining, :integer, required: true

  def game_time_remaining(assigns) do
    ~H"""
    <div class="rg-time-bar">
      <span class="rg-time-bar__label">⏱ Time left</span>
      <time
        class="rg-time-bar__value leading-none"
        aria-live="polite"
        aria-atomic="true"
        id="countdown-timer"
        phx-hook=".SolveTimer"
        data-seconds={@time_remaining}
      >
        <span data-timer-display>{format_time(@time_remaining)}</span>
      </time>
    </div>
    """
  end

  # @doc "Riddle text with word-by-word reveal animation."
  # attr :riddle, :map, required: true

  # def game_riddle_text(assigns) do
  #   ~H"""
  #   <p
  #     id="riddle-description"
  #     class="rg-riddle-text"
  #     phx-hook=".RiddleReveal"
  #     data-text={@riddle.description}
  #   >
  #     {@riddle.description}
  #   </p>
  #   """
  # end

  # ─── Shared Avatar ────────────────────────────────────────────────────────────

  @doc "Colored initial avatar. Color is derived from username if not provided."
  attr :letter, :string, required: true
  attr :color, :string, default: nil
  attr :username, :string, default: nil

  def rg_avatar(assigns) do
    assigns =
      assign_new(assigns, :resolved_color, fn ->
        cond do
          assigns[:color] -> assigns[:color]
          assigns[:username] -> avatar_color(assigns[:username])
          true -> "purple"
        end
      end)

    ~H"""
    <div
      class={"rg-avatar rg-avatar--#{@resolved_color}"}
      aria-hidden="true"
    >
      {@letter}
    </div>
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

  # ─── Round Complete Header ────────────────────────────────────────────────────

  @doc "Round complete / time's up header with riddle recap and accepted answers."
  attr :riddle, :map, required: true
  attr :outcome, :atom, values: [:solved, :expired], required: true
  attr :solver_username, :string, default: nil
  attr :solve_time, :integer, default: nil

  def game_round_header(assigns) do
    ~H"""
    <section
      class={["rg-round-header", @outcome == :expired && "rg-round-header--expired"]}
      aria-label="Round result"
    >
      <span class="rg-round-header__emoji" aria-hidden="true">
        {if @outcome == :solved, do: "🎉", else: "⏰"}
      </span>
      <h1 class="rg-round-header__title">
        {if @outcome == :solved, do: "Round Complete!", else: "Time's Up!"}
      </h1>
      <p class="rg-round-header__subtitle">
        {if @outcome == :solved and @solver_username do
          solve_str = if @solve_time, do: " in #{format_time(@solve_time)}", else: ""
          "Solved#{solve_str} by #{@solver_username}"
        else
          "Better luck next time"
        end}
      </p>

      <p class="rg-round-riddle-text">{@riddle.description}</p>

      <div class="rg-answers" aria-label="Accepted answers">
        <span class="rg-answers__label">Accepted Answers</span>
        <div class="rg-answers__pills">
          <span :for={answer <- @riddle.answers} class="rg-pill">"{answer}"</span>
        </div>
      </div>
    </section>
    """
  end

  # ─── Game Leaderboard ─────────────────────────────────────────────────────────

  @doc "Top solvers leaderboard with podium (top 3) and ranked list."
  attr :top_solvers, :list, required: true
  attr :solver_count, :integer, default: nil

  def game_leaderboard(assigns) do
    assigns =
      assigns
      |> assign(:podium, Enum.take(assigns.top_solvers, 3))
      |> assign(:ranked, Enum.drop(assigns.top_solvers, 3))

    ~H"""
    <div class="rg-leaderboard" aria-label="Game leaderboard">
      <%!-- Podium top 3 --%>
      <div :if={@podium != []} class="rg-podium">
        <div
          :for={solver <- @podium}
          class={["rg-podium__card", podium_card_class(solver.placement)]}
        >
          <span class="rg-podium__badge" aria-hidden="true">{podium_badge(solver.placement)}</span>
          <div class={["rg-podium__avatar", podium_avatar_class(solver.placement)]} aria-hidden="true">
            {String.first(solver.username) |> String.upcase()}
          </div>
          <span class={["rg-podium__name", podium_name_class(solver.placement)]}>
            {solver.username}
          </span>
          <span :if={solver.solve_time_display} class="rg-podium__time">
            +{solver.solve_time_display}
          </span>
        </div>
      </div>

      <div :if={@ranked != []} class="rg-divider"></div>

      <%!-- Ranked list 4th+ --%>
      <div :if={@ranked != []} class="rg-ranks">
        <div :for={solver <- @ranked} class="rg-rank">
          <span class="rg-rank__number" aria-label={"Rank #{solver.placement}"}>
            {solver.placement}
          </span>
          <div
            class={"rg-rank__avatar rg-rank__avatar--#{avatar_color(solver.username)}"}
            aria-hidden="true"
          >
            {String.first(solver.username) |> String.upcase()}
          </div>
          <span class="rg-rank__name">{solver.username}</span>
          <span :if={solver.solve_time_display} class="rg-rank__time">
            +{solver.solve_time_display}
          </span>
        </div>
      </div>

      <button
        :if={@solver_count && @solver_count > length(@top_solvers)}
        class="rg-show-all"
        type="button"
      >
        Show all {@solver_count} solvers ▼
      </button>
    </div>
    """
  end

  defp podium_card_class(1), do: "rg-podium__card--gold"
  defp podium_card_class(2), do: "rg-podium__card--silver"
  defp podium_card_class(3), do: "rg-podium__card--bronze"
  defp podium_card_class(_), do: ""

  defp podium_avatar_class(1), do: "rg-podium__avatar--gold"
  defp podium_avatar_class(2), do: "rg-podium__avatar--silver"
  defp podium_avatar_class(3), do: "rg-podium__avatar--bronze"
  defp podium_avatar_class(_), do: ""

  defp podium_name_class(1), do: "rg-podium__name--gold"
  defp podium_name_class(2), do: "rg-podium__name--silver"
  defp podium_name_class(3), do: "rg-podium__name--bronze"
  defp podium_name_class(_), do: ""

  defp podium_badge(1), do: "👑"
  defp podium_badge(2), do: "🥈"
  defp podium_badge(3), do: "🥉"
  defp podium_badge(_), do: ""

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
        aria-controls="panel-leaderboard"
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

  defp switch_tab(tab) do
    other = if tab == "leaderboard", do: "chat", else: "leaderboard"

    remove_attribute("hidden", to: "#panel-#{tab}")
    |> set_attribute({"hidden", ""}, to: "#panel-#{other}")
    |> push("switch_tab", value: %{tab: tab})
  end
end
