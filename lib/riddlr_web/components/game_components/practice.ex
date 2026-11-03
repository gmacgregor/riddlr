defmodule RiddlrWeb.GameComponents.Practice do
  @moduledoc """
  The practice riddle note Home shows while nothing is scheduled.

  It renders the `rg-` markup styled by `assets/css/game.css`.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias RiddlrWeb.GameCopy

  @doc """
  The "While you wait" note on Home when nothing is scheduled: a practice
  riddle with its answer hidden as blank tiles.

  The answer letters are in the DOM; a practice riddle scores nothing, so
  that is fine. "Peek at the answer" toggles all on the client with `JS`
  commands, which LiveView keeps across patches:

    * `is-open` on the tiles, which CSS reads to show the letters
    * `aria-expanded` on the button, which CSS reads to swap its text
    * `hidden` on the two lines of the polite status, so a screen reader
      hears the answer, or its letter count once hidden again

  `riddle` is any map with a `description` and an `answer`. `n` and `total`
  give its place in the set ("Practice riddle N of M").

  With `on_another` set and more than one riddle in the set, an "Another
  riddle" button closes the answer and pushes that event to the server.
  """
  attr :id, :string, required: true
  attr :riddle, :map, required: true, doc: "a map with `description` and `answer`"
  attr :n, :integer, required: true
  attr :total, :integer, required: true
  attr :on_another, :string, default: nil, doc: "the event \"Another riddle\" pushes"
  attr :rest, :global

  @spec practice_note(map()) :: Phoenix.LiveView.Rendered.t()
  def practice_note(assigns) do
    assigns =
      assign(assigns, :chars, assigns.riddle.answer |> String.upcase() |> String.graphemes())

    ~H"""
    <section id={@id} class="rg-peek" aria-labelledby={"#{@id}-h"} {@rest}>
      <div class="rg-peek__head">
        <h3 id={"#{@id}-h"} class="rg-peek__h">{GameCopy.Home.practice_heading()}</h3>
        <span class="rg-peek__tag">{GameCopy.Home.practice_tag(@n, @total)}</span>
      </div>
      <p class="rg-peek__q">“{@riddle.description}”</p>
      <div id={"#{@id}-answer"} class="rg-peek__a">
        <%= for char <- @chars do %>
          <span :if={char == " "} class="rg-pk-gap" aria-hidden="true"></span>
          <span :if={char != " "} class="rg-pk" aria-hidden="true">
            <span>{char}</span>
          </span>
        <% end %>
      </div>
      <span class="rg-sr-only" role="status">
        <span id={"#{@id}-sr-hidden"}>{GameCopy.Home.practice_status_hidden(@riddle.answer)}</span>
        <span id={"#{@id}-sr-shown"} hidden>{GameCopy.Home.practice_status_shown(@riddle.answer)}</span>
      </span>
      <div class="rg-peek__bar">
        <button
          id={"#{@id}-peek"}
          type="button"
          class="rg-btn rg-peek__btn"
          aria-expanded="false"
          aria-controls={"#{@id}-answer"}
          phx-click={
            JS.toggle_class("is-open", to: "##{@id}-answer")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
            |> JS.toggle_attribute({"hidden", ""}, to: "##{@id}-sr-hidden")
            |> JS.toggle_attribute({"hidden", ""}, to: "##{@id}-sr-shown")
          }
        >
          <span class="rg-peek__show">{GameCopy.Home.practice_peek()}</span>
          <span class="rg-peek__hide">{GameCopy.Home.practice_hide()}</span>
        </button>
        <button
          :if={@on_another && @total > 1}
          type="button"
          class="rg-btn rg-peek__btn rg-peek__next"
          phx-click={close_practice(@id) |> JS.push(@on_another)}
        >
          {GameCopy.Home.practice_another()}
        </button>
        <p :if={GameCopy.Home.practice_note() != ""} class="rg-peek__note">
          {GameCopy.Home.practice_note()}
        </p>
      </div>
    </section>
    """
  end

  # The peek toggle's JS commands stick across patches, so the next riddle
  # would arrive with its answer showing. Close it before asking for one.
  @spec close_practice(String.t()) :: JS.t()
  defp close_practice(id) do
    JS.remove_class("is-open", to: "##{id}-answer")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id}-peek")
    |> JS.remove_attribute("hidden", to: "##{id}-sr-hidden")
    |> JS.set_attribute({"hidden", ""}, to: "##{id}-sr-shown")
  end
end
