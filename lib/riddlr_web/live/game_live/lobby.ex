defmodule RiddlrWeb.GameLive.Lobby do
  use RiddlrWeb, :live_view

  alias Riddlr.GameClock
  alias Riddlr.Games
  alias Riddlr.Gameplay.Presence
  alias RiddlrWeb.GameComponents
  alias RiddlrWeb.GameCopy
  alias RiddlrWeb.GameLive.Stagger

  @typep refs :: %{String.t() => MapSet.t(String.t())}

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
              track_player(socket.assigns.current_scope, id)
              Phoenix.PubSub.subscribe(Riddlr.PubSub, Presence.lobby_topic(id))
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
             |> assign(:pending, [])
             |> assign(:flush_ref, nil)
             |> load_players()
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
      {:noreply, Stagger.navigate(socket, ~p"/game/#{riddle.id}/play")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:stagger_navigate, path}, socket) do
    {:noreply, push_navigate(socket, to: path)}
  end

  # A full Lobby sends a diff for every join and leave, to every player in it.
  # Diffs wait here and the room is redrawn at most once per flush.
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    socket = update(socket, :pending, &[diff | &1])

    case socket.assigns.flush_ref do
      nil -> {:noreply, assign(socket, :flush_ref, schedule_flush())}
      _ref -> {:noreply, socket}
    end
  end

  def handle_info(:flush_room, socket) do
    %{pending: pending, players: players, refs: refs} = socket.assigns
    diffs = Enum.reverse(pending)
    refs = Enum.reduce(diffs, refs, &apply_diff/2)
    known = player_ids(players)

    joined =
      for {id, username} <- Enum.sort(joined_usernames(diffs)),
          Map.has_key?(refs, id),
          not MapSet.member?(known, id),
          do: %{id: id, username: username, me?: false}

    staying = Enum.filter(players, &(&1.me? or Map.has_key?(refs, &1.id)))

    {:noreply,
     socket
     |> assign(pending: [], flush_ref: nil, refs: refs, players: staying ++ joined)
     |> assign_last_join(joined)
     |> assign_room()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @spec schedule_flush() :: reference()
  defp schedule_flush do
    ms = :riddlr |> Application.get_env(__MODULE__, []) |> Keyword.get(:room_flush_ms, 300)
    Process.send_after(self(), :flush_room, ms)
  end

  # A player is in the room while they hold at least one presence (one per
  # tab). Keeping each presence's phx_ref, not a count, means a diff that the
  # mount's Presence.list already held changes nothing when it lands.
  @spec apply_diff(map(), refs()) :: refs()
  defp apply_diff(%{joins: joins, leaves: leaves}, refs) do
    refs =
      Enum.reduce(leaves, refs, fn {id, %{metas: metas}}, refs ->
        left = MapSet.difference(Map.get(refs, id, MapSet.new()), phx_refs(metas))
        if MapSet.size(left) == 0, do: Map.delete(refs, id), else: Map.put(refs, id, left)
      end)

    Enum.reduce(joins, refs, fn {id, %{metas: metas}}, refs ->
      Map.update(refs, id, phx_refs(metas), &MapSet.union(&1, phx_refs(metas)))
    end)
  end

  @spec phx_refs([map()]) :: MapSet.t(String.t())
  defp phx_refs(metas), do: MapSet.new(metas, & &1.phx_ref)

  @spec joined_usernames([map()]) :: %{String.t() => String.t()}
  defp joined_usernames(diffs) do
    Enum.reduce(diffs, %{}, &Map.merge(&2, usernames(&1.joins)))
  end

  # The ticker shows the players who joined since the last flush. The viewer
  # and players already in the room (a second tab) are not news. A flush with
  # no new joins keeps the last one on show.
  @spec assign_last_join(Phoenix.LiveView.Socket.t(), [GameComponents.room_player()]) ::
          Phoenix.LiveView.Socket.t()
  defp assign_last_join(socket, joined) do
    last_join = socket.assigns.last_join

    case Enum.map(joined, & &1.username) do
      [] ->
        socket

      [first | rest] ->
        seq = if last_join, do: last_join.seq + 1, else: 1
        assign(socket, :last_join, %{first: first, others: length(rest), seq: seq})
    end
  end

  # Puts a signed-in viewer in the room. A guest watches without being tracked,
  # so they never show in the room or its count.
  @spec track_player(Riddlr.Accounts.Scope.t() | nil, String.t()) :: :ok
  defp track_player(nil, _riddle_id), do: :ok

  defp track_player(%{user: user}, riddle_id) do
    {:ok, _ref} =
      Presence.track(self(), Presence.lobby_topic(riddle_id), to_string(user.id), %{
        username: user.username
      })

    :ok
  end

  # Reads who is in the room, once, at mount. After that the room changes
  # only by diffs (see :flush_room). A signed-in viewer comes first, then the
  # other players; later joins go on the end, and players already shown keep
  # their place. Before the socket connects the viewer is not yet tracked, so
  # they are added here. A guest is not added.
  #
  # `players` is a plain list, not a stream: the grid needs the full order to
  # pick which players get tiles and to count the rest. Only `room_cells/2`'s
  # bounded slice reaches the DOM.
  @spec load_players(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_players(socket) do
    %{riddle: riddle, current_scope: scope} = socket.assigns
    me = viewer(scope)
    present = riddle.id |> Presence.lobby_topic() |> Presence.list()

    others =
      for {id, username} <- Enum.sort(usernames(present)),
          is_nil(me) or id != me.id,
          do: %{id: id, username: username, me?: false}

    socket
    |> assign(:refs, Map.new(present, fn {id, %{metas: metas}} -> {id, phx_refs(metas)} end))
    |> assign(:players, List.wrap(me) ++ others)
    |> assign_room()
  end

  # The viewer's own room entry, or nil for a guest, who has none.
  @spec viewer(Riddlr.Accounts.Scope.t() | nil) :: GameComponents.room_player() | nil
  defp viewer(nil), do: nil
  defp viewer(%{user: user}), do: %{id: to_string(user.id), username: user.username, me?: true}

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
