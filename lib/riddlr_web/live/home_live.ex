defmodule RiddlrWeb.HomeLive do
  @moduledoc """
  The public Home page: an "Up next" hero card for the next riddle
  (`Games.next_riddle/0`), a timeline of a round, and two notes.

  The hero card has one state for each Next riddle case, set as `data-state`
  on the hero sheet:

    * `none`: no next riddle. The heading reads "Nothing listed", with no
      date.
    * `future`: scheduled, Lobby not open. A countdown and a "While you
      wait" practice note, with no button. The drop time sits under the
      heading.
    * `lobby`: ready. A countdown, how many players wait in the Lobby, and a
      button to it.
    * `live`: the time left, how many have solved it, and a button to Play.

  In the other states, the date under the heading is the next riddle's drop
  date.

  A hand-drawn thinker (`RiddlrWeb.Thinker`) sits on the card's corner in
  every state but `none`. It is random on each load, and kept as the page
  connects.

  With nothing next, the card also shows a blank clock and a link to Coming
  up. With nothing next, or a riddle whose Lobby is not open yet, it shows a
  "While you wait" practice note (`GameComponents.practice_note/1`)
  with a random practice riddle. "Another riddle" swaps in a different one.
  The note is hidden when there are no practice riddles.

  The timeline ("A round, start to finish") ends at the next riddle's solve
  time. Below it, "Coming up" lists the riddles not yet live, the
  next one included (`Games.list_upcoming_riddles/1`), with no riddle text, and "Previously"
  shows the most recent finished riddle with its answer and first solver
  (`Games.last_finished_riddle/0`).

  The topbar pill follows the same next riddle: "Live now" while it is live,
  else "Next" with a countdown. It reuses the card's data and adds no
  subscription.

  The page follows the riddle's state while open. It listens to the riddle
  state topics, and to the next riddle's clock and its Lobby and solver
  counts, which the clock sends at most once a second.
  When the next riddle changes, the per-riddle topics move with it. Any state
  message reloads the card and both notes.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{GameClock, Gameplay, Games}
  alias Riddlr.Gameplay.Presence
  alias RiddlrWeb.{DropTime, GameComponents, GameCopy, Thinker}

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

  @typedoc "A practice riddle and its place in the set, for the practice note."
  @type practice :: %{
          riddle: Games.PracticeRiddle.t(),
          n: pos_integer(),
          total: pos_integer()
        }

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
     # The "While you wait" note's practice riddle, as
     # `%{riddle: riddle, n: n, total: total}`, or nil to hide the note.
     # `assign_next/2` picks one once nothing is next.
     |> assign(:practice, kept_practice(socket))
     |> assign(:thinker, kept_thinker(socket))
     |> assign_next(next)
     |> assign_panels()}
  end

  # "Another riddle": a different practice riddle from the one on screen. The
  # view transition event goes out before the patch, so the client can slide
  # the new riddle in.
  @impl true
  def handle_event("another_practice", _params, socket) do
    exclude_id = socket.assigns.practice && socket.assigns.practice.riddle.id

    case Games.random_practice_riddle(exclude_id) do
      nil ->
        {:noreply, socket}

      riddle ->
        {:noreply,
         socket
         |> assign(:practice, practice(riddle))
         |> push_event("view-transition", %{}, dispatch: :before)}
    end
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

  # Counts from the last next riddle's clock can land after a switch.
  def handle_info({:riddle_stats, id, stats}, %{assigns: %{next: %{id: id} = next}} = socket) do
    solved = if next.play_status == "live", do: stats.solved, else: 0
    {:noreply, assign(socket, waiting: stats.waiting, solved: solved)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # The hero card's top for a riddle not yet live: its title and countdown.
  # The lobby and future states share it. The drop time sits under "Up next".
  attr :riddle, Games.Riddle, required: true
  attr :seconds, :integer, required: true

  defp drop(assigns) do
    ~H"""
    <div class="rg-hero__row">
      <span class="rg-hero__label">{GameCopy.riddle_title(@riddle)}</span>
    </div>
    <GameComponents.flaps id="hero-flaps" seconds={@seconds} />
    """
  end

  # The "While you wait" note, in the none and future states. Shows nothing
  # with no practice riddles.
  attr :practice, :map, default: nil

  defp practice_note(assigns) do
    ~H"""
    <GameComponents.practice_note
      :if={@practice}
      id="practice"
      riddle={@practice.riddle}
      n={@practice.n}
      total={@practice.total}
      on_another="another_practice"
      data-practice-id={@practice.riddle.id}
    />
    """
  end

  @spec assign_next(Phoenix.LiveView.Socket.t(), Games.Riddle.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp assign_next(socket, next) do
    socket
    |> assign(:next, next)
    |> assign(:hero, hero_state(next))
    |> assign(:today, Riddlr.Clock.utc_now())
    |> assign(:round_end, round_end(next))
    |> assign(:seconds, seconds_left(next))
    |> assign(:waiting, waiting(next))
    |> assign(:solved, solved(next))
    |> assign_practice()
  end

  # Picks a practice riddle the first time the card shows the note (nothing
  # next, or a riddle whose Lobby is not open yet), and keeps it after that,
  # so a state change does not swap it under the player.
  @spec assign_practice(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_practice(%{assigns: %{hero: hero, practice: nil}} = socket)
       when hero in [:none, :future] do
    assign(socket, :practice, practice(Games.random_practice_riddle()))
  end

  defp assign_practice(socket), do: socket

  # Each mount picks at random, so the connected mount would swap the riddle
  # the static page showed. app.js sends that riddle's id as a connect param
  # (also on reconnect); keep it if it still exists.
  @spec kept_practice(Phoenix.LiveView.Socket.t()) :: practice() | nil
  defp kept_practice(socket) do
    with true <- connected?(socket),
         %{"practice_id" => id} <- get_connect_params(socket),
         {id, ""} <- Integer.parse(id) do
      practice(Games.get_practice_riddle(id))
    else
      _ -> nil
    end
  end

  # The thinker in the hero card's corner, random on each load. Like the
  # practice riddle, app.js sends the static page's pick on connect, so the
  # drawing does not change as the page connects.
  @spec kept_thinker(Phoenix.LiveView.Socket.t()) :: pos_integer()
  defp kept_thinker(socket) do
    with true <- connected?(socket),
         %{"thinker" => param} <- get_connect_params(socket),
         n when is_integer(n) <- Thinker.parse(param) do
      n
    else
      _ -> Thinker.random()
    end
  end

  @spec practice(Games.PracticeRiddle.t() | nil) :: practice() | nil
  defp practice(nil), do: nil

  defp practice(riddle) do
    %{
      riddle: riddle,
      n: Games.practice_riddle_number(riddle),
      total: Games.count_practice_riddles()
    }
  end

  # The schedule under the hero and the last finished riddle.
  @spec assign_panels(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_panels(socket) do
    last = Games.last_finished_riddle()

    socket
    |> assign(:upcoming, Games.list_upcoming_riddles(@upcoming_limit))
    |> assign(:last, last)
    |> assign(:last_answer, last && List.first(last.answers, ""))
    |> assign(:last_tone, last && answer_tone(last.id))
    |> assign(:last_win, last && last_win(last.id))
  end

  # The highlighter colour behind the last answer. It looks picked at random,
  # but comes from the riddle id, so it holds still when the page updates.
  # The paper tile (5) and the warning red (6) are left out.
  @answer_tones ~w(variant-1 variant-2 variant-3 variant-4 variant-7 variant-8 variant-9)

  @spec answer_tone(integer()) :: String.t()
  defp answer_tone(riddle_id),
    do: Enum.at(@answer_tones, :erlang.phash2(riddle_id, length(@answer_tones)))

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
  defp riddle_topics(id), do: [GameClock.topic(id), GameClock.stats_topic(id)]

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

  # The hero card's state, one per Next riddle case. A `scheduled` riddle is
  # `future`: its Lobby is not open yet.
  @spec hero_state(Games.Riddle.t() | nil) :: GameCopy.hero_state()
  defp hero_state(nil), do: :none
  defp hero_state(%{play_status: "live"}), do: :live
  defp hero_state(%{play_status: "ready"}), do: :lobby
  defp hero_state(_riddle), do: :future

  # The last time on the timeline: when the next riddle's round ends.
  @spec round_end(Games.Riddle.t() | nil) :: String.t()
  defp round_end(nil), do: GameCopy.timeline_end_default()
  defp round_end(riddle), do: GameCopy.m_ss(riddle.solve_time)

  @spec waiting(Games.Riddle.t() | nil) :: non_neg_integer()
  defp waiting(nil), do: 0
  defp waiting(riddle), do: riddle.id |> Presence.lobby_topic() |> Presence.list() |> map_size()

  @spec solved(Games.Riddle.t() | nil) :: non_neg_integer()
  defp solved(%{play_status: "live", id: id}), do: Gameplay.solved_count(id)
  defp solved(_riddle), do: 0
end
