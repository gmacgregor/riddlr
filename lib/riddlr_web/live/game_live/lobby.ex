defmodule RiddlrWeb.GameLive.Lobby do
  use RiddlrWeb, :live_view

  alias Riddlr.Games
  alias Riddlr.Gameplay.Presence

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    riddle = Games.get_riddle!(id)

    cond do
      riddle.play_status == "live" ->
        {:ok, push_navigate(socket, to: ~p"/game/#{id}/play")}

      riddle.play_status != "ready" ->
        {:ok,
         socket
         |> put_flash(:error, "Game lobby is not available.")
         |> push_navigate(to: ~p"/")}

      true ->
        timer_ref =
          if connected?(socket) do
            Presence.track(self(), lobby_topic(id), to_string(socket.assigns.current_user.id), %{
              username: socket.assigns.current_user.username
            })

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
    <div class="max-w-2xl mx-auto px-4 py-12">
      <div class="text-center mb-10">
        <div class="flex items-center justify-center gap-3 mb-2">
          <span
            :if={@riddle.category}
            class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-700/10"
          >
            {@riddle.category.name}
          </span>
          <span
            :if={@riddle.difficulty}
            class="inline-flex items-center rounded-md bg-yellow-50 px-2 py-1 text-xs font-medium text-yellow-800 ring-1 ring-inset ring-yellow-600/20"
          >
            {@riddle.difficulty}
          </span>
        </div>
        <h1 id="riddle-name" class="text-3xl font-bold text-gray-900">{@riddle.name}</h1>
      </div>

      <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-8 text-center mb-6">
        <p class="text-sm text-gray-500 mb-2">Game starts in</p>
        <div
          id="countdown"
          phx-hook=".Countdown"
          data-seconds={@time_remaining}
          class="text-6xl font-mono font-bold text-gray-900 tabular-nums"
        >
          {format_time(@time_remaining)}
        </div>
      </div>

      <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 text-center">
        <p class="text-sm text-gray-500 mb-1">Players in lobby</p>
        <p id="player-count" class="text-3xl font-bold text-gray-900">{@player_count}</p>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Countdown">
      export default {
        mounted() {
          this.seconds = parseInt(this.el.dataset.seconds, 10)
          this.tick()
          this.interval = setInterval(() => this.tick(), 100)
          this.handleEvent("countdown-tick", ({ seconds }) => {
            this.seconds = seconds
          })
        },
        updated() {
          // Server update — reset to server-authoritative value
          this.seconds = parseInt(this.el.dataset.seconds, 10)
        },
        destroyed() {
          clearInterval(this.interval)
        },
        tick() {
          if (this.seconds > 0) {
            this.seconds = Math.max(0, this.seconds - 0.1)
          }
          const secs = Math.ceil(this.seconds)
          const m = Math.floor(secs / 60).toString().padStart(2, "0")
          const s = (secs % 60).toString().padStart(2, "0")
          this.el.textContent = `${m}:${s}`
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
