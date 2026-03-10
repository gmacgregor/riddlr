defmodule RiddlrWeb.GameLive.Lobby do
  use RiddlrWeb, :live_view

  alias Riddlr.Games
  alias Riddlr.Gameplay.Presence

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Games.fetch_riddle(id) do
      {:ok, riddle} ->
        cond do
          riddle.play_status == "live" ->
            {:ok, push_navigate(socket, to: ~p"/game/#{id}/play")}

          riddle.play_status != "ready" ->
            {:ok,
             socket
             |> put_flash(:info, "Game lobby is not yet available.")
             |> push_navigate(to: ~p"/")}

          true ->
            timer_ref =
              if connected?(socket) do
                Presence.track(
                  self(),
                  lobby_topic(id),
                  to_string(socket.assigns.current_user.id),
                  %{
                    username: socket.assigns.current_user.username
                  }
                )

                Phoenix.PubSub.subscribe(Riddlr.PubSub, lobby_topic(id))
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:live")
                {:ok, ref} = :timer.send_interval(1000, self(), :tick)
                ref
              end

            player_count = lobby_topic(id) |> Presence.list() |> map_size()
            time_remaining = time_remaining(riddle.live_date)

            {:ok,
             socket
             |> assign(:page_title, "Lobby — #{riddle.name}")
             |> assign(:riddle, riddle)
             |> assign(:player_count, player_count)
             |> assign(:time_remaining, time_remaining)
             |> assign(:timer_ref, timer_ref)}
        end

      {:error, :not_found} ->
        {:ok, socket |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    riddle = socket.assigns.riddle
    time_remaining = time_remaining(riddle.live_date)

    socket =
      socket
      |> assign(:time_remaining, time_remaining)
      |> push_event("countdown-tick", %{seconds: time_remaining})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:riddle_live, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      {:noreply, push_navigate(socket, to: ~p"/game/#{riddle.id}/play")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    player_count = lobby_topic(socket.assigns.riddle.id) |> Presence.list() |> map_size()
    {:noreply, assign(socket, :player_count, player_count)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col items-center justify-center px-4 py-12"
         style="background: var(--bg); color: var(--text)">
      <%!-- Riddle identity --%>
      <div class="text-center mb-8 w-full max-w-sm">
        <div class="flex items-center justify-center gap-2 mb-3">
          <span
            :if={@riddle.category}
            class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium"
            style="background: rgba(255,255,255,0.06); color: var(--text-muted)"
          >
            <span style="width:6px;height:6px;border-radius:50%;background:var(--accent);display:inline-block"></span>
            {@riddle.category.name}
          </span>
          <span
            :if={@riddle.difficulty}
            class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium"
            style="background: rgba(255,255,255,0.06); color: var(--text-muted)"
          >
            <span style="width:6px;height:6px;border-radius:50%;background:#d97706;display:inline-block"></span>
            {@riddle.difficulty}
          </span>
        </div>
        <h1 id="riddle-name" class="text-2xl font-bold" style="color: var(--text)">
          {@riddle.name}
        </h1>
      </div>

      <%!-- Timer card --%>
      <div
        id="lobby-timer-card"
        style="view-transition-name: game-timer; background: var(--surface); border: 1px solid var(--surface-border)"
        class="w-full max-w-sm rounded-2xl p-8 text-center mb-6"
      >
        <p class="text-xs font-semibold uppercase tracking-widest mb-4" style="color: var(--text-muted)">
          Starts in
        </p>
        <div
          id="countdown"
          phx-hook=".Countdown"
          data-seconds={@time_remaining}
          class="text-5xl font-mono font-bold tabular-nums"
          style="color: var(--text)"
        >
          {format_time(@time_remaining)}
        </div>
      </div>

      <%!-- Player presence --%>
      <div
        class="w-full max-w-sm rounded-2xl p-6 text-center mb-6"
        style="background: var(--surface); border: 1px solid var(--surface-border)"
      >
        <div id="player-dots" class="flex items-center justify-center gap-2 flex-wrap mb-3">
          <span
            :for={_i <- if(@player_count > 0, do: 1..min(@player_count, 12)//1, else: [])}
            class="player-dot"
            style={"animation-delay: #{:rand.uniform(20) * 100}ms"}
          />
          <span
            :if={@player_count > 12}
            class="text-xs"
            style="color: var(--text-muted)"
          >
            +{@player_count - 12} more
          </span>
        </div>
        <p class="text-sm" style="color: var(--text-muted)">
          {if @player_count == 1, do: "1 player waiting", else: "#{@player_count} players waiting"}
        </p>
      </div>

      <%!-- Anticipation hint --%>
      <p class="text-sm italic text-center" style="color: #52525b">
        Get ready. The riddle appears when the clock hits zero.
      </p>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Countdown">
      export default {
        mounted() {
          this.tick()
          this.interval = setInterval(() => this.tick(), 1000)
          this.handleEvent("countdown-tick", ({ seconds }) => {
            this.el.dataset.seconds = seconds
            this.tick()
          })
        },
        destroyed() {
          clearInterval(this.interval)
        },
        tick() {
          const secs = parseInt(this.el.dataset.seconds, 10) || 0
          const m = Math.floor(secs / 60).toString().padStart(2, "0")
          const s = (secs % 60).toString().padStart(2, "0")
          this.el.textContent = `${m}:${s}`

          // Color: violet > 60s, white < 60s, red < 10s
          if (secs <= 10) {
            this.el.style.color = "rgb(220,38,38)"
          } else if (secs <= 60) {
            this.el.style.color = "var(--text)"
          } else {
            this.el.style.color = "var(--accent)"
          }

          // Tick pulse: briefly add class, then remove
          this.el.classList.remove("countdown-tick")
          void this.el.offsetWidth // force reflow to restart animation
          this.el.classList.add("countdown-tick")

          // Timer card border glow when urgent
          const card = document.getElementById("lobby-timer-card")
          if (card) {
            if (secs <= 10) {
              card.classList.add("timer-card-urgent")
            } else {
              card.classList.remove("timer-card-urgent")
            }
          }
        }
      }
    </script>
    """
  end

  @impl true
  def terminate(_reason, socket) do
    if ref = socket.assigns[:timer_ref], do: :timer.cancel(ref)
    :ok
  end

  defp lobby_topic(id), do: "game:lobby:#{id}"

  defp time_remaining(nil), do: 0

  defp time_remaining(live_date),
    do: max(0, DateTime.diff(live_date, DateTime.utc_now()))

  defp format_time(seconds) do
    m = div(seconds, 60) |> Integer.to_string() |> String.pad_leading(2, "0")
    s = rem(seconds, 60) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{m}:#{s}"
  end
end
