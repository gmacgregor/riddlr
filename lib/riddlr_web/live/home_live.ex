defmodule RiddlrWeb.HomeLive do
  @moduledoc """
  The public Home page: what Riddlr is, and a card for the next riddle
  (`Games.next_riddle/0`).

  The card has three modes. With no next riddle it says so. Before the drop
  it counts down and shows how many players wait in the Lobby; only a `ready`
  riddle gets a button, since a `scheduled` riddle's Lobby is not open yet.
  Once live it shows the time left and how many have solved it.

  Below the card, "Coming up" lists the riddles after the next one
  (`Games.list_upcoming_riddles/1`), with no riddle text, and "Last riddle"
  shows the most recent finished riddle with its answer and first solver
  (`Games.last_finished_riddle/0`).

  The page follows the riddle's state while open. It listens to the riddle
  state topics, and to the next riddle's clock, Lobby presence and answers.
  When the next riddle changes, the per-riddle topics move with it. Any state
  message reloads the card and both panels.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{GameClock, Gameplay, Games}
  alias Riddlr.Gameplay.{Answer, Presence}
  alias RiddlrWeb.{GameComponents, GameCopy}

  # Each of these can change which riddle is next, or its state, or the
  # schedule and last riddle panels. Completed is here so a live riddle drops
  # off the card when it ends; changed carries admin edits and deletes.
  @state_topics ~w(games:riddle:scheduled games:riddle:ready games:riddle:live games:riddle:completed games:riddle:archived games:riddle:changed)
  @state_messages [
    :riddle_scheduled,
    :riddle_rescheduled,
    :riddle_unscheduled,
    :riddle_ready,
    :riddle_live,
    :riddle_completed,
    :riddle_archived,
    :riddle_saved,
    :riddle_deleted
  ]

  # How many riddles the schedule lists after the next one.
  @upcoming_limit 3

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe before reading the next riddle, so a change in between is
    # heard rather than lost.
    if connected?(socket) do
      Enum.each(@state_topics, &Phoenix.PubSub.subscribe(Riddlr.PubSub, &1))
    end

    next = Games.next_riddle()
    if connected?(socket), do: follow(nil, next)

    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign_next(next)
     |> assign_panels()}
  end

  @impl true
  def handle_info({message, _riddle}, socket) when message in @state_messages do
    next = Games.next_riddle()
    follow(socket.assigns.next, next)

    {:noreply,
     socket
     |> assign_next(next)
     |> assign_panels()
     |> sync_flaps()}
  end

  # A tick is only a heartbeat. Ticks carry no riddle id, so one from the last
  # next riddle's clock can land after a switch; reading the seconds from the
  # next riddle itself keeps a stale tick from showing the wrong time.
  def handle_info({:countdown_tick, _phase, _seconds}, socket) do
    case socket.assigns.next do
      nil ->
        {:noreply, socket}

      next ->
        {:noreply,
         socket
         |> assign(:seconds, seconds_left(next))
         |> sync_flaps()}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :waiting, waiting(socket.assigns.next))}
  end

  def handle_info({:answer_submitted, %{correct: true}}, socket) do
    {:noreply, assign(socket, :solved, solved(socket.assigns.next))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @spec assign_next(Phoenix.LiveView.Socket.t(), Games.Riddle.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp assign_next(socket, next) do
    socket
    |> assign(:next, next)
    |> assign(:seconds, seconds_left(next))
    |> assign(:waiting, waiting(next))
    |> assign(:solved, solved(next))
  end

  # The schedule under the hero and the last finished riddle.
  @spec assign_panels(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_panels(socket) do
    last = Games.last_finished_riddle()

    socket
    |> assign(:upcoming, Games.list_upcoming_riddles(@upcoming_limit))
    |> assign(:last, last)
    |> assign(:last_answer, last && List.first(last.answers, ""))
    |> assign(:last_win, last && last_win(last.id))
  end

  # The last riddle's first solver and time, from the saved solve.
  @spec last_win(integer()) :: %{name: String.t(), secs: String.t()} | nil
  defp last_win(riddle_id) do
    case Gameplay.first_solve(riddle_id) do
      nil ->
        nil

      solve ->
        %{
          name: if(solve.user, do: solve.user.username, else: GameCopy.gone_player()),
          secs: GameCopy.solve_secs(solve.solve_time_ms)
        }
    end
  end

  # The flaps hook owns its digits, so a new drop time (a reschedule, or a
  # new next riddle) must reach it as an event.
  @spec sync_flaps(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp sync_flaps(%{assigns: %{next: %{play_status: status}, seconds: seconds}} = socket)
       when status != "live" do
    push_event(socket, "countdown-tick", %{seconds: seconds})
  end

  defp sync_flaps(socket), do: socket

  # Moves the per-riddle subscriptions from the old next riddle to the new
  # one, and starts the new one's clock once its Lobby or race is open. A
  # scheduled riddle gets no clock: the flaps hook counts down by itself, and
  # `sync_flaps/1` corrects it when the drop time moves.
  @spec follow(Games.Riddle.t() | nil, Games.Riddle.t() | nil) :: :ok
  defp follow(old, new) do
    if old && old.id != (new && new.id) do
      Enum.each(riddle_topics(old.id), &Phoenix.PubSub.unsubscribe(Riddlr.PubSub, &1))
    end

    if new && (old == nil or old.id != new.id) do
      Enum.each(riddle_topics(new.id), &Phoenix.PubSub.subscribe(Riddlr.PubSub, &1))
    end

    if new && new.play_status in ["ready", "live"], do: GameClock.ensure_started(new)

    :ok
  end

  @spec riddle_topics(integer()) :: [String.t()]
  defp riddle_topics(id), do: [GameClock.topic(id), Presence.lobby_topic(id), Answer.topic(id)]

  # The seconds on the card's clock: until the drop, or left to solve. A riddle
  # past its drop time but not yet live holds at zero until the live broadcast.
  @spec seconds_left(Games.Riddle.t() | nil) :: non_neg_integer()
  defp seconds_left(nil), do: 0

  defp seconds_left(riddle) do
    case {riddle.play_status, GameClock.countdown(riddle)} do
      {"live", {:play, seconds}} -> seconds
      {"live", {:lobby, _seconds}} -> riddle.solve_time
      {_status, {:lobby, seconds}} -> seconds
      {_status, {:play, _seconds}} -> 0
    end
  end

  @spec waiting(Games.Riddle.t() | nil) :: non_neg_integer()
  defp waiting(nil), do: 0
  defp waiting(riddle), do: riddle.id |> Presence.lobby_topic() |> Presence.list() |> map_size()

  @spec solved(Games.Riddle.t() | nil) :: non_neg_integer()
  defp solved(%{play_status: "live", id: id}), do: Gameplay.solved_count(id)
  defp solved(_riddle), do: 0
end
