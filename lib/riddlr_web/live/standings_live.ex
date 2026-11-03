defmodule RiddlrWeb.StandingsLive do
  @moduledoc """
  The public Standings page: the overall ranking of players across riddles
  (`Riddlr.Standings.list/2`): rank, player, points, wins and podiums, or
  on the Fastest board rank, player, best time and its riddle, linked to
  that riddle's Results.

  Two URL params pick what it shows, each with a switch on the page that
  patches between values and keeps the other param:

  - `?board=points` (default), `wins`, `podiums` or `fastest`: the stat it
    ranks by
  - `?window=all_time` (default) or `month`: which riddles count

  Any other value falls back to the default.

  It reloads the board and pinned row when a riddle completes
  (`Riddlr.Standings.subscribe/0`).

  A signed-in player's own row is marked. When they are on the board but
  outside the top 50, their row (`Riddlr.Standings.player_row/3`) is pinned
  below the list with its true rank.

  A "How are these counted?" link below opens a note on how each board is
  counted, how ties break, and what This month covers.

  Anyone can open it, signed in or not. With no solves in the window it
  shows an empty note instead of the board.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.Standings
  alias RiddlrWeb.{GameComponents, GameCopy}

  @boards [:points, :wins, :podiums, :fastest]
  @windows [:all_time, :month]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Standings.subscribe()

    {:ok,
     socket
     |> assign(:page_title, GameCopy.Standings.standings_heading())
     |> assign(boards: @boards, windows: @windows)
     |> stream_configure(:rows, dom_id: &"standings-#{&1.user_id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(board: parse_board(params["board"]), window: parse_window(params["window"]))
     |> load_board()}
  end

  @impl true
  def handle_info(:standings_changed, socket), do: {:noreply, load_board(socket)}

  # Reads the current board and window, and the viewer's pinned row.
  @spec load_board(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_board(socket) do
    %{board: board, window: window, current_scope: scope} = socket.assigns
    rows = Standings.list(board, window)

    socket
    |> assign(:pinned, pinned_row(rows, scope, board, window))
    # A stream can't say whether it is empty, so the empty note reads this.
    |> assign(:empty?, rows == [])
    |> stream(:rows, rows, reset: true)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.game flash={@flash} current_scope={@current_scope} theme={@theme}>
      <section class="rg-view" aria-labelledby="standings-h">
        <div class="rg-wrap rg-standings">
          <section class="rg-panel rg-stand-note">
            <GameComponents.trophy class="rg-stand__trophy" />
            <div class="rg-stand__head">
              <.laurel />
              <h1 id="standings-h" class="rg-panel__h" tabindex="-1">
                {GameCopy.Standings.standings_heading()}
              </h1>
              <.laurel flip />
            </div>
            <nav class="rg-stand__switch" aria-label={GameCopy.Standings.standings_board_label()}>
              <.link
                :for={board <- @boards}
                id={"standings-board-#{board}"}
                patch={~p"/standings?#{[board: board, window: @window]}"}
                class="rg-tab rg-tab--sm"
                aria-current={if board == @board, do: "page"}
              >
                {GameCopy.Standings.standings_board(board)}
              </.link>
            </nav>
            <nav class="rg-stand__switch" aria-label={GameCopy.Standings.standings_window_label()}>
              <.link
                :for={window <- @windows}
                id={"standings-window-#{window}"}
                patch={~p"/standings?#{[board: @board, window: window]}"}
                class="rg-tab rg-tab--sm rg-tab--sub"
                aria-current={if window == @window, do: "page"}
              >
                {GameCopy.Standings.standings_window(window)}
              </.link>
            </nav>
            <p :if={@empty?} id="standings-empty" class="rg-board__empty">
              {GameCopy.Standings.standings_empty(@window)}
            </p>
            <table :if={!@empty?} id="standings-board" class="rg-stand">
              <thead>
                <tr>
                  <th scope="col" class="rg-stand__rank">
                    {GameCopy.Standings.standings_col(:rank)}
                  </th>
                  <th scope="col" class="rg-stand__player">
                    {GameCopy.Standings.standings_col(:player)}
                  </th>
                  <%= if @board == :fastest do %>
                    <th scope="col" class="rg-stand__time" aria-sort="ascending">
                      {GameCopy.Standings.standings_col(:time)}
                    </th>
                    <th scope="col" class="rg-stand__riddle">
                      {GameCopy.Standings.standings_col(:riddle)}
                    </th>
                  <% else %>
                    <th scope="col" class="rg-stand__pts" aria-sort={aria_sort(@board, :points)}>
                      {GameCopy.Standings.standings_col(:points)}
                    </th>
                    <th scope="col" class="rg-stand__wins" aria-sort={aria_sort(@board, :wins)}>
                      {GameCopy.Standings.standings_col(:wins)}
                    </th>
                    <th scope="col" class="rg-stand__pods" aria-sort={aria_sort(@board, :podiums)}>
                      {GameCopy.Standings.standings_col(:podiums)}
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody id="standings-rows" phx-update="stream">
                <.board_row
                  :for={{dom_id, row} <- @streams.rows}
                  id={dom_id}
                  row={row}
                  board={@board}
                  viewer={viewer_name(@current_scope)}
                  you?={you?(row, @current_scope)}
                />
              </tbody>
              <tbody :if={@pinned} class="rg-stand__pinned">
                <.board_row
                  id="standings-you"
                  row={@pinned}
                  board={@board}
                  viewer={viewer_name(@current_scope)}
                  you?
                />
              </tbody>
            </table>
            <details id="standings-how" class="rg-stand__how">
              <summary class="rg-link-btn">{GameCopy.Standings.standings_how_link()}</summary>
              <dl class="rg-stand__how-list">
                <div :for={board <- @boards} id={"standings-how-#{board}"}>
                  <dt>{GameCopy.Standings.standings_board(board)}</dt>
                  <dd>{GameCopy.Standings.standings_how(board)}</dd>
                </div>
              </dl>
              <p>{GameCopy.Standings.standings_how_ties()}</p>
              <p>{GameCopy.Standings.standings_how_month()}</p>
            </details>
          </section>
        </div>
      </section>
    </Layouts.game>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :board, :atom, required: true
  attr :viewer, :string, default: nil, doc: "the viewer's username, for the tile tone"
  attr :you?, :boolean, default: false, doc: "true on the viewer's own row"

  # One player's line. The viewer's own row carries aria-current.
  defp board_row(assigns) do
    ~H"""
    <tr id={@id} class={@you? && "rg-stand__you"} aria-current={@you? && "true"}>
      <td class="rg-stand__rank">
        <.medal :if={@row.rank <= 3} place={@row.rank} />{@row.rank}
      </td>
      <th scope="row" class="rg-stand__player">
        <span class="rg-stand__who">
          <GameComponents.tile
            initial={GameComponents.initial(@row.username)}
            tone={GameComponents.tone(@row.username, @viewer)}
            size="sm"
          />
          <span class="rg-stand__name">{@row.username}</span>
        </span>
      </th>
      <%= if @board == :fastest do %>
        <td class="rg-stand__time">{GameCopy.solve_secs(@row.solve_time_ms)}</td>
        <td class="rg-stand__riddle">
          <.link navigate={~p"/game/#{@row.riddle_id}/results"} class="rg-link-btn rg-stand__link">
            {GameCopy.riddle_name(%{number: @row.riddle_number, name: @row.riddle_name})}
          </.link>
        </td>
      <% else %>
        <td class="rg-stand__pts">{@row.points}</td>
        <td class="rg-stand__wins">{@row.wins}</td>
        <td class="rg-stand__pods">{@row.podiums}</td>
      <% end %>
    </tr>
    """
  end

  attr :place, :integer, required: true, doc: "1, 2 or 3"

  # A gold, silver or bronze medal hung beside a top-three rank. It pokes
  # past the note's left edge. Players level on a rank share a medal.
  defp medal(assigns) do
    ~H"""
    <svg
      class={"rg-stand__medal rg-stand__medal--#{@place}"}
      viewBox="0 0 40 54"
      aria-hidden="true"
    >
      <path class="rg-stand__ribbon" d="M9 2 L18 2 L23 22 L15.5 24 Z" />
      <path class="rg-stand__ribbon" d="M31 2 L22.5 2 L17 22 L24.5 24 Z" />
      <path
        class="rg-stand__disc"
        d="M20.5 22.5 C28.5 22 34 27.5 33.5 35.5 C33 43 27.5 48 20 47.5 C12.5 47 7 41.5 7.5 34.5 C8 27 13 23 20.5 22.5 Z"
      />
      <path
        class="rg-stand__disc-ring"
        d="M20 27.5 C25.5 27.5 28.5 31 28.5 35.5 C28 40 24.5 43 20 42.5"
      />
      <path
        class="rg-stand__star"
        d="M20 29.5 L21.9 33.4 L26 33.9 L23 36.7 L23.8 40.8 L20 38.8 L16.2 40.8 L17 36.7 L14 33.9 L18.1 33.4 Z"
      />
    </svg>
    """
  end

  attr :flip, :boolean, default: false, doc: "mirror it for the right of the heading"

  # A laurel sprig, one each side of the heading.
  defp laurel(assigns) do
    ~H"""
    <svg
      class={["rg-doodle rg-stand__laurel", @flip && "rg-stand__laurel--flip"]}
      viewBox="0 0 40 56"
      aria-hidden="true"
    >
      <path d="M30 52 C14 46 8 30 14 6" />
      <path class="rg-stand__leaf" d="M13 12 C7 10 6 5 8 2 C12 4 14 8 13 12 Z" />
      <path class="rg-stand__leaf" d="M14 13 C19 10 23 11 24 15 C20 17 16 16 14 13 Z" />
      <path class="rg-stand__leaf" d="M11 22 C5 21 3 16 4 12 C9 14 11 18 11 22 Z" />
      <path class="rg-stand__leaf" d="M12 24 C17 21 21 22 22 26 C18 28 14 27 12 24 Z" />
      <path class="rg-stand__leaf" d="M12 33 C6 33 3 29 3 25 C8 26 11 29 12 33 Z" />
      <path class="rg-stand__leaf" d="M14 35 C19 33 23 35 23 39 C19 40 16 38 14 35 Z" />
      <path class="rg-stand__leaf" d="M18 43 C12 44 8 41 7 37 C12 37 16 39 18 43 Z" />
      <path class="rg-stand__leaf" d="M22 46 C26 43 30 44 32 47 C28 50 24 49 22 46 Z" />
    </svg>
    """
  end

  # The viewer's row when they are on the board but outside the top 50, so
  # it can be pinned below the list. Nil when signed out, off the board, or
  # already listed.
  @spec pinned_row(
          [Standings.row()],
          Riddlr.Accounts.Scope.t() | nil,
          Standings.board(),
          Standings.window()
        ) ::
          Standings.row() | nil
  defp pinned_row(_rows, nil, _board, _window), do: nil

  defp pinned_row(rows, %{user: user}, board, window) do
    if Enum.any?(rows, &(&1.user_id == user.id)),
      do: nil,
      else: Standings.player_row(user.id, board, window)
  end

  @spec you?(Standings.row(), Riddlr.Accounts.Scope.t() | nil) :: boolean()
  defp you?(_row, nil), do: false
  defp you?(row, %{user: user}), do: row.user_id == user.id

  # Anything but a known board falls back to points.
  @spec parse_board(String.t() | nil) :: Standings.board()
  defp parse_board("wins"), do: :wins
  defp parse_board("podiums"), do: :podiums
  defp parse_board("fastest"), do: :fastest
  defp parse_board(_), do: :points

  # Marks the column the board ranks by, for screen readers.
  @spec aria_sort(Standings.board(), Standings.board()) :: String.t() | nil
  defp aria_sort(board, board), do: "descending"
  defp aria_sort(_board, _col), do: nil

  # Anything but a known window falls back to all-time.
  @spec parse_window(String.t() | nil) :: Standings.window()
  defp parse_window("month"), do: :month
  defp parse_window(_), do: :all_time

  # The viewer's username, so their own tile gets the "you" tone.
  @spec viewer_name(Riddlr.Accounts.Scope.t() | nil) :: String.t() | nil
  defp viewer_name(nil), do: nil
  defp viewer_name(%{user: user}), do: user.username
end
