defmodule RiddlrWeb.GameLive.Play do
  @moduledoc """
  Live game view — answer submission, scoring, real-time gameplay.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{Accounts, Games, Gameplay}

  @answer_max_length 500
  @try_again_messages [
    "Uuuh… no! Try again.",
    "Ooopsie whoopise, not quite. Try again!",
    "Good guess, but no!",
    "Nooooope!",
    "Not so, I'm afraid. Try again!"
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # DB query in both connected and disconnected mount is intentional: we need
    # play_status to decide the redirect destination before the socket connects.
    riddle = Games.get_riddle!(id)

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

        if connected?(socket) do
          Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:completed")
          Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:archived")
        end

        already_solved =
          status == "live" and
            match?({:error, :already_solved}, Gameplay.check_already_solved(riddle.id, user.id))

        {:ok,
         socket
         |> assign(:page_title, "Play — #{riddle.name}")
         |> assign(:riddle, riddle)
         |> assign(:game_completed, status == "completed")
         |> assign(:already_solved, already_solved)
         |> assign(:submission_state, nil)}
    end
  end

  @impl true
  def handle_event("submit_answer", %{"answer" => text}, socket) do
    text = String.trim(text)
    user = socket.assigns.current_user
    riddle = socket.assigns.riddle

    # Re-fetch user to check current ban status
    fresh_user = Accounts.get_user!(user.id)

    with :ok <- check_not_banned(fresh_user),
         :ok <- check_game_live(riddle),
         :ok <- Gameplay.check_already_solved(riddle.id, user.id),
         :ok <- Gameplay.check_cooldown(riddle.id, user.id),
         :ok <- validate_input(text) do
      correct? = Gameplay.validate_answer(riddle, text)
      timestamp = Gameplay.store_answer(riddle.id, user.id, text, correct?)

      answer_data = %{
        id: "#{riddle.id}-#{user.id}-#{timestamp}",
        user_id: user.id,
        username: user.username,
        text: text,
        correct: correct?,
        timestamp: timestamp
      }

      Gameplay.broadcast_answer(riddle.id, answer_data)

      if correct? do
        placement = Gameplay.calculate_placement(riddle.id, timestamp)
        {:ok, points} = Accounts.award_game_points(user.id, placement)

        if placement == 1 do
          Games.record_first_solver(riddle.id, user.id)
        end

        {:noreply,
         socket
         |> assign(:already_solved, true)
         |> assign(:submission_state, {:correct, placement, points})}
      else
        socket = assign(socket, :try_again_message, try_again())
        {:noreply, assign(socket, :submission_state, :incorrect)}
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
  def handle_info({:riddle_completed, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      {:noreply,
       socket
       |> assign(:riddle, riddle)
       |> assign(:game_completed, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:riddle_archived, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      {:noreply,
       socket
       |> put_flash(:info, "This game has been archived.")
       |> push_navigate(to: ~p"/")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-12">
      <div class="text-center mb-8">
        <div class="flex items-center justify-center gap-3 mb-2">
          <span
            :if={@riddle.category}
            class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-700/10"
          >
            {@riddle.category.name}
          </span>
          <span
            :if={@riddle.difficulty}
            class="inline-flex items-center rounded-md bg-yellow-50 px-2 py-1 text-xs font-medium text-yellow-800 ring-1 ring-inset ring-yellow-600/20"
          >
            {@riddle.difficulty}
          </span>
          <span
            :if={@game_completed}
            class="inline-flex items-center rounded-md bg-gray-100 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"
          >
            Game Over
          </span>
        </div>
        <h1 id="riddle-name" class="text-3xl font-bold text-gray-900">{@riddle.name}</h1>
      </div>

      <div
        id="riddle-description"
        class="bg-white rounded-2xl shadow-sm border border-gray-100 p-8 mb-6"
      >
        <p class="text-lg text-gray-700 text-center">{@riddle.description}</p>
      </div>

      <%!-- Correct answer result --%>
      <div
        :if={match?({:correct, _, _}, @submission_state)}
        id="correct-result"
        class="bg-green-50 border border-green-200 rounded-2xl p-6 mb-6 text-center"
      >
        <p class="text-2xl font-bold text-green-700 mb-1">Correct!</p>
        <p class="text-green-600">
          {placement_text(elem(@submission_state, 1))} place &mdash; +{elem(@submission_state, 2)} points
        </p>
      </div>

      <%!-- Answer submission form (hidden once solved or game over) --%>
      <div :if={not @already_solved and not @game_completed} id="answer-form-container">
        <form id="answer-form" phx-submit="submit_answer" class="flex gap-3">
          <input
            id="answer-input"
            type="text"
            name="answer"
            placeholder="Your answer..."
            autocomplete="off"
            class="flex-1 rounded-xl border border-gray-300 px-4 py-3 text-gray-900 shadow-sm focus:border-blue-500 focus:ring-2 focus:ring-blue-500 focus:outline-none"
          />
          <button
            type="submit"
            class="rounded-xl bg-blue-600 px-6 py-3 text-sm font-semibold text-white shadow-sm hover:bg-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            Submit
          </button>
        </form>

        <%!-- Feedback messages --%>
        <div :if={@submission_state == :incorrect} id="incorrect-feedback" class="mt-4">
          <p class="text-sm text-red-600 font-medium">{@try_again_message}</p>
        </div>
        <div
          :if={match?({:error, _}, @submission_state)}
          id="error-feedback"
          class="mt-4"
        >
          <p class="text-sm text-yellow-600 font-medium">{elem(@submission_state, 1)}</p>
        </div>
      </div>

      <%!-- Game over state (user didn't solve it) --%>
      <div
        :if={@game_completed and not @already_solved}
        id="game-over"
        class="bg-gray-50 border border-gray-200 rounded-2xl p-8 text-center"
      >
        <p class="text-xl font-semibold text-gray-700">Time's up!</p>
        <p class="text-gray-500 mt-1">Better luck next time.</p>
      </div>
    </div>
    """
  end

  defp check_not_banned(%{account_status: :banned}), do: {:error, :banned}
  defp check_not_banned(_user), do: :ok

  defp check_game_live(%{play_status: "live"}), do: :ok
  defp check_game_live(%{play_status: status}), do: {:error, {:not_live, status}}

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
end
