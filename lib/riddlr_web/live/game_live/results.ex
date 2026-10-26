defmodule RiddlrWeb.GameLive.Results do
  @moduledoc """
  Shows a finished riddle: who solved it, the leaderboard, and a chat that
  follows the riddle's answers. Works for completed and archived riddles: the
  board comes from saved solves, but archive drops the answers, so an archived
  riddle shows an empty feed. Opening it for a riddle in any other state sends
  the player to the screen for that state.

  A card under the board points to the next riddle (`Games.next_riddle/0`)
  and follows its state while the page is open. A `scheduled` riddle gets no
  button: its Lobby does not open until the riddle is `ready`.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{Games, Gameplay}
  alias Riddlr.Gameplay.Answer
  alias RiddlrWeb.{GameComponents, GameCopy}
  alias RiddlrWeb.GameLive.Feed

  import Riddlr.Utils.User

  @message_max_length 500
  # Guesses loaded at mount, and rows kept in the feed once chat joins them.
  @log_limit 100
  @feed_limit 200

  # The feed shows the riddle's answers and then the chat, so it needs a row
  # that marks where the race stopped. A stream can't add a row at render
  # time, so the divider is an item in the stream.
  @round_ended %{id: "round-ended", divider: true}

  # Each of these can change which riddle is next, or its state. Completed is
  # here so a live next riddle drops off the card when it ends.
  @next_topics ~w(games:riddle:scheduled games:riddle:ready games:riddle:live games:riddle:completed)
  @next_messages [
    :riddle_scheduled,
    :riddle_rescheduled,
    :riddle_unscheduled,
    :riddle_ready,
    :riddle_live,
    :riddle_completed
  ]

  # One saved solve as the podium, board and payout show it. `username` picks
  # the tile; `shown_as` is the name on screen, "you" for the viewer.
  @typep board_entry :: %{
           placement: pos_integer(),
           points: non_neg_integer(),
           username: String.t(),
           shown_as: String.t(),
           me?: boolean(),
           secs: String.t()
         }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Games.fetch_riddle(id) do
      {:ok, %{play_status: status} = riddle} when status in ["completed", "archived"] ->
        user = socket.assigns.current_user
        # Chat closes at archive. A page opened before then keeps its chat.
        chat_open? = status == "completed"
        board = load_board(riddle.id, user.id)

        feed =
          if connected?(socket) do
            if chat_open?, do: subscribe_to_chat(id)
            Phoenix.PubSub.subscribe(Riddlr.PubSub, "user:#{user.id}")
            Enum.each(@next_topics, &Phoenix.PubSub.subscribe(Riddlr.PubSub, &1))
            load_feed(riddle.id) ++ [@round_ended]
          else
            []
          end

        {:ok,
         socket
         |> assign(:banned, is_banned?(user))
         |> assign(:chat_open?, chat_open?)
         |> assign(:page_title, "Results — #{riddle.name}")
         |> assign(:riddle, riddle)
         |> assign(:answer, List.first(riddle.answers, ""))
         |> assign(:board, board)
         |> assign(:you, you_card(board, riddle.id, user.id))
         |> assign(:payout, payout(board))
         |> assign(:next, Games.next_riddle())
         # Negative: chat joins at the bottom, so the oldest rows drop first.
         |> stream(:answers, feed, limit: -@feed_limit)}

      {:ok, %{play_status: status}} when status in ["closed", "scheduled", "ready"] ->
        {:ok, push_navigate(socket, to: ~p"/game/#{id}/lobby")}

      {:ok, %{play_status: "live"}} ->
        {:ok, push_navigate(socket, to: ~p"/game/#{id}/play")}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("send_chat", _params, %{assigns: %{chat_open?: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("send_chat", %{"message" => text}, socket) do
    text = String.trim(text)
    %{current_user: user, riddle: riddle} = socket.assigns

    with :ok <- validate_input(text),
         :ok <- check_not_banned(socket.assigns) do
      Gameplay.broadcast_answer(Answer.new(riddle.id, user, text, chat: true))
      {:noreply, push_event(socket, "chat-sent", %{})}
    else
      {:error, :banned} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your account has been suspended.")
         |> push_navigate(to: ~p"/")}

      {:error, :empty_message} ->
        {:noreply, push_event(socket, "chat-empty", %{})}

      # The post-game screen has no place to show an error, so an over-long
      # message is dropped.
      {:error, :message_too_long} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:answer_submitted, answer}, socket) do
    {:noreply, stream_insert(socket, :answers, answer, limit: -@feed_limit)}
  end

  def handle_info({:answer_flagged, answer_id}, socket) do
    {:noreply, stream_delete(socket, :answers, %{id: answer_id})}
  end

  def handle_info({:riddle_archived, riddle}, socket) do
    if riddle.id == socket.assigns.riddle.id do
      {:noreply, put_flash(socket, :info, "This game has been archived.")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({message, _riddle}, socket) when message in @next_messages do
    {:noreply, assign(socket, :next, Games.next_riddle())}
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

  @spec subscribe_to_chat(String.t()) :: :ok | {:error, term()}
  defp subscribe_to_chat(riddle_id) do
    Phoenix.PubSub.subscribe(Riddlr.PubSub, "games:riddle:archived")
    Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(riddle_id))
    Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.flagged_topic(riddle_id))
  end

  @spec check_not_banned(map()) :: :ok | {:error, :banned}
  defp check_not_banned(%{banned: true}), do: {:error, :banned}
  defp check_not_banned(_assigns), do: :ok

  # Every feed item is an answer except the round-ended divider.
  @spec divider?(map()) :: boolean()
  defp divider?(item), do: Map.get(item, :divider, false)

  @spec validate_input(String.t()) :: :ok | {:error, :empty_message | :message_too_long}
  defp validate_input(text) do
    cond do
      text == "" -> {:error, :empty_message}
      String.length(text) > @message_max_length -> {:error, :message_too_long}
      true -> :ok
    end
  end

  # The riddle's last @log_limit answers from ETS, oldest first. Play masks correct
  # answers (Answer.for_live_feed/1) while the race runs. The race is over, so
  # they show in full here. Offsets go: they only mean something next to a
  # running timer.
  @spec load_feed(integer()) :: [Answer.t()]
  defp load_feed(riddle_id) do
    riddle_id
    |> Gameplay.get_answers()
    |> Enum.take(@log_limit)
    |> Enum.reverse()
    |> Feed.put_usernames()
    |> Enum.map(&%{&1 | offset_ms: nil})
  end

  # The viewer's card. Joining means guessing while the riddle was live; ETS
  # knows that until archive, after which only solvers count as joined.
  @spec you_card([board_entry()], integer(), integer()) :: GameCopy.you_card()
  defp you_card(board, riddle_id, user_id) do
    mine = Enum.find(board, & &1.me?)
    GameCopy.you_card(mine, mine != nil or Gameplay.guessed?(riddle_id, user_id))
  end

  # One cell per scoring place: its points and the solver who took it, if any.
  @spec payout([board_entry()]) :: [
          %{place: pos_integer(), points: pos_integer(), solver: board_entry() | nil}
        ]
  defp payout(board) do
    by_place = Map.new(board, &{&1.placement, &1})

    Gameplay.points_table()
    |> Enum.with_index(1)
    |> Enum.map(fn {points, place} ->
      %{place: place, points: points, solver: Map.get(by_place, place)}
    end)
  end

  # Every saved solve, by placement. A deleted account shows as "Player", as
  # on the feed.
  @spec load_board(integer(), integer()) :: [board_entry()]
  defp load_board(riddle_id, user_id) do
    riddle_id
    |> Gameplay.list_solves()
    |> Enum.map(fn solve ->
      me? = solve.user_id == user_id
      username = if(solve.user, do: solve.user.username, else: "Player")

      %{
        placement: solve.placement,
        points: solve.points,
        username: username,
        shown_as: if(me?, do: GameCopy.room_you(), else: username),
        me?: me?,
        secs: GameCopy.solve_secs(solve.solve_time_ms)
      }
    end)
  end
end
