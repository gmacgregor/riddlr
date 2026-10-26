defmodule RiddlrWeb.GameLive.Play do
  @moduledoc """
  Live game view — answer submission, scoring, real-time gameplay.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{GameClock, Games, Gameplay}
  alias Riddlr.Gameplay.Answer
  alias RiddlrWeb.{GameComponents, GameCopy}
  alias RiddlrWeb.GameLive.Feed

  import Riddlr.Utils.User

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
            user = socket.assigns.current_user

            {initial_answers, guess_count} =
              if connected?(socket) do
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(id))
                Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.flagged_topic(id))
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "user:#{user.id}")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, GameClock.topic(riddle.id))
                GameClock.ensure_started(riddle)
                build_initial_feed(riddle.id)
              else
                {[], 0}
              end

            {:ok,
             socket
             |> assign(:banned, is_banned?(user))
             |> assign(:page_title, "Play — #{riddle.name}")
             |> assign(:riddle, riddle)
             |> assign(:words, String.split(riddle.description))
             |> assign(:solve, Gameplay.solve_for(riddle.id, user.id))
             |> assign(:time_remaining, solve_seconds_left(riddle))
             |> assign(:guess_msg, nil)
             |> assign(:guess_wrong?, false)
             |> assign(:cooling?, false)
             |> assign(:cooldown_timer, nil)
             |> assign(:guess_count, guess_count)
             |> stream(:answers, initial_answers, limit: -@feed_limit)}
        end

      {:error, :not_found} ->
        {:ok, socket |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("submit_answer", %{"answer" => text}, socket) do
    riddle = socket.assigns.riddle

    result =
      case check_not_banned(socket.assigns) do
        :ok -> Gameplay.submit_answer(riddle, socket.assigns.current_user, text)
        {:error, :banned} = error -> error
      end

    case result do
      {:correct, placement, points} ->
        {:noreply, assign(socket, :solve, %{placement: placement, points: points})}

      :incorrect ->
        {:noreply,
         socket
         |> put_guess_msg(GameCopy.quip(socket.assigns.guess_msg), true)
         |> start_cooldown()
         |> push_event("guess-wrong", %{})}

      {:error, :banned} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> push_navigate(to: ~p"/")}

      {:error, :empty_answer} ->
        {:noreply, put_guess_msg(socket, GameCopy.guess_empty(), true)}

      {:error, reason} ->
        {:noreply, put_guess_msg(socket, format_error(reason), false)}
    end
  end

  @impl true
  def handle_info({:answer_submitted, answer_data}, socket) do
    {:noreply,
     socket
     |> update(:guess_count, &(&1 + 1))
     |> stream_insert(:answers, answer_data, at: -1, limit: -@feed_limit)}
  end

  def handle_info({:answer_flagged, answer_id}, socket) do
    {:noreply,
     socket
     |> update(:guess_count, &max(&1 - 1, 0))
     |> stream_delete(:answers, %{id: answer_id})}
  end

  def handle_info({:riddle_completed, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      {:noreply, push_navigate(socket, to: ~p"/game/#{riddle.id}/results")}
    else
      {:noreply, socket}
    end
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

  defp format_error(:cooldown), do: GameCopy.guess_cooldown()
  defp format_error(:already_solved), do: "You've already solved this riddle!"

  defp format_error(:answer_too_long),
    do: "Answer is too long (max #{@answer_max_length} characters)."

  defp format_error({:not_live, _}), do: "The game is not currently active."

  # Builds feed items for answers already in ETS when the LiveView mounts,
  # oldest first, plus the count of every guess so far.
  # Correct answers stay masked while the race runs (Answer.for_live_feed/1).
  @spec build_initial_feed(integer()) :: {[Answer.t()], non_neg_integer()}
  defp build_initial_feed(riddle_id) do
    answers = Gameplay.get_answers(riddle_id)

    feed =
      answers
      |> Enum.take(@feed_limit)
      |> Enum.reverse()
      |> Feed.put_usernames()
      |> Enum.map(&Answer.for_live_feed/1)

    {feed, length(answers)}
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
