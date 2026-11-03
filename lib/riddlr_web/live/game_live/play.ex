defmodule RiddlrWeb.GameLive.Play do
  @moduledoc """
  Live game view — answer submission, scoring, real-time gameplay.

  A guest may watch the riddle and the guess feed, but gets no guess form, and
  the server drops any guess a guest sends.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{Accounts, GameClock, Games, Gameplay}
  alias Riddlr.Gameplay.Answer
  alias RiddlrWeb.{GameComponents, GameCopy}
  alias RiddlrWeb.GameLive.Stagger

  @answer_max_length 500
  # The most guesses the feed keeps in the DOM; older ones drop off the top.
  @feed_limit 100

  # How long the Guess button stays disabled after a guess. Matches the
  # Gameplay cooldown.
  @cooldown_ms 1_000

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

          "completed" ->
            {:ok, push_navigate(socket, to: ~p"/game/#{id}/results")}

          "live" ->
            scope = socket.assigns.current_scope
            user = scope && scope.user

            {initial_answers, guess_count, solved} =
              if connected?(socket) do
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")
                Gameplay.subscribe_answers(id)
                if user, do: Phoenix.PubSub.subscribe(Riddlr.PubSub, "user:#{user.id}")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, GameClock.topic(riddle.id))
                GameClock.ensure_started(riddle)
                build_initial_feed(riddle.id)
              else
                {[], 0, 0}
              end

            {:ok,
             socket
             |> assign(:banned, Accounts.banned?(user))
             |> assign(:page_title, "Play — #{riddle.name}")
             |> assign(:riddle, riddle)
             |> assign(:words, String.split(riddle.description))
             |> assign(:solve, user && Gameplay.live_solve_for(riddle.id, user.id))
             |> assign(:time_remaining, solve_seconds_left(riddle))
             |> assign(:guess_msg, nil)
             |> assign(:guess_wrong?, false)
             |> assign(:cooling?, false)
             |> assign(:cooldown_timer, nil)
             |> assign(:guess_count, guess_count)
             |> assign(:solved, solved)
             |> stream(:answers, initial_answers, limit: -@feed_limit)}
        end

      {:error, :not_found} ->
        {:ok, socket |> push_navigate(to: ~p"/")}
    end
  end

  # A guest has no form, but a guess could still be sent by hand.
  @impl true
  def handle_event("submit_answer", _params, %{assigns: %{current_scope: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("submit_answer", %{"answer" => text}, socket) do
    riddle = socket.assigns.riddle

    result =
      case check_not_banned(socket.assigns) do
        :ok -> Gameplay.submit_answer(riddle, socket.assigns.current_scope.user, text)
        {:error, :banned} = error -> error
      end

    case result do
      {:correct, placement, points} ->
        {:noreply, assign(socket, :solve, %{placement: placement, points: points})}

      :incorrect ->
        {:noreply,
         socket
         |> put_guess_msg(GameCopy.Play.quip(socket.assigns.guess_msg), true)
         |> start_cooldown()
         |> push_event("guess-wrong", %{})}

      {:error, :banned} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> push_navigate(to: ~p"/")}

      {:error, :empty_answer} ->
        {:noreply, put_guess_msg(socket, GameCopy.Play.guess_empty(), true)}

      {:error, reason} ->
        {:noreply, put_guess_msg(socket, format_error(reason), false)}
    end
  end

  @impl true
  # Totals count every guess stored, so they replace the counts. A batch sent
  # before the mount snapshot was read can land after it, so counts only rise.
  def handle_info({:answers_batch, answers, %{guesses: guesses, solved: solved}}, socket) do
    socket =
      Enum.reduce(answers, socket, &stream_insert(&2, :answers, &1, at: -1, limit: -@feed_limit))

    {:noreply,
     socket
     |> update(:guess_count, &max(&1, guesses))
     |> update(:solved, &max(&1, solved))}
  end

  def handle_info({:answer_flagged, answer_id}, socket) do
    {:noreply,
     socket
     |> update(:guess_count, &max(&1 - 1, 0))
     |> stream_delete(:answers, %{id: answer_id})}
  end

  # The riddle ended while the player watched, so Results opens with a
  # celebration. Results drops the param once read, so a reload doesn't replay it.
  # The completed riddle replaces the mounted one, so a guess that lands before
  # the page leaves is checked against the "completed" status.
  def handle_info({:riddle_completed, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      {:noreply,
       socket
       |> assign(:riddle, riddle)
       |> Stagger.navigate(~p"/game/#{riddle.id}/results?celebrate=1")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:stagger_navigate, path}, socket) do
    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_info({:countdown_tick, :play, seconds}, socket) do
    {:noreply,
     socket
     |> assign(:time_remaining, seconds)}
  end

  # The riddle is already live here, so a :lobby tick can only be the clock's
  # first broadcast arriving just after mount. Nothing on this page counts down
  # to the live date.
  def handle_info({:countdown_tick, _phase, _seconds}, socket), do: {:noreply, socket}

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

  def handle_info(:cooldown_over, socket) do
    {:noreply, assign(socket, cooling?: false, cooldown_timer: nil)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp check_not_banned(%{banned: true}), do: {:error, :banned}
  defp check_not_banned(_assigns), do: :ok

  defp put_guess_msg(socket, msg, wrong?),
    do: assign(socket, guess_msg: msg, guess_wrong?: wrong?)

  # Disables the Guess button for a second. A new guess restarts the timer.
  defp start_cooldown(socket) do
    if timer = socket.assigns.cooldown_timer, do: Process.cancel_timer(timer)
    timer = Process.send_after(self(), :cooldown_over, @cooldown_ms)
    assign(socket, cooling?: true, cooldown_timer: timer)
  end

  defp format_error(:cooldown), do: GameCopy.Play.guess_cooldown()
  defp format_error(:time_up), do: GameCopy.Play.guess_time_up()
  defp format_error(:already_solved), do: "You've already solved this riddle!"

  defp format_error(:answer_too_long),
    do: "Answer is too long (max #{@answer_max_length} characters)."

  defp format_error({:not_live, _}), do: "The game is not currently active."

  # Builds feed items for the newest answers in ETS when the LiveView mounts,
  # oldest first, plus how many guesses and solves the riddle has so far.
  # Correct answers stay masked while the race runs.
  @spec build_initial_feed(integer()) ::
          {[Answer.t()], non_neg_integer(), non_neg_integer()}
  defp build_initial_feed(riddle_id) do
    feed = Gameplay.get_live_feed(riddle_id, @feed_limit)

    {feed, Gameplay.answer_count(riddle_id), Gameplay.solved_count(riddle_id)}
  end

  defp solve_seconds_left(riddle) do
    case GameClock.countdown(riddle) do
      {:play, seconds} -> seconds
      {:lobby, _} -> riddle.solve_time
    end
  end

  # The clock's warning class. Thresholds come from the design.
  @spec urgency(integer()) :: String.t() | nil
  defp urgency(seconds) when seconds <= 10, do: "is-crit"
  defp urgency(seconds) when seconds <= 20, do: "is-warn"
  defp urgency(_seconds), do: nil

  # How much of the riddle's solve time is left, from 0.0 to 1.0, for the track's scaleX.
  @spec share_left(integer(), integer() | nil) :: float()
  defp share_left(_seconds, total) when not is_integer(total) or total <= 0, do: 0.0
  defp share_left(seconds, total), do: (seconds / total) |> max(0.0) |> min(1.0) |> Float.round(3)
end
