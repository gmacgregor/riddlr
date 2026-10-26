defmodule RiddlrWeb.GameLive.Play do
  @moduledoc """
  Live game view — answer submission, scoring, real-time gameplay.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{GameClock, Games, Gameplay}
  alias Riddlr.Gameplay.Answer
  alias RiddlrWeb.GameLive.Feed

  import Riddlr.Utils.User

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

          "completed" ->
            {:ok, push_navigate(socket, to: ~p"/game/#{id}/results")}

          "live" ->
            user = socket.assigns.current_user
            already_solved = Gameplay.solved?(riddle.id, user.id)

            initial_answers =
              if connected?(socket) do
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(id))
                Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.flagged_topic(id))
                Phoenix.PubSub.subscribe(Riddlr.PubSub, "user:#{user.id}")
                Phoenix.PubSub.subscribe(Riddlr.PubSub, GameClock.topic(riddle.id))
                GameClock.ensure_started(riddle)
                build_initial_feed(riddle.id)
              else
                []
              end

            {:ok,
             socket
             |> assign(:banned, is_banned?(user))
             |> assign(:page_title, "Play — #{riddle.name}")
             |> assign(:riddle, riddle)
             |> assign(:already_solved, already_solved)
             |> assign(:submission_state, nil)
             |> assign(:time_remaining, solve_seconds_left(riddle))
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
  def handle_info({:answer_submitted, answer_data}, socket) do
    {:noreply, stream_insert(socket, :answers, answer_data, at: 0)}
  end

  def handle_info({:answer_flagged, answer_id}, socket) do
    {:noreply, stream_delete(socket, :answers, %{id: answer_id})}
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
     |> assign(:time_remaining, seconds)
     |> push_event("countdown-tick", %{seconds: seconds})}
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

  defp format_error(:cooldown), do: "Please wait a moment before submitting again."
  defp format_error(:already_solved), do: "You've already solved this riddle!"
  defp format_error(:empty_answer), do: "Answer cannot be empty."

  defp format_error(:answer_too_long),
    do: "Answer is too long (max #{@answer_max_length} characters)."

  defp format_error({:not_live, _}), do: "The game is not currently active."

  defp try_again() do
    Enum.random(@try_again_messages)
  end

  # Builds feed items for answers already in ETS when the LiveView mounts.
  # Correct answers stay masked while the race runs (Answer.for_live_feed/1).
  # Offsets go: they only mean something for answers seen live.
  @spec build_initial_feed(integer()) :: [Answer.t()]
  defp build_initial_feed(riddle_id) do
    riddle_id
    |> Gameplay.get_answers()
    |> Enum.take(100)
    |> Feed.put_usernames()
    |> Enum.map(&%{Answer.for_live_feed(&1) | offset_ms: nil})
  end

  defp solve_seconds_left(riddle) do
    case GameClock.countdown(riddle) do
      {:play, seconds} -> seconds
      {:lobby, _} -> riddle.solve_time
    end
  end

  defp format_offset(ms) when ms < 1000, do: "#{ms}ms"
  defp format_offset(ms), do: "#{div(ms, 1000)}s"
end
