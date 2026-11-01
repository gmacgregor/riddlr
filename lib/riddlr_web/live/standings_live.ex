defmodule RiddlrWeb.StandingsLive do
  @moduledoc """
  The public Standings page: the overall ranking of players across riddles
  (`Riddlr.Standings.list/2`): rank, player, points, wins and podiums, or
  on the Fastest board rank, player, best time and its riddle. Every board
  ends with the solve rate.

  Two URL params pick what it shows, each with a switch on the page that
  patches between values and keeps the other param:

  - `?board=points` (default), `wins`, `podiums` or `fastest`: the stat it
    ranks by
  - `?window=all_time` (default) or `month`: which riddles count

  Any other value falls back to the default.

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
    {:ok,
     socket
     |> assign(:page_title, GameCopy.standings_heading())
     |> assign(boards: @boards, windows: @windows)
     |> stream_configure(:rows, dom_id: &"standings-#{&1.user_id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    board = parse_board(params["board"])
    window = parse_window(params["window"])
    rows = Standings.list(board, window)

    {:noreply,
     socket
     |> assign(board: board, window: window)
     # A stream can't say whether it is empty, so the empty note reads this.
     |> assign(:empty?, rows == [])
     |> stream(:rows, rows, reset: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.game flash={@flash} current_scope={@current_scope} theme={@theme}>
      <section class="rg-view" aria-labelledby="standings-h">
        <div class="rg-wrap rg-standings">
          <section class="rg-panel">
            <h1 id="standings-h" class="rg-panel__h" tabindex="-1">
              {GameCopy.standings_heading()}
            </h1>
            <nav class="rg-stand__switch" aria-label={GameCopy.standings_board_label()}>
              <.link
                :for={board <- @boards}
                id={"standings-board-#{board}"}
                patch={~p"/standings?#{[board: board, window: @window]}"}
                class="rg-tab rg-tab--sm"
                aria-current={if board == @board, do: "page"}
              >
                {GameCopy.standings_board(board)}
              </.link>
            </nav>
            <nav class="rg-stand__switch" aria-label={GameCopy.standings_window_label()}>
              <.link
                :for={window <- @windows}
                id={"standings-window-#{window}"}
                patch={~p"/standings?#{[board: @board, window: window]}"}
                class="rg-tab rg-tab--sm"
                aria-current={if window == @window, do: "page"}
              >
                {GameCopy.standings_window(window)}
              </.link>
            </nav>
            <p :if={@empty?} id="standings-empty" class="rg-board__empty">
              {GameCopy.standings_empty(@window)}
            </p>
            <table :if={!@empty?} id="standings-board" class="rg-stand">
              <thead>
                <tr>
                  <th scope="col" class="rg-stand__rank">{GameCopy.standings_col(:rank)}</th>
                  <th scope="col" class="rg-stand__player">{GameCopy.standings_col(:player)}</th>
                  <%= if @board == :fastest do %>
                    <th scope="col" class="rg-stand__time" aria-sort="ascending">
                      {GameCopy.standings_col(:time)}
                    </th>
                    <th scope="col" class="rg-stand__riddle">{GameCopy.standings_col(:riddle)}</th>
                  <% else %>
                    <th scope="col" class="rg-stand__pts" aria-sort={aria_sort(@board, :points)}>
                      {GameCopy.standings_col(:points)}
                    </th>
                    <th scope="col" class="rg-stand__wins" aria-sort={aria_sort(@board, :wins)}>
                      {GameCopy.standings_col(:wins)}
                    </th>
                    <th scope="col" class="rg-stand__pods" aria-sort={aria_sort(@board, :podiums)}>
                      {GameCopy.standings_col(:podiums)}
                    </th>
                  <% end %>
                  <th scope="col" class="rg-stand__rate">{GameCopy.standings_col(:rate)}</th>
                </tr>
              </thead>
              <tbody id="standings-rows" phx-update="stream">
                <tr :for={{dom_id, row} <- @streams.rows} id={dom_id}>
                  <td class="rg-stand__rank">{row.rank}</td>
                  <th scope="row" class="rg-stand__player">
                    <span class="rg-stand__who">
                      <GameComponents.tile
                        initial={GameComponents.initial(row.username)}
                        tone={GameComponents.tone(row.username, viewer_name(@current_user))}
                        size="sm"
                      />
                      <span class="rg-stand__name">{row.username}</span>
                    </span>
                  </th>
                  <%= if @board == :fastest do %>
                    <td class="rg-stand__time">{GameCopy.solve_secs(row.solve_time_ms)}</td>
                    <td class="rg-stand__riddle">
                      {GameCopy.riddle_name(%{number: row.riddle_number, name: row.riddle_name})}
                    </td>
                  <% else %>
                    <td class="rg-stand__pts">{row.points}</td>
                    <td class="rg-stand__wins">{row.wins}</td>
                    <td class="rg-stand__pods">{row.podiums}</td>
                  <% end %>
                  <td class="rg-stand__rate">{GameCopy.standings_rate(row.solves, row.entries)}</td>
                </tr>
              </tbody>
            </table>
          </section>
        </div>
      </section>
    </Layouts.game>
    """
  end

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
  @spec viewer_name(Riddlr.Accounts.User.t() | nil) :: String.t() | nil
  defp viewer_name(nil), do: nil
  defp viewer_name(user), do: user.username
end
