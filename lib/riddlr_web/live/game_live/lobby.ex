defmodule RiddlrWeb.GameLive.Lobby do
  use RiddlrWeb, :live_view

  alias Riddlr.Clock
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
              Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:live")
              Riddlr.LobbyTimer.ensure_started(id, riddle.live_date)
            end

            player_count = lobby_topic(id) |> Presence.list() |> map_size()
            time_until_game_starts = time_remaining(riddle.live_date)

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
  def handle_info({:countdown_tick, seconds}, socket) do
    {:noreply,
     socket
     |> assign(:time_remaining, seconds)
     |> push_event("countdown-tick", %{seconds: seconds})}
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

  defp lobby_topic(id), do: "game:lobby:#{id}"

  defp time_remaining(nil), do: 0

  defp time_remaining(live_date),
    do: max(0, DateTime.diff(live_date, Clock.utc_now()))
end
