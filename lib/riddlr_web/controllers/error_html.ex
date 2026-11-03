defmodule RiddlrWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  Every error gets a full page in the app's own look: the root layout, the
  topbar and a riddle in place of an error message. A 404 gets
  `not_found.html.heex`; any other status gets `crisis.html.heex`.

  A 500 may come from a broken layout, so the page renders in full here and
  falls back to the plain status message if that render fails.

  See config/config.exs.
  """
  use RiddlrWeb, :html

  require Logger

  alias RiddlrWeb.{GameCopy, Theme}

  embed_templates "error_html/*"

  @doc """
  Renders an error page: `not_found.html.heex` for a 404,
  `crisis.html.heex` for anything else, each inside the root layout. If the
  page fails to render, it renders the status message instead, e.g.
  "Internal Server Error".
  """
  @spec render(String.t(), map()) :: Phoenix.HTML.safe() | String.t()
  def render("404.html", assigns) do
    page(assigns, GameCopy.Errors.not_found_title(), &not_found/1, "404.html")
  end

  def render(template, assigns) do
    page(assigns, GameCopy.Errors.crisis_title(), &crisis/1, template)
  end

  # Renders to iodata right here rather than handing back a lazy template, so
  # a failure in the layout lands in this rescue and not in the endpoint.
  @spec page(map(), String.t(), (map() -> Phoenix.LiveView.Rendered.t()), String.t()) ::
          Phoenix.HTML.safe() | String.t()
  defp page(assigns, title, body, template) do
    assigns = page_assigns(assigns, title)

    {:safe,
     assigns
     |> Map.put(:inner_content, body.(assigns))
     |> Layouts.root()
     |> Phoenix.HTML.Safe.to_iodata()}
  rescue
    exception ->
      Logger.error("Error page failed to render: " <> Exception.message(exception))
      Phoenix.Controller.status_message_from_template(template)
  end

  # The browser pipeline sets the theme, scope and flash. The catch-all route
  # runs it for unknown pages, but an error raised before the pipeline (a bad
  # method, say) arrives without them, so fall back to a guest in light mode.
  @spec page_assigns(map(), String.t()) :: map()
  defp page_assigns(assigns, title) do
    theme = if assigns[:theme] in Theme.themes(), do: assigns.theme, else: "light"

    assigns
    |> Map.put(:theme, theme)
    |> Map.put(:current_scope, assigns[:current_scope])
    |> Map.put(:flash, assigns[:flash] || %{})
    |> Map.put(:page_title, title)
  end

  @doc """
  The body both error pages share: a doodle, a riddle as the heading, an
  optional line under it and a link back to Home, all centred.
  """
  attr :id, :string, required: true
  attr :riddle, :string, required: true
  attr :tail, :string, default: nil, doc: "a line under the riddle"
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :theme, :string, required: true
  slot :doodle, required: true, doc: "an `rg-doodle` SVG above the riddle"

  @spec error_page(map()) :: Phoenix.LiveView.Rendered.t()
  def error_page(assigns) do
    ~H"""
    <Layouts.game flash={@flash} current_scope={@current_scope} theme={@theme}>
      <section id={@id} class="rg-view rg-lost" aria-labelledby={"#{@id}-h"}>
        {render_slot(@doodle)}
        <h1 id={"#{@id}-h"} class="rg-lost__riddle" tabindex="-1">{@riddle}</h1>
        <p :if={@tail} class="rg-lost__tail">{@tail}</p>
        <.link navigate={~p"/"} class="rg-link-btn">{GameCopy.Errors.not_found_home()}</.link>
      </section>
    </Layouts.game>
    """
  end
end
