defmodule RiddlrWeb.GameLive.Play do
  @moduledoc """
  Live game view — answer submission, scoring, real-time gameplay.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{Accounts, Games, Gameplay}

  @answer_max_length 500
  @try_again_messages [
    "Uuuh… no! Think harder.",
    "Ooopsie whoopise, not quite. Go on, guess again!",
    "Good guess, but no! So close… or not.",
    "Nooooope! Wrack that brain.",
    "Not so, unfortunately. Back to the drawing board!"
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # DB query in both connected and disconnected mount is intentional: we need
    # play_status to decide the redirect destination before the socket connects.
    case Games.fetch_riddle(id) do
      {:ok, riddle} ->
        case riddle.play_status do
          status when status in ["closed", "scheduled", "ready"] ->
            {:ok,
             socket
             |> put_flash(:error, "Game is not live yet.")
             |> push_navigate(to: ~p"/game/#{id}/lobby")}

          "archived" ->
            {:ok,
             socket
             |> put_flash(:info, "That game has ended.")
             |> push_navigate(to: ~p"/")}

          status when status in ["live", "completed"] ->
            user = socket.assigns.current_user

            already_solved =
              status == "live" and
                match?(
                  {:error, :already_solved},
                  Gameplay.check_already_solved(riddle.id, user.id)
                )

            game_completed = status == "completed"

            {initial_answers, top_solvers} =
              if connected?(socket) do
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:archived")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{id}:answer_submitted")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{id}:answer_flagged")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "user:#{user.id}")
                answers = build_initial_feed(riddle.id, game_completed)
                solvers = if game_completed, do: load_top_solvers(riddle.id), else: []
                {answers, solvers}
              else
                {[], []}
              end

            # Track correct answers in assigns so we can re-stream them with highlight
            # when the game completes (stream items don't re-render on outer assign changes).
            correct_answers =
              initial_answers
              |> Enum.filter(& &1.correct)
              |> Map.new(&{&1.id, &1})

            time_remaining =
              if game_completed do
                0
              else
                compute_time_remaining(riddle.live_date, riddle.solve_time)
              end

            if connected?(socket) and not game_completed and time_remaining > 0 do
              Process.send_after(self(), :tick, 1000)
            end

            {:ok,
             socket
             |> assign(:page_title, "Play — #{riddle.name}")
             |> assign(:riddle, riddle)
             |> assign(:game_start_time, riddle.live_date)
             |> assign(:game_completed, game_completed)
             |> assign(:already_solved, already_solved)
             |> assign(:banned, user.account_status == :banned)
             |> assign(:submission_state, nil)
             |> assign(:time_remaining, time_remaining)
             |> assign(:correct_answers, correct_answers)
             |> assign(:top_solvers, top_solvers)
             |> stream(:answers, initial_answers, limit: 100)}
        end

      {:error, :not_found} ->
        {:ok, socket |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("submit_answer", %{"answer" => text}, socket) do
    text = String.trim(text)
    user = socket.assigns.current_user
    riddle = socket.assigns.riddle

    with :ok <- check_not_banned(socket.assigns),
         :ok <- check_game_live(riddle),
         :ok <- Gameplay.check_already_solved(riddle.id, user.id),
         :ok <- Gameplay.check_cooldown(riddle.id, user.id),
         :ok <- validate_input(text) do
      correct? = Gameplay.validate_answer(riddle, text)
      solve_time_ms = compute_offset_ms(socket.assigns.game_start_time)
      timestamp = Gameplay.store_answer(riddle.id, user.id, text, correct?, solve_time_ms)

      answer_data = %{
        id: "#{riddle.id}-#{user.id}-#{timestamp}",
        user_id: user.id,
        username: user.username,
        text: text,
        correct: correct?,
        timestamp: timestamp,
        offset_ms: solve_time_ms,
        show_highlight: false,
        flagged: false,
        chat: false
      }

      Gameplay.broadcast_answer(riddle.id, answer_data)
      Gameplay.moderate_answer_async(riddle.id, answer_data.id, text)

      if correct? do
        placement = Gameplay.calculate_placement(riddle.id, timestamp)
        {:ok, points} = Accounts.award_game_points(user.id, placement)

        if placement == 1 do
          first_solve_time_seconds = solve_time_ms && div(solve_time_ms, 1000)

          if riddle.live_until_solved do
            # live_until_solved games complete immediately on first solve
            stats =
              Gameplay.get_completion_stats(riddle.id)
              |> Map.put(:first_solve_time, first_solve_time_seconds)

            Games.complete_riddle_on_first_solve(riddle.id, user.id, stats)
          else
            # Timed games: record first solver; Oban CompleteRiddleWorker fires at solve_time
            Games.record_first_solver(riddle.id, user.id, first_solve_time_seconds)
          end
        end

        {:noreply,
         socket
         |> push_event("answer-correct", %{})
         |> assign(:already_solved, true)
         |> assign(:submission_state, {:correct, placement, points})}
      else
        socket = assign(socket, :try_again_message, try_again())

        {:noreply,
         socket
         |> assign(:submission_state, :incorrect)
         |> push_event("answer-shake", %{})}
      end
    else
      {:error, :banned} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> push_navigate(to: ~p"/")}

      {:error, reason} ->
        {:noreply, assign(socket, :submission_state, {:error, format_error(reason)})}
    end
  end

  @impl true
  def handle_event("send_chat", %{"message" => text}, socket) do
    text = String.trim(text)
    user = socket.assigns.current_user
    riddle = socket.assigns.riddle

    with :ok <- check_not_banned(socket.assigns),
         :ok <- check_game_completed(riddle),
         :ok <- validate_input(text) do
      chat_data = %{
        id: "chat-#{riddle.id}-#{user.id}-#{System.monotonic_time(:microsecond)}",
        user_id: user.id,
        username: user.username,
        text: text,
        correct: false,
        timestamp: System.monotonic_time(:microsecond),
        offset_ms: nil,
        show_highlight: false,
        flagged: false,
        chat: true
      }

      Gameplay.broadcast_chat(riddle.id, chat_data)
      {:noreply, socket}
    else
      {:error, :banned} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> push_navigate(to: ~p"/")}

      {:error, reason} ->
        {:noreply, assign(socket, :submission_state, {:error, format_error(reason)})}
    end
  end

  @impl true
  def handle_info({:answer_submitted, answer_data}, socket) do
    socket = stream_insert(socket, :answers, answer_data, at: 0)

    socket =
      if answer_data.correct do
        update(socket, :correct_answers, &Map.put(&1, answer_data.id, answer_data))
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:answer_flagged, answer_id}, socket) do
    {:noreply, stream_delete(socket, :answers, %{id: answer_id})}
  end

  def handle_info({:riddle_completed, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      # Re-insert correct answers with show_highlight: true so the stream items
      # update in the DOM (stream items don't re-render on outer assign changes).
      socket =
        socket.assigns.correct_answers
        |> Enum.reduce(socket, fn {_id, answer}, acc ->
          stream_insert(acc, :answers, %{answer | show_highlight: true})
        end)

      top_solvers = load_top_solvers(riddle.id)

      {:noreply,
       socket
       |> assign(:riddle, riddle)
       |> assign(:game_completed, true)
       |> assign(:time_remaining, 0)
       |> assign(:top_solvers, top_solvers)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:riddle_archived, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      {
        :noreply,
        socket
        |> put_flash(:info, "This game has been archived.")
        #  |> push_navigate(to: ~p"/")
      }
    else
      {:noreply, socket}
    end
  end

  def handle_info(:tick, socket) do
    if socket.assigns.game_completed do
      {:noreply, socket}
    else
      time_remaining =
        compute_time_remaining(socket.assigns.game_start_time, socket.assigns.riddle.solve_time)

      if time_remaining > 0 do
        Process.send_after(self(), :tick, 1000)
      end

      {:noreply,
       socket
       |> assign(:time_remaining, time_remaining)
       |> push_event("countdown-tick", %{seconds: time_remaining})}
    end
  end

  def handle_info({:user_status_changed, :banned}, socket) do
    {:noreply,
     socket
     |> assign(:banned, true)
     |> put_flash(:error, "Your account has been suspended.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info({:user_status_changed, _status}, socket) do
    {:noreply, assign(socket, :banned, false)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="min-h-screen px-4 py-10"
      style="background: var(--bg); color: var(--text)"
    >
      <div class="max-w-lg mx-auto">
        <%!-- Header: badges + riddle name --%>
        <div class="text-center mb-6">
          <div class="flex items-center justify-center gap-2 mb-3">
            <span
              :if={@riddle.category}
              class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium"
              style="background: rgba(255,255,255,0.06); color: var(--text-muted)"
            >
              <span style="width:6px;height:6px;border-radius:50%;background:var(--accent);display:inline-block">
              </span>
              {@riddle.category.name}
            </span>
            <span
              :if={@riddle.difficulty}
              class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium"
              style="background: rgba(255,255,255,0.06); color: var(--text-muted)"
            >
              <span style="width:6px;height:6px;border-radius:50%;background:#d97706;display:inline-block">
              </span>
              {@riddle.difficulty}
            </span>
            <span
              :if={@game_completed}
              class="inline-flex items-center rounded-full px-3 py-1 text-xs font-medium"
              style="background: rgba(255,255,255,0.06); color: var(--text-muted)"
            >
              Game Over
            </span>
          </div>
          <h1 id="riddle-name" class="text-2xl font-bold" style="color: var(--text)">
            {@riddle.name}
          </h1>

          <%!-- Solve timer --%>
          <div :if={not @game_completed} class="mt-4 flex justify-center">
            <div
              id="solve-timer-card"
              style="view-transition-name: game-timer; background: var(--surface); border: 1px solid var(--surface-border)"
              class="rounded-xl px-6 py-3 text-center"
            >
              <p
                class="text-[10px] font-semibold uppercase tracking-widest mb-1"
                style="color: var(--text-muted)"
              >
                Solve time
              </p>
              <div
                id="countdown-timer"
                phx-hook=".SolveTimer"
                data-seconds={@time_remaining}
                class="leading-none"
              >
                <span
                  data-timer-display
                  class="text-2xl font-mono font-bold tabular-nums"
                  style="color: var(--text)"
                >
                  {format_time(@time_remaining)}
                </span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Riddle description (word-by-word reveal via JS hook) --%>
        <div
          id="riddle-description"
          class="rounded-2xl p-6 mb-6 text-center"
          style="background: var(--surface); border: 1px solid var(--surface-border)"
          phx-hook=".RiddleReveal"
          data-text={@riddle.description}
        >
          <p class="text-base leading-relaxed" style="color: var(--text)">
            {@riddle.description}
          </p>
        </div>

        <%!-- Correct answer result --%>
        <div
          :if={match?({:correct, _, _}, @submission_state)}
          id="correct-result"
          class="rounded-2xl p-6 mb-6 text-center"
          style="background: rgba(34,197,94,0.08); border: 1px solid rgba(34,197,94,0.25)"
        >
          <p class="text-xl font-bold mb-1" style="color: #4ade80">Correct!</p>
          <p style="color: #86efac">
            {placement_text(elem(@submission_state, 1))} place &mdash; +{elem(@submission_state, 2)} points
          </p>
        </div>

        <%!-- Answer form --%>
        <div
          :if={not @already_solved and not @game_completed}
          id="answer-form-container"
          phx-hook=".AnswerForm"
          class="mb-6"
        >
          <form id="answer-form" phx-submit="submit_answer" class="flex flex-col gap-3">
            <input
              id="answer-input"
              type="text"
              name="answer"
              placeholder="Your answer…"
              autocomplete="off"
              class="w-full rounded-xl px-4 py-3 text-base focus-ring"
              style="background: var(--surface); border: 1px solid var(--surface-border); color: var(--text); outline: none"
            />
            <button
              id="submit-btn"
              type="submit"
              class="w-full rounded-xl py-3 text-sm font-semibold pressable focus-ring"
              style="background: var(--accent); color: #fff; min-height: 52px; border: none"
            >
              Submit
            </button>
          </form>

          <div :if={@submission_state == :incorrect} id="incorrect-feedback" class="mt-3">
            <p class="text-sm" style="color: var(--text-muted)">{@try_again_message}</p>
          </div>
          <div :if={match?({:error, _}, @submission_state)} id="error-feedback" class="mt-3">
            <p class="text-sm" style="color: #a78bfa">{elem(@submission_state, 1)}</p>
          </div>
        </div>

        <%!-- Game over (didn't solve) --%>
        <div
          :if={@game_completed and not @already_solved}
          id="game-over"
          class="rounded-2xl p-8 text-center mb-6"
          style="background: var(--surface); border: 1px solid var(--surface-border)"
        >
          <p class="text-lg font-semibold" style="color: var(--text)">Time's up!</p>
          <p class="mt-1" style="color: var(--text-muted)">Better luck next time.</p>
        </div>

        <%!-- Post-game chat --%>
        <div :if={@game_completed} id="chat-form-container" class="mb-6">
          <form id="chat-form" phx-submit="send_chat" class="flex flex-col gap-3">
            <input
              id="chat-input"
              type="text"
              name="message"
              placeholder="Chat with other players…"
              autocomplete="off"
              class="w-full rounded-xl px-4 py-3 text-base focus-ring"
              style="background: var(--surface); border: 1px solid var(--surface-border); color: var(--text); outline: none"
            />
            <button
              type="submit"
              class="w-full rounded-xl py-3 text-sm font-semibold pressable focus-ring"
              style="background: #4338ca; color: #fff; min-height: 52px; border: none"
            >
              Send
            </button>
          </form>
        </div>

        <%!-- Post-game results --%>
        <div :if={@game_completed} id="post-game-results" class="space-y-4">
          <%!-- Winner --%>
          <div
            :if={@riddle.first_solver}
            id="winner-announcement"
            class="rounded-2xl p-6 text-center"
            style="background: rgba(217,119,6,0.08); border: 1px solid rgba(217,119,6,0.25)"
          >
            <p class="text-xs font-semibold uppercase tracking-wide mb-1" style="color: #d97706">
              Winner
            </p>
            <p class="text-xl font-bold" style="color: #fcd34d">{@riddle.first_solver.username}</p>
            <p :if={@riddle.first_solve_time} class="text-sm mt-1" style="color: #fbbf24">
              Solved in {format_time(@riddle.first_solve_time)}
            </p>
          </div>

          <%!-- The answer(s) revealed --%>
          <div
            id="correct-answers-revealed"
            class="rounded-2xl p-6"
            style="background: var(--surface); border: 1px solid var(--surface-border)"
          >
            <h3
              class="text-xs font-semibold uppercase tracking-wide mb-3"
              style="color: var(--text-muted)"
            >
              The Answer{if length(@riddle.answers) > 1, do: "s", else: ""}
            </h3>
            <ul class="space-y-1">
              <li :for={answer <- @riddle.answers} class="font-medium" style="color: var(--text)">
                {answer}
              </li>
            </ul>
          </div>

          <%!-- Top solvers leaderboard --%>
          <div
            :if={@top_solvers != []}
            id="game-leaderboard"
            class="rounded-2xl p-6"
            style="background: var(--surface); border: 1px solid var(--surface-border)"
          >
            <h3
              class="text-xs font-semibold uppercase tracking-wide mb-3"
              style="color: var(--text-muted)"
            >
              Top Solvers
            </h3>
            <ol class="space-y-2">
              <li
                :for={solver <- @top_solvers}
                class="flex items-center justify-between py-1"
              >
                <div class="flex items-center gap-3">
                  <span class={[
                    "w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold",
                    solver.placement == 1 && "bg-amber-500/20 text-amber-400",
                    solver.placement == 2 && "bg-zinc-700 text-zinc-400",
                    solver.placement == 3 && "bg-orange-500/20 text-orange-400",
                    solver.placement > 3 && "bg-zinc-800 text-zinc-500"
                  ]}>
                    {solver.placement}
                  </span>
                  <span class="font-medium" style="color: var(--text)">{solver.username}</span>
                </div>
                <span class="text-sm" style="color: var(--text-muted)">
                  {solver.solve_time_display || "—"}
                </span>
              </li>
            </ol>
          </div>
        </div>

        <%!-- Answer feed --%>
        <div id="answer-feed" class="mt-8">
          <h2
            class="text-xs font-semibold uppercase tracking-wide mb-3"
            style="color: var(--text-muted)"
          >
            Answer Feed
          </h2>
          <div id="answers" phx-update="stream" class="space-y-0">
            <div
              :for={{dom_id, answer} <- @streams.answers}
              id={dom_id}
              class="feed-entry flex items-center gap-3 px-3 py-2.5 text-sm"
              style={[
                "border-bottom: 1px solid rgba(255,255,255,0.03);",
                cond do
                  answer.show_highlight ->
                    "border-left: 3px solid var(--accent); padding-left: 10px"

                  Map.get(answer, :chat, false) ->
                    "border-left: 3px solid #4338ca; padding-left: 10px"

                  true ->
                    ""
                end
              ]}
            >
              <span class="font-medium shrink-0" style="color: var(--text)">{answer.username}</span>
              <span class="flex-1 truncate" style="color: var(--text-muted)">{answer.text}</span>
              <span :if={answer.offset_ms} class="text-xs shrink-0" style="color: #52525b">
                +{format_offset(answer.offset_ms)}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SolveTimer">
      export default {
        mounted() {
          this.displayEl = this.el.querySelector("[data-timer-display]")
          this.render(parseInt(this.el.dataset.seconds, 10) || 0)
          this.handleEvent("countdown-tick", ({ seconds }) => {
            this.render(seconds)
          })
        },
        render(secs) {
          const m = Math.floor(secs / 60).toString().padStart(2, "0")
          const s = (secs % 60).toString().padStart(2, "0")
          if (this.displayEl) this.displayEl.textContent = `${m}:${s}`

          const urgency = secs <= 10 ? "critical" : secs <= 30 ? "warning" : "normal"
          const card = this.el.closest("[id='solve-timer-card']") || this.el
          if (card.dataset.urgency !== urgency) {
            card.dataset.urgency = urgency
          }

          if (this.displayEl) {
            if (secs > 30 || secs <= 10) {
              this.displayEl.style.color = ""
            } else {
              const t = (30 - secs) / 20
              const r = Math.round(55 + t * (234 - 55))
              const g = Math.round(65 + t * (88 - 65))
              const b = Math.round(81 + t * (12 - 81))
              this.displayEl.style.color = `rgb(${r},${g},${b})`
            }
          }
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".RiddleReveal">
      export default {
        mounted() {
          const para = this.el.querySelector("p")
          if (!para) return

          const escape = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
          const words = para.textContent.trim().split(/\s+/)
          para.innerHTML = words
            .map(w => `<span class="riddle-word">${escape(w)} </span>`)
            .join("")

          setTimeout(() => {
            const spans = para.querySelectorAll(".riddle-word")
            spans.forEach((span, i) => {
              setTimeout(() => span.classList.add("revealed"), i * 60)
            })
          }, 300)
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".AnswerForm">
      export default {
        mounted() {
          this.handleEvent("answer-shake", () => {
            const input = this.el.querySelector("#answer-input")
            if (!input) return
            input.classList.remove("shake")
            void input.offsetWidth
            input.classList.add("shake")
            input.addEventListener("animationend", () => input.classList.remove("shake"), { once: true })
          })

          this.handleEvent("answer-correct", () => {
            this.el.style.transition = "opacity 400ms ease"
            this.el.style.opacity = "0"
            setTimeout(() => { this.el.style.display = "none" }, 400)
          })
        }
      }
    </script>
    """
  end

  defp check_not_banned(%{banned: true}), do: {:error, :banned}
  defp check_not_banned(_assigns), do: :ok

  defp check_game_live(%{play_status: "live"}), do: :ok
  defp check_game_live(%{play_status: status}), do: {:error, {:not_live, status}}

  defp check_game_completed(%{play_status: "completed"}), do: :ok
  defp check_game_completed(%{play_status: status}), do: {:error, {:not_completed, status}}

  defp validate_input(text) do
    cond do
      text == "" -> {:error, :empty_answer}
      String.length(text) > @answer_max_length -> {:error, :answer_too_long}
      true -> :ok
    end
  end

  defp format_error(:cooldown), do: "Please wait a moment before submitting again."
  defp format_error(:already_solved), do: "You've already solved this riddle!"
  defp format_error(:empty_answer), do: "Answer cannot be empty."

  defp format_error(:answer_too_long),
    do: "Answer is too long (max #{@answer_max_length} characters)."

  defp format_error({:not_live, _}), do: "The game is not currently active."
  defp format_error(_), do: "Something went wrong. Please try again."

  defp placement_text(1), do: "1st"
  defp placement_text(2), do: "2nd"
  defp placement_text(3), do: "3rd"
  defp placement_text(n), do: "#{n}th"

  defp try_again() do
    Enum.random(@try_again_messages)
  end

  # Builds feed items for answers already in ETS when the LiveView mounts.
  # Batch-loads usernames from the DB to avoid N+1 queries.
  # When game_completed is true, correct answers are immediately highlighted.
  defp build_initial_feed(riddle_id, game_completed) do
    ets_answers = Gameplay.get_answers(riddle_id)

    user_ids = ets_answers |> Enum.map(& &1.user_id) |> Enum.uniq()
    users_by_id = Accounts.get_users_by_ids(user_ids)

    ets_answers
    |> Enum.take(100)
    |> Enum.map(fn a ->
      username =
        case Map.get(users_by_id, a.user_id) do
          %{username: u} -> u
          nil -> "Player"
        end

      %{
        id: "#{riddle_id}-#{a.user_id}-#{a.timestamp}",
        user_id: a.user_id,
        username: username,
        text: a.text,
        correct: a.correct,
        offset_ms: nil,
        show_highlight: game_completed and a.correct,
        flagged: false,
        chat: false
      }
    end)
  end

  # Loads top solvers from ETS and batch-fetches their usernames from the DB.
  defp load_top_solvers(riddle_id) do
    solver_entries = Gameplay.get_top_solvers(riddle_id)
    user_ids = Enum.map(solver_entries, & &1.user_id)
    users_by_id = Accounts.get_users_by_ids(user_ids)

    Enum.map(solver_entries, fn entry ->
      username =
        case Map.get(users_by_id, entry.user_id) do
          %{username: u} -> u
          nil -> "Player"
        end

      solve_time_display =
        case entry.solve_time_ms do
          nil -> nil
          ms -> format_time(div(ms, 1000))
        end

      entry |> Map.put(:username, username) |> Map.put(:solve_time_display, solve_time_display)
    end)
  end

  defp compute_time_remaining(nil, solve_time), do: solve_time

  defp compute_time_remaining(live_date, solve_time) do
    elapsed = DateTime.diff(DateTime.utc_now(), live_date, :second)
    max(solve_time - elapsed, 0)
  end

  defp format_time(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> IO.iodata_to_binary()
  end

  defp compute_offset_ms(nil), do: nil

  defp compute_offset_ms(game_start) do
    max(DateTime.diff(DateTime.utc_now(), game_start, :millisecond), 0)
  end

  defp format_offset(ms) when ms < 1000, do: "#{ms}ms"
  defp format_offset(ms), do: "#{div(ms, 1000)}s"
end
