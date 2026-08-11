defmodule RiddlrWeb.GameLive.Lobby do
  use RiddlrWeb, :live_view

  alias Riddlr.GameClock
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
            if connected?(socket) do
              Presence.track(
                self(),
                lobby_topic(id),
                to_string(socket.assigns.current_user.id),
                %{username: socket.assigns.current_user.username}
              )

              Phoenix.PubSub.subscribe(Riddlr.PubSub, lobby_topic(id))
              Phoenix.PubSub.subscribe(Riddlr.PubSub, GameClock.topic(riddle.id))
              Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:live")
              GameClock.ensure_started(riddle)
            end

            player_count = lobby_topic(id) |> Presence.list() |> map_size()
            time_until_game_starts = lobby_seconds_left(riddle)

            {:ok,
             socket
             |> assign(:page_title, "Lobby — #{riddle.name}")
             |> assign(:riddle, riddle)
             |> assign(:player_count, player_count)
             |> assign(:time_remaining, time_until_game_starts)}
        end

      {:error, :not_found} ->
        {:ok, socket |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:countdown_tick, :lobby, seconds}, socket) do
    {:noreply,
     socket
     |> assign(:time_remaining, seconds)
     |> push_event("countdown-tick", %{seconds: seconds})}
  end

  # The clock rolls straight from the lobby phase into the play phase. The lobby
  # leaves on the :riddle_live broadcast, not on a tick, so play ticks are
  # ignored here.
  def handle_info({:countdown_tick, _phase, _seconds}, socket), do: {:noreply, socket}

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

  defp lobby_topic(id), do: "game:lobby:#{id}"

  # The seconds shown on the first render. Every render after it comes from a
  # tick on the same clock.
  defp lobby_seconds_left(riddle) do
    case GameClock.countdown(riddle) do
      {:lobby, seconds} -> seconds
      {:play, _} -> 0
    end
  end
end
