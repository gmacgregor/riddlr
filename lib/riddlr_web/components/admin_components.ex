defmodule RiddlrWeb.AdminComponents do
  @moduledoc """
  The UI components the admin uses: button, input, page header, table, flash,
  and the topbar.

  A frozen copy of `RiddlrWeb.CoreComponents` and the `RiddlrWeb.Layouts`
  topbar as they stood before the v9 player redesign (#47). The topbar has
  since moved to match the player one, minus the colour mode switch. The admin gets
  them through `use RiddlrWeb, :admin_live_view` (and the other admin entry
  points) in place of the core ones, so the player components can change
  without moving the admin. They render the `rg-` classes styled by
  `assets/css/admin-base.css` and `assets/css/admin.css`.

  `icon/1`, `show/2`, `hide/2` and `translate_error/1` hold no look of their
  own, so the admin shares them with `RiddlrWeb.CoreComponents`.
  """
  use Phoenix.Component
  use Gettext, backend: RiddlrWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: RiddlrWeb.Endpoint,
    router: RiddlrWeb.Router,
    statics: RiddlrWeb.static_paths()

  import RiddlrWeb.CoreComponents, only: [icon: 1, show: 1, hide: 1, hide: 2, translate_error: 1]

  alias Phoenix.LiveView.JS
  alias RiddlrWeb.GameComponents
  alias RiddlrWeb.GameCopy

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  @spec flash(map()) :: Phoenix.LiveView.Rendered.t()
  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "rg-flash",
        @kind == :info && "rg-flash--info",
        @kind == :error && "rg-flash--error"
      ]}
      {@rest}
    >
      <.icon :if={@kind == :info} name="hero-information-circle" class="rg-flash__icon" />
      <.icon :if={@kind == :error} name="hero-exclamation-circle" class="rg-flash__icon" />
      <div class="rg-flash__body">
        <p :if={@title} class="rg-flash__title">{@title}</p>
        <p>{msg}</p>
      </div>
      <button type="button" class="rg-flash__close" aria-label={gettext("close")}>
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  @spec flash_group(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="rg-flash-group" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "rg-btn--accent", nil => nil}

    assigns =
      assign_new(assigns, :class, fn ->
        ["rg-btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument, which is used to
  get the input name, id, and values. Otherwise pass every attribute.

  Takes every HTML input type, plus `type="select"` for a `<select>` (pass
  `options` and an optional `value`) and `type="textarea"`. `type="checkbox"`
  renders boolean values only.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
      <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  @spec input(map()) :: Phoenix.LiveView.Rendered.t()
  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="rg-field">
      <div class="rg-field__check">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "rg-check"}
          {@rest}
        />
        <label :if={@label} for={@id} class="rg-field__label">{@label}</label>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="rg-field">
      <label :if={@label} for={@id} class="rg-field__label">{@label}</label>
      <select
        id={@id}
        name={@name}
        class={[@class || "rg-input", @errors != [] && (@error_class || "is-invalid")]}
        aria-invalid={@errors != [] && "true"}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="rg-field">
      <label :if={@label} for={@id} class="rg-field__label">{@label}</label>
      <textarea
        id={@id}
        name={@name}
        class={[@class || "rg-input", @errors != [] && (@error_class || "is-invalid")]}
        aria-invalid={@errors != [] && "true"}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Every other type: text, datetime-local, url, password and the rest.
  def input(assigns) do
    ~H"""
    <div class="rg-field">
      <label :if={@label} for={@id} class="rg-field__label">{@label}</label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[@class || "rg-input", @errors != [] && (@error_class || "is-invalid")]}
        aria-invalid={@errors != [] && "true"}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # One error line under an input.
  slot :inner_block, required: true

  @spec error(map()) :: Phoenix.LiveView.Rendered.t()
  defp error(assigns) do
    ~H"""
    <p class="rg-field__error">
      <.icon name="hero-exclamation-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a page header with a title, and an optional subtitle and actions.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  @spec header(map()) :: Phoenix.LiveView.Rendered.t()
  def header(assigns) do
    ~H"""
    <header class="rg-pagehead">
      <div>
        <h1 class="rg-pagehead__h">{render_slot(@inner_block)}</h1>
        <p :if={@subtitle != []} class="rg-pagehead__sub">{render_slot(@subtitle)}</p>
      </div>
      <div :if={@actions != []} class="rg-pagehead__actions">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  @spec table(map()) :: Phoenix.LiveView.Rendered.t()
  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="rg-table-wrap">
      <table class="rg-table">
        <thead>
          <tr>
            <th :for={col <- @col}>{col[:label]}</th>
            <th :if={@action != []}>
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={@row_click && "is-clickable"}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="rg-table__actions">
              <div>
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders the admin topbar: brand mark, a middle slot (the admin nav) and the
  account controls. It copies the player topbar in `RiddlrWeb.Layouts`, but
  without the colour mode switch: the admin follows the mode picked on the
  player screens.

  ## Examples

      <.topbar current_scope={@current_scope}>
        <nav class="adm-nav" aria-label="Admin">…</nav>
      </.topbar>
  """
  attr :current_scope, :map, default: nil
  slot :inner_block, doc: "content for the middle of the bar"

  @spec topbar(map()) :: Phoenix.LiveView.Rendered.t()
  def topbar(assigns) do
    ~H"""
    <header class="rg-topbar">
      <div class="rg-topbar__in">
        <.link id="topbar-brand" navigate={~p"/"} class="rg-brand" aria-label="Riddlr home">
          <.brand_mark />
        </.link>
        <div class="rg-topbar__mid">{render_slot(@inner_block)}</div>
        <.topbar_account current_scope={@current_scope} />
      </div>
    </header>
    """
  end

  # The logo, as in `RiddlrWeb.Layouts`: a doodled K with pen ticks off its
  # top corner, then the game's name in hand lettering. `--i` staggers the
  # hop that runs across the K's pieces and on through the letters.
  @spec brand_mark(map()) :: Phoenix.LiveView.Rendered.t()
  defp brand_mark(assigns) do
    assigns = assign(assigns, :letters, Enum.with_index(String.graphemes(GameCopy.brand()), 4))

    ~H"""
    <span class="rg-brand__mark" aria-hidden="true">
      <svg class="rg-brand__k" viewBox="-24 -32 312 300" focusable="false">
        <defs>
          <filter id="rg-brand-soften" x="-10%" y="-10%" width="120%" height="120%">
            <feGaussianBlur stdDeviation="1.6" />
          </filter>
          <path id="rg-brand-k-bar" d="M2,3 Q19,-1 37,2 Q40,92 38,181 Q19,169 1,155 Q-1,79 2,3 Z" />
          <path id="rg-brand-k-arm" d="M70,2 Q133,-1 195,1 Q133,58 70,114 Q68,58 70,2 Z" />
          <path
            id="rg-brand-k-low"
            d="M70,151 Q94,131 118,108 Q156,151 191,195 Q158,220 124,244 Q96,225 69,204 Q71,178 70,151 Z"
          />
          <path
            id="rg-brand-k-leg"
            d="M241,2 Q245,1 248,2 Q250,78 247,153 Q234,165 219,175 Q181,131 144,86 Q193,43 241,2 Z"
          />
        </defs>
        <g transform="rotate(-3 124 122)">
          <g class="rg-brand__tip">
            <g class="rg-brand__shadow" filter="url(#rg-brand-soften)">
              <use href="#rg-brand-k-bar" />
              <use href="#rg-brand-k-arm" />
              <use href="#rg-brand-k-low" />
              <use href="#rg-brand-k-leg" />
            </g>
            <g class="rg-brand__piece" style="--i: 0">
              <use href="#rg-brand-k-bar" />
              <path class="rg-brand__gleam" d="M13,16 Q11,78 13,142" />
            </g>
            <g class="rg-brand__piece" style="--i: 1">
              <use href="#rg-brand-k-arm" />
              <path class="rg-brand__gleam" d="M83,18 Q81,48 83,78" />
            </g>
            <g class="rg-brand__piece" style="--i: 2">
              <use href="#rg-brand-k-low" />
            </g>
            <g class="rg-brand__piece" style="--i: 3">
              <use href="#rg-brand-k-leg" />
              <path class="rg-brand__gleam" d="M231,24 Q236,22 236,28" />
            </g>
            <path class="rg-brand__ticks" d="M258,16 L276,9 M252,-6 L264,-20 M238,-12 L240,-27" />
          </g>
        </g>
      </svg>
      <span class="rg-brand__word">
        <span :for={{letter, i} <- @letters} class="rg-brand__l" style={"--i: #{i}"}>{letter}</span>
      </span>
    </span>
    """
  end

  # The me-chip tile is always `variant-1`: the player topbar asked
  # `GameComponents.tone(name, name)`, which gives the viewer `variant-1`.
  attr :current_scope, :map, default: nil

  @spec topbar_account(map()) :: Phoenix.LiveView.Rendered.t()
  defp topbar_account(assigns) do
    ~H"""
    <nav class="rg-topbar__account" aria-label="Account">
      <%= if user = @current_scope && @current_scope.user do %>
        <.link id="topbar-me-chip" navigate={~p"/profile"} class="rg-me-chip">
          <span class="rg-tile rg-tile--sm" data-tone="variant-1" aria-hidden="true">{GameComponents.initial(
            user.username
          )}</span>
          <span class="rg-me-chip__text">
            <span class="rg-me-chip__name">{user.username}</span>
          </span>
        </.link>
        <.link id="topbar-log-out" href={~p"/users/log-out"} method="delete" class="rg-link-btn">
          Log out
        </.link>
      <% else %>
        <.link id="topbar-log-in" navigate={~p"/users/log-in"} class="rg-link-btn">Log in</.link>
      <% end %>
    </nav>
    """
  end
end
