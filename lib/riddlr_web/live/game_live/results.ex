defmodule RiddlrWeb.GameLive.Results do
  @moduledoc """
  Shows a finished riddle: who solved it, the leaderboard, and a chat that
  follows the riddle's answers. Works for completed and archived riddles: the
  board comes from saved solves, but archive drops the answers, so an archived
  riddle shows an empty feed. Opening it for a riddle in any other state sends
  the player to the screen for that state.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.{Games, Gameplay}
  alias Riddlr.Gameplay.Answer
  alias RiddlrWeb.GameLive.Feed

  import Riddlr.Utils.User

  @message_max_length 500

  # The feed shows the riddle's answers and then the chat, so it needs a row
  # that marks where the race stopped. A stream can't add a row at render
  # time, so the divider is an item in the stream.
  @round_ended %{id: "round-ended", divider: true}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Games.fetch_riddle(id) do
      {:ok, %{play_status: status} = riddle} when status in ["completed", "archived"] ->
        user = socket.assigns.current_user
        # Chat closes at archive. A page opened before then keeps its chat.
        chat_open? = status == "completed"

        feed =
          if connected?(socket) do
            if chat_open?, do: subscribe_to_chat(id)
            Phoenix.PubSub.subscribe(Riddlr.PubSub, "user:#{user.id}")
            [@round_ended | load_feed(riddle.id)]
          else
            []
          end

        {:ok,
         socket
         |> assign(:banned, is_banned?(user))
         |> assign(:chat_open?, chat_open?)
         |> assign(:page_title, "Results — #{riddle.name}")
         |> assign(:riddle, riddle)
         |> assign(:top_solvers, load_board(riddle.id))
         |> assign(:active_tab, :leaderboard)
         |> stream(:answers, feed, limit: 100)}

      {:ok, %{play_status: status}} when status in ["closed", "scheduled", "ready"] ->
        {:ok, push_navigate(socket, to: ~p"/game/#{id}/lobby")}

      {:ok, %{play_status: "live"}} ->
        {:ok, push_navigate(socket, to: ~p"/game/#{id}/play")}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

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

      # The post-game screen has no place to show an error yet, so an empty or
      # over-long message is dropped.
      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:answer_submitted, answer}, socket) do
    {:noreply, stream_insert(socket, :answers, answer, at: 0)}
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

  # The riddle's answers from ETS, newest first. Play masks correct answers
  # (Answer.for_live_feed/1) while the race runs. The race is over, so they
  # show in full here. Offsets go: they only mean something next to a
  # running timer.
  @spec load_feed(integer()) :: [Answer.t()]
  defp load_feed(riddle_id) do
    riddle_id
    |> Gameplay.get_answers()
    |> Enum.take(100)
    |> Feed.put_usernames()
    |> Enum.map(&%{&1 | offset_ms: nil})
  end

  # Every saved solve, shaped for `game_leaderboard/1`. A deleted account
  # shows as "Player", as on the feed.
  @spec load_board(integer()) :: [map()]
  defp load_board(riddle_id) do
    riddle_id
    |> Gameplay.list_solves()
    |> Enum.map(fn solve ->
      %{
        placement: solve.placement,
        points: solve.points,
        username: if(solve.user, do: solve.user.username, else: "Player"),
        solve_time_display:
          solve.solve_time_ms && Feed.format_time(div(solve.solve_time_ms, 1000))
      }
    end)
  end
end
