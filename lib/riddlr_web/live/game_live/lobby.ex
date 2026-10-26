defmodule RiddlrWeb.GameLive.Lobby do
  use RiddlrWeb, :live_view

  alias Riddlr.GameClock
  alias Riddlr.Games
  alias Riddlr.Gameplay.Presence
  alias RiddlrWeb.GameComponents
  alias RiddlrWeb.GameCopy

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
             |> put_flash(:info, GameCopy.lobby_unavailable())
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

            time_until_game_starts = lobby_seconds_left(riddle)

            {:ok,
             socket
             |> assign(:page_title, "Lobby — #{riddle.name}")
             |> assign(:riddle, riddle)
             # The narrowest grid, until the .RoomGrid hook measures it.
             |> assign(:room_cols, GameComponents.clamp_cols(0))
             |> assign(:last_join, nil)
             |> assign(:players, [])
             |> refresh_players()
             |> assign(:time_remaining, time_until_game_starts)}
        end

      {:error, :not_found} ->
        {:ok, socket |> push_navigate(to: ~p"/")}
    end
  end

  # The .RoomGrid hook reports how many columns the room grid has at the
  # browser's width. The count is clamped, so the grid stays bounded whatever
  # the client sends.
  @impl true
  def handle_event("room-cols", %{"cols" => cols}, socket) when is_integer(cols) do
    {:noreply,
     socket
     |> assign(:room_cols, GameComponents.clamp_cols(cols))
     |> assign_room()}
  end

  def handle_event("room-cols", _params, socket), do: {:noreply, socket}

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

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    {:noreply,
     socket
     |> assign_last_join(diff.joins)
     |> refresh_players()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @spec lobby_topic(integer() | String.t()) :: String.t()
  defp lobby_topic(id), do: "game:lobby:#{id}"

  # The ticker shows the players in the latest diff's joins. The viewer and
  # players already in the room (a second tab) are not news. A diff with no
  # new joins keeps the last one on show.
  @spec assign_last_join(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp assign_last_join(socket, joins) do
    %{players: players, last_join: last_join} = socket.assigns
    known = player_ids(players)

    names =
      for {id, username} <- Enum.sort(usernames(joins)),
          not MapSet.member?(known, id),
          do: username

    case names do
      [] ->
        socket

      [first | rest] ->
        seq = if last_join, do: last_join.seq + 1, else: 1
        assign(socket, :last_join, %{first: first, others: length(rest), seq: seq})
    end
  end

  # Re-reads who is in the room. The viewer comes first, then players in the
  # order they joined: players already shown keep their place, players who
  # left drop out, new players go on the end. Before the socket connects the
  # viewer is not yet tracked, so they are added here.
  #
  # `players` is a plain list, not a stream: the grid needs the full order to
  # pick which players get tiles and to count the rest. Only `room_cells/2`'s
  # bounded slice reaches the DOM.
  @spec refresh_players(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp refresh_players(socket) do
    %{riddle: riddle, current_user: user, players: players} = socket.assigns
    me = %{id: to_string(user.id), username: user.username, me?: true}

    present =
      riddle.id
      |> lobby_topic()
      |> Presence.list()
      |> usernames()
      |> Map.put(me.id, me.username)

    staying =
      Enum.filter(players, fn player ->
        not player.me? and Map.has_key?(present, player.id)
      end)

    shown = player_ids(staying)

    joined =
      for {id, username} <- Enum.sort(present),
          id != me.id,
          not MapSet.member?(shown, id),
          do: %{id: id, username: username, me?: false}

    socket
    |> assign(:players, [me | staying ++ joined])
    |> assign_room()
  end

  @spec assign_room(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_room(socket) do
    %{players: players, room_cols: cols} = socket.assigns
    assign(socket, :room, GameComponents.room_cells(players, cols))
  end

  # Presence entries (from a list or a diff) as player id => username.
  @spec usernames(map()) :: %{String.t() => String.t()}
  defp usernames(presences) do
    Map.new(presences, fn {id, %{metas: [meta | _]}} -> {id, meta.username} end)
  end

  @spec player_ids([GameComponents.room_player()]) :: MapSet.t(String.t())
  defp player_ids(players), do: MapSet.new(players, & &1.id)

  # The seconds shown on the first render. Every render after it comes from a
  # tick on the same clock.
  @spec lobby_seconds_left(Riddlr.Games.Riddle.t()) :: non_neg_integer()
  defp lobby_seconds_left(riddle) do
    case GameClock.countdown(riddle) do
      {:lobby, seconds} -> seconds
      {:play, _} -> 0
    end
  end
end
