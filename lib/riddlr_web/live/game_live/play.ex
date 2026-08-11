defmodule RiddlrWeb.GameLive.Play do
  @moduledoc """
  Live game view — answer submission, scoring, real-time gameplay.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{Accounts, GameClock, Games, Gameplay}
  alias Riddlr.Gameplay.Answer

  import Riddlr.Utils.User

  @answer_max_length 500

  # The feed carries on after the round ends, so it needs a row saying where the
  # round stopped and the chat started. Streams can't inject a row at render
  # time, so the divider rides in the stream as an item of its own.
  @round_ended %{id: "round-ended", divider: true}

  @try_again_messages [
    "Uuuh… no! Think harder.",
    "Ooopsie whoopise, not quite. Go on, guess again!",
    "Good guess, but no! So close… or not.",
    "Nooooope! Wrack that brain.",
    "Not so, unfortunately. Back to the drawing board!"
  ]

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

          status when status in ["live", "completed"] ->
            user = socket.assigns.current_user
            game_completed = status == "completed"
            game_live = status == "live"

            already_solved = game_live and Gameplay.solved?(riddle.id, user.id)

            {initial_answers, top_solvers} =
              if connected?(socket) do
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:archived")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(id))
                Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.flagged_topic(id))
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "user:#{user.id}")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, GameClock.topic(riddle.id))
                answers = build_initial_feed(riddle.id, game_completed)
                answers = if game_completed, do: [@round_ended | answers], else: answers
                solvers = if game_completed, do: load_top_solvers(riddle.id), else: []
                {answers, solvers}
              else
                {[], []}
              end

            time_remaining =
              if game_completed do
                0
              else
                if connected?(socket), do: GameClock.ensure_started(riddle)
                solve_seconds_left(riddle)
              end

            {:ok,
             socket
             |> assign(:banned, is_banned?(user))
             |> assign(:page_title, "Play — #{riddle.name}")
             |> assign(:riddle, riddle)
             |> assign(:game_completed, game_completed)
             |> assign(:already_solved, already_solved)
             |> assign(:submission_state, nil)
             |> assign(:time_remaining, time_remaining)
             |> assign(:top_solvers, top_solvers)
             |> assign(:active_tab, :leaderboard)
             |> assign(:try_again_message, nil)
             |> stream(:answers, initial_answers, limit: 100)}
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
        # Delay already_solved assign by 450ms so the .AnswerForm fade animation (400ms)
        # completes before LiveView removes the form container from the DOM.
        Process.send_after(self(), {:mark_solved, riddle.id}, 450)

        {:noreply,
         socket
         |> push_event("answer-correct", %{})
         |> assign(:submission_state, {:correct, placement, points})}

      :incorrect ->
        {:noreply,
         socket
         |> assign(:try_again_message, try_again())
         |> assign(:submission_state, :incorrect)
         |> push_event("answer-shake", %{})}

      {:error, :banned} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> push_navigate(to: ~p"/")}

      {:error, reason} ->
        {:noreply, assign(socket, :submission_state, {:error, format_error(reason)})}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("send_chat", %{"message" => text}, socket) do
    text = String.trim(text)
    user = socket.assigns.current_user
    riddle = socket.assigns.riddle

    with :ok <- validate_input(text),
         :ok <- check_not_banned(socket.assigns),
         :ok <- check_game_completed(riddle) do
      Gameplay.broadcast_answer(Answer.new(riddle.id, user, text, chat: true))
      {:noreply, push_event(socket, "chat-sent", %{})}
    else
      {:error, :banned} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> push_navigate(to: ~p"/")}

      {:error, reason} ->
        {:noreply, assign(socket, :submission_state, {:error, format_error(reason)})}
    end
  end

  @impl true
  def handle_info({:answer_submitted, answer_data}, socket) do
    {:noreply, stream_insert(socket, :answers, answer_data, at: 0)}
  end

  def handle_info({:answer_flagged, answer_id}, socket) do
    {:noreply, stream_delete(socket, :answers, %{id: answer_id})}
  end

  def handle_info({:riddle_completed, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      # The post-game feed renders in its own container, and a stream only ships
      # the rows it was handed this render — the live feed's rows leave with the
      # container that held them. So rebuild the feed from ETS, which also
      # unmasks the correct answers now that revealing them is safe.
      feed = build_initial_feed(riddle.id, true)

      top_solvers = load_top_solvers(riddle.id)

      {:noreply,
       socket
       |> stream(:answers, feed, reset: true, limit: 100)
       |> stream_insert(:answers, @round_ended, at: 0)
       |> assign(:riddle, riddle)
       |> assign(:game_completed, true)
       |> assign(:time_remaining, 0)
       |> assign(:top_solvers, top_solvers)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:riddle_archived, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      {
        :noreply,
        socket
        |> put_flash(:info, "This game has been archived.")
        #  |> push_navigate(to: ~p"/")
      }
    else
      {:noreply, socket}
    end
  end

  def handle_info({:countdown_tick, :play, seconds}, socket) do
    if socket.assigns.game_completed do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:time_remaining, seconds)
       |> push_event("countdown-tick", %{seconds: seconds})}
    end
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

  def handle_info({:mark_solved, riddle_id}, socket) do
    if socket.assigns.riddle.id == riddle_id do
      {:noreply, assign(socket, :already_solved, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp check_not_banned(%{banned: true}), do: {:error, :banned}
  defp check_not_banned(_assigns), do: :ok

  # Every feed item is an answer except the round-ended divider.
  defp divider?(item), do: Map.get(item, :divider, false)

  defp check_game_completed(%{play_status: "completed"}), do: :ok
  defp check_game_completed(%{play_status: status}), do: {:error, {:not_completed, status}}

  defp validate_input(text) do
    cond do
      text == "" -> {:error, :empty_answer}
      String.length(text) > @answer_max_length -> {:error, :answer_too_long}
      true -> :ok
    end
  end

  defp format_error(:cooldown), do: "Please wait a moment before submitting again."
  defp format_error(:already_solved), do: "You've already solved this riddle!"
  defp format_error(:empty_answer), do: "Answer cannot be empty."

  defp format_error(:answer_too_long),
    do: "Answer is too long (max #{@answer_max_length} characters)."

  defp format_error({:not_live, _}), do: "The game is not currently active."
  defp format_error(_), do: "Something went wrong. Please try again."

  defp try_again() do
    Enum.random(@try_again_messages)
  end

  # Builds feed items for answers already in ETS when the LiveView mounts.
  # Batch-loads usernames from the DB to avoid N+1 queries.
  # Correct answers were masked while the round ran (Answer.for_live_feed/1), so
  # ETS is the only place the real text survives. Revealing is simply not masking.
  # ETS doesn't store usernames, so the feed is joined against Accounts here.
  # Offsets are dropped: they're only meaningful live, next to a running timer.
  defp build_initial_feed(riddle_id, game_completed) do
    answers = Gameplay.get_answers(riddle_id) |> Enum.take(100)

    users_by_id =
      answers |> Enum.map(& &1.user_id) |> Enum.uniq() |> Accounts.get_users_by_ids()

    Enum.map(answers, fn answer ->
      username =
        case Map.get(users_by_id, answer.user_id) do
          %{username: u} -> u
          nil -> "Player"
        end

      answer = if game_completed, do: answer, else: Answer.for_live_feed(answer)

      %{answer | username: username, offset_ms: nil}
    end)
  end

  # Loads top solvers from ETS and batch-fetches their usernames from the DB.
  defp load_top_solvers(riddle_id) do
    solver_entries = Gameplay.get_top_solvers(riddle_id)
    user_ids = Enum.map(solver_entries, & &1.user_id)
    users_by_id = Accounts.get_users_by_ids(user_ids)

    Enum.map(solver_entries, fn entry ->
      username =
        case Map.get(users_by_id, entry.user_id) do
          %{username: u} -> u
          nil -> "Player"
        end

      solve_time_display =
        case entry.solve_time_ms do
          nil -> nil
          ms -> format_time(div(ms, 1000))
        end

      entry |> Map.put(:username, username) |> Map.put(:solve_time_display, solve_time_display)
    end)
  end

  defp solve_seconds_left(riddle) do
    case GameClock.countdown(riddle) do
      {:play, seconds} -> seconds
      {:lobby, _} -> riddle.solve_time
    end
  end

  def format_time(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> IO.iodata_to_binary()
  end

  defp format_offset(ms) when ms < 1000, do: "#{ms}ms"
  defp format_offset(ms), do: "#{div(ms, 1000)}s"
end
