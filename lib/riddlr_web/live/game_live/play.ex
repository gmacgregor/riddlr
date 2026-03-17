defmodule RiddlrWeb.GameLive.Play do
  @moduledoc """
  Live game view — answer submission, scoring, real-time gameplay.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{Accounts, Games, Gameplay}

  @answer_max_length 500
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

            already_solved =
              status == "live" and
                match?(
                  {:error, :already_solved},
                  Gameplay.check_already_solved(riddle.id, user.id)
                )

            game_completed = status == "completed"

            {initial_answers, top_solvers} =
              if connected?(socket) do
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:archived")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{id}:answer_submitted")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{id}:answer_flagged")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "user:#{user.id}")
                answers = build_initial_feed(riddle.id, game_completed)
                solvers = if game_completed, do: load_top_solvers(riddle.id), else: []
                {answers, solvers}
              else
                {[], []}
              end

            # Track correct answers in assigns so we can re-stream them with highlight
            # when the game completes (stream items don't re-render on outer assign changes).
            correct_answers =
              initial_answers
              |> Enum.filter(& &1.correct)
              |> Map.new(&{&1.id, &1})

            time_remaining =
              if game_completed do
                0
              else
                compute_time_remaining(riddle.live_date, riddle.solve_time)
              end

            if connected?(socket) and not game_completed and time_remaining > 0 do
              Process.send_after(self(), :tick, 1000)
            end

            {:ok,
             socket
             |> assign(:page_title, "Play — #{riddle.name}")
             |> assign(:riddle, riddle)
             |> assign(:game_start_time, riddle.live_date)
             |> assign(:game_completed, game_completed)
             |> assign(:already_solved, already_solved)
             |> assign(:banned, user.account_status == :banned)
             |> assign(:submission_state, nil)
             |> assign(:time_remaining, time_remaining)
             |> assign(:cooldown_remaining, 0)
             |> assign(:correct_answers, correct_answers)
             |> assign(:top_solvers, top_solvers)
             |> stream(:answers, initial_answers, limit: 100)}
        end

      {:error, :not_found} ->
        {:ok, socket |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("submit_answer", %{"answer" => text}, socket) do
    text = String.trim(text)
    user = socket.assigns.current_user
    riddle = socket.assigns.riddle

    with :ok <- check_not_banned(socket.assigns),
         :ok <- check_game_live(riddle),
         :ok <- Gameplay.check_already_solved(riddle.id, user.id),
         :ok <- Gameplay.check_cooldown(riddle.id, user.id),
         :ok <- validate_input(text) do
      correct? = Gameplay.validate_answer(riddle, text)
      solve_time_ms = compute_offset_ms(socket.assigns.game_start_time)
      timestamp = Gameplay.store_answer(riddle.id, user.id, text, correct?, solve_time_ms)

      answer_data = %{
        id: "#{riddle.id}-#{user.id}-#{timestamp}",
        user_id: user.id,
        username: user.username,
        text: text,
        correct: correct?,
        timestamp: timestamp,
        offset_ms: solve_time_ms,
        show_highlight: false,
        flagged: false,
        chat: false
      }

      Gameplay.broadcast_answer(riddle.id, answer_data)
      Gameplay.moderate_answer_async(riddle.id, answer_data.id, text)

      if correct? do
        placement = Gameplay.calculate_placement(riddle.id, timestamp)
        {:ok, points} = Accounts.award_game_points(user.id, placement)

        if placement == 1 do
          first_solve_time_seconds = solve_time_ms && div(solve_time_ms, 1000)

          if riddle.live_until_solved do
            # live_until_solved games complete immediately on first solve
            stats =
              Gameplay.get_completion_stats(riddle.id)
              |> Map.put(:first_solve_time, first_solve_time_seconds)

            Games.complete_riddle_on_first_solve(riddle.id, user.id, stats)
          else
            # Timed games: record first solver; Oban CompleteRiddleWorker fires at solve_time
            Games.record_first_solver(riddle.id, user.id, first_solve_time_seconds)
          end
        end

        {:noreply,
         socket
         |> push_event("answer-correct", %{})
         |> assign(:already_solved, true)
         |> assign(:submission_state, {:correct, placement, points})}
      else
        socket = assign(socket, :try_again_message, try_again())

        {:noreply,
         socket
         |> assign(:submission_state, :incorrect)
         |> push_event("answer-shake", %{})}
      end
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
  def handle_event("send_chat", %{"message" => text}, socket) do
    text = String.trim(text)
    user = socket.assigns.current_user
    riddle = socket.assigns.riddle

    with :ok <- validate_input(text),
         :ok <- check_not_banned(socket.assigns),
         :ok <- check_game_completed(riddle) do
      chat_data = %{
        id: "chat-#{riddle.id}-#{user.id}-#{System.monotonic_time(:microsecond)}",
        user_id: user.id,
        username: user.username,
        text: text,
        correct: false,
        timestamp: System.monotonic_time(:microsecond),
        offset_ms: nil,
        show_highlight: false,
        flagged: false,
        chat: true
      }

      Gameplay.broadcast_chat(riddle.id, chat_data)
      {:noreply, socket}
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
    socket = stream_insert(socket, :answers, answer_data, at: 0)

    socket =
      if answer_data.correct do
        update(socket, :correct_answers, &Map.put(&1, answer_data.id, answer_data))
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:answer_flagged, answer_id}, socket) do
    {:noreply, stream_delete(socket, :answers, %{id: answer_id})}
  end

  def handle_info({:riddle_completed, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      # Re-insert correct answers with show_highlight: true so the stream items
      # update in the DOM (stream items don't re-render on outer assign changes).
      socket =
        socket.assigns.correct_answers
        |> Enum.reduce(socket, fn {_id, answer}, acc ->
          stream_insert(acc, :answers, %{answer | show_highlight: true})
        end)

      top_solvers = load_top_solvers(riddle.id)
      cooldown_remaining = riddle.archive_cooldown_minutes * 60

      if cooldown_remaining > 0 do
        Process.send_after(self(), :cooldown_tick, 1000)
      end

      {:noreply,
       socket
       |> assign(:riddle, riddle)
       |> assign(:game_completed, true)
       |> assign(:time_remaining, 0)
       |> assign(:cooldown_remaining, cooldown_remaining)
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

  def handle_info(:tick, socket) do
    if socket.assigns.game_completed do
      {:noreply, socket}
    else
      time_remaining =
        compute_time_remaining(socket.assigns.game_start_time, socket.assigns.riddle.solve_time)

      if time_remaining > 0 do
        Process.send_after(self(), :tick, 1000)
      end

      {:noreply,
       socket
       |> assign(:time_remaining, time_remaining)
       |> push_event("countdown-tick", %{seconds: time_remaining})}
    end
  end

  def handle_info(:cooldown_tick, socket) do
    remaining = max(0, socket.assigns.cooldown_remaining - 1)

    if remaining > 0 do
      Process.send_after(self(), :cooldown_tick, 1000)
    end

    {:noreply, assign(socket, :cooldown_remaining, remaining)}
  end

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

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp check_not_banned(%{banned: true}), do: {:error, :banned}
  defp check_not_banned(_assigns), do: :ok

  defp check_game_live(%{play_status: "live"}), do: :ok
  defp check_game_live(%{play_status: status}), do: {:error, {:not_live, status}}

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

  defp placement_text(1), do: "1st"
  defp placement_text(2), do: "2nd"
  defp placement_text(3), do: "3rd"
  defp placement_text(n), do: "#{n}th"

  defp try_again() do
    Enum.random(@try_again_messages)
  end

  # Builds feed items for answers already in ETS when the LiveView mounts.
  # Batch-loads usernames from the DB to avoid N+1 queries.
  # When game_completed is true, correct answers are immediately highlighted.
  defp build_initial_feed(riddle_id, game_completed) do
    ets_answers = Gameplay.get_answers(riddle_id)

    user_ids = ets_answers |> Enum.map(& &1.user_id) |> Enum.uniq()
    users_by_id = Accounts.get_users_by_ids(user_ids)

    ets_answers
    |> Enum.take(100)
    |> Enum.map(fn a ->
      username =
        case Map.get(users_by_id, a.user_id) do
          %{username: u} -> u
          nil -> "Player"
        end

      %{
        id: "#{riddle_id}-#{a.user_id}-#{a.timestamp}",
        user_id: a.user_id,
        username: username,
        text: a.text,
        correct: a.correct,
        offset_ms: nil,
        show_highlight: game_completed and a.correct,
        flagged: false,
        chat: false
      }
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

  defp compute_time_remaining(nil, solve_time), do: solve_time

  defp compute_time_remaining(live_date, solve_time) do
    elapsed = DateTime.diff(DateTime.utc_now(), live_date, :second)
    max(solve_time - elapsed, 0)
  end

  defp format_time(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> IO.iodata_to_binary()
  end

  defp compute_offset_ms(nil), do: nil

  defp compute_offset_ms(game_start) do
    max(DateTime.diff(DateTime.utc_now(), game_start, :millisecond), 0)
  end

  defp format_offset(ms) when ms < 1000, do: "#{ms}ms"
  defp format_offset(ms), do: "#{div(ms, 1000)}s"

  defp top_answer([head | _]), do: head
  defp remaining_answers([_ | tail]), do: tail

  defp has_many_answers?(answers) do
    length(answers) > 1
  end

  defp chat_status("live") do
    "Answer feed"
  end

  defp chat_status("completed") do
    "Post game chat"
  end

  defp chat_status(_), do: ""
end
