defmodule RiddlrWeb.StandingsLive do
  @moduledoc """
  The public Standings page: the overall ranking of players across riddles
  (`Riddlr.Standings.list/2`). For now it shows the all-time Points board:
  rank, player, points, wins and podiums.

  Anyone can open it, signed in or not. With no solves yet it shows an empty
  note instead of the board.
  """

  use RiddlrWeb, :live_view

  alias Riddlr.Standings
  alias RiddlrWeb.{GameComponents, GameCopy}

  @impl true
  def mount(_params, _session, socket) do
    rows = Standings.list(:points, :all_time)

    {:ok,
     socket
     |> assign(:page_title, GameCopy.standings_heading())
     # A stream can't say whether it is empty, so the empty note reads this.
     |> assign(:empty?, rows == [])
     |> stream_configure(:rows, dom_id: &"standings-#{&1.user_id}")
     |> stream(:rows, rows)}
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
            <p :if={@empty?} id="standings-empty" class="rg-board__empty">
              {GameCopy.standings_empty()}
            </p>
            <table :if={!@empty?} id="standings-board" class="rg-stand">
              <thead>
                <tr>
                  <th scope="col" class="rg-stand__rank">{GameCopy.standings_col(:rank)}</th>
                  <th scope="col" class="rg-stand__player">{GameCopy.standings_col(:player)}</th>
                  <th scope="col" class="rg-stand__pts">{GameCopy.standings_col(:points)}</th>
                  <th scope="col" class="rg-stand__wins">{GameCopy.standings_col(:wins)}</th>
                  <th scope="col" class="rg-stand__pods">{GameCopy.standings_col(:podiums)}</th>
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
                  <td class="rg-stand__pts">{row.points}</td>
                  <td class="rg-stand__wins">{row.wins}</td>
                  <td class="rg-stand__pods">{row.podiums}</td>
                </tr>
              </tbody>
            </table>
          </section>
        </div>
      </section>
    </Layouts.game>
    """
  end

  # The viewer's username, so their own tile gets the "you" tone.
  @spec viewer_name(Riddlr.Accounts.User.t() | nil) :: String.t() | nil
  defp viewer_name(nil), do: nil
  defp viewer_name(user), do: user.username
end
