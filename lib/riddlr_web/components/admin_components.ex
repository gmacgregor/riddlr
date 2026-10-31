defmodule RiddlrWeb.AdminComponents do
  @moduledoc """
  The UI components the admin uses: button, input, page header, table, flash,
  and the topbar with its colour mode switch.

  A frozen copy of `RiddlrWeb.CoreComponents` and the `RiddlrWeb.Layouts`
  topbar as they stood before the v9 player redesign (#47). The admin gets
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
  alias RiddlrWeb.Theme

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
  account controls, with the colour mode switch.

  ## Examples

      <.topbar current_scope={@current_scope} theme={@theme}>
        <nav class="adm-nav" aria-label="Admin">…</nav>
      </.topbar>
  """
  attr :current_scope, :map, default: nil
  attr :theme, :string, required: true
  slot :inner_block, doc: "content for the middle of the bar"

  @spec topbar(map()) :: Phoenix.LiveView.Rendered.t()
  def topbar(assigns) do
    ~H"""
    <header class="rg-topbar">
      <div class="rg-topbar__in">
        <.link id="topbar-brand" navigate={~p"/"} class="rg-brand" aria-label="Riddlr home">
          <span class="rg-brand__mark" aria-hidden="true">
            <span class="rg-brand__q">?</span><span class="rg-brand__word">riddlr</span>
          </span>
        </.link>
        <div class="rg-topbar__mid">{render_slot(@inner_block)}</div>
        <.theme_switch theme={@theme} />
        <.topbar_account current_scope={@current_scope} />
      </div>
    </header>
    """
  end

  # The colour mode switch: one button that flips between light and dark on
  # each press (see `assets/js/app.js`). It sets `data-theme` on <html> and
  # writes the `theme` cookie in the browser, so the admin and player screens
  # share one choice. The button holds one icon per mode and CSS shows the one
  # that matches <html data-theme>. Each icon carries the button label and
  # browser bar colour for its mode, which JS copies onto the page.
  # `phx-update="ignore"` keeps LiveView from undoing the pick.
  attr :theme, :string, required: true

  @spec theme_switch(map()) :: Phoenix.LiveView.Rendered.t()
  defp theme_switch(assigns) do
    assigns = assign(assigns, :themes, Theme.themes())

    ~H"""
    <button
      id="theme-switch"
      type="button"
      class="rg-theme"
      aria-label={theme_switch_label(@theme)}
      phx-update="ignore"
    >
      <svg
        :for={theme <- @themes}
        class={["rg-theme__icon", "rg-theme__icon--#{theme}"]}
        data-theme-icon={theme}
        data-label={theme_switch_label(theme)}
        data-color={Theme.theme_color(theme)}
        width="15"
        height="15"
        viewBox="0 0 15 15"
        fill="none"
        aria-hidden="true"
      >
        <path d={theme_icon_path(theme)} fill="currentColor" />
      </svg>
    </button>
    """
  end

  @spec theme_switch_label(Theme.t()) :: String.t()
  defp theme_switch_label(theme) do
    "Colour mode: #{Theme.label(theme)}. Switch to #{Theme.label(Theme.next(theme))}"
  end

  # Radix icons (https://www.radix-ui.com/icons): eye closed for dark, eye
  # open for light.
  @spec theme_icon_path(Theme.t()) :: String.t()
  defp theme_icon_path("dark"),
    do:
      "M5.58284 12.5867C5.5113 12.8531 5.23703 13.0113 4.97054 12.9402C4.70421 12.8686 4.54496 12.5943 4.61605 12.3279L5.58284 12.5867ZM10.3826 12.3279C10.4539 12.5945 10.2956 12.8686 10.0291 12.9402C9.76261 13.0113 9.48834 12.8531 9.41681 12.5867L10.3826 12.3279ZM14.1375 6.15505C14.2977 5.98633 14.5595 5.94799 14.7644 6.07595C14.9692 6.20395 15.0496 6.45576 14.9685 6.6736L14.9236 6.76442C14.4845 7.46696 13.962 8.1052 13.3689 8.66188L14.5711 9.86402L14.6355 9.94214C14.7636 10.1362 14.7419 10.4002 14.5711 10.571C14.4003 10.7419 14.1363 10.7636 13.9422 10.6355L13.8641 10.571L12.5994 9.3064C11.8032 9.90116 10.9077 10.3602 9.93243 10.6492L10.3826 12.3279L9.89923 12.4568L9.41681 12.5867L8.95783 10.8777C8.48648 10.958 7.99975 10.9998 7.49983 10.9998C6.9991 10.9998 6.51194 10.9563 6.03987 10.8757L5.58284 12.5867L5.09945 12.4568L4.61605 12.3279L5.06527 10.6492C4.09036 10.3601 3.19423 9.90202 2.39829 9.30738L1.1356 10.571C0.940342 10.7662 0.623806 10.7662 0.428567 10.571C0.233426 10.3758 0.233415 10.0593 0.428567 9.86402L1.62973 8.66188C1.10375 8.1681 0.633248 7.61 0.227396 6.99977L0.0760295 6.76442L0.0311078 6.6736C-0.0498844 6.45577 0.0304399 6.20394 0.235208 6.07595C0.440189 5.94795 0.701937 5.98637 0.862159 6.15505L0.923682 6.23513L1.20102 6.65114C2.63903 8.68678 4.86748 9.99974 7.49983 9.99976C10.3076 9.99976 12.6564 8.50638 14.076 6.23513L14.1375 6.15505Z"

  defp theme_icon_path("light"),
    do:
      "M7.50002 3C10.6922 3 13.3435 4.70671 14.9239 7.23535C15.0124 7.37717 15.0235 7.55201 14.9571 7.70215L14.9239 7.76465C13.3435 10.2933 10.6922 12 7.50002 12C4.30788 12 1.65659 10.2933 0.0761963 7.76465C-0.0249881 7.6026 -0.0249956 7.3974 0.0761963 7.23535L0.227563 7C1.82294 4.60122 4.4078 3 7.50002 3ZM7.50002 4C4.80354 4 2.53299 5.37905 1.09963 7.5C2.53299 9.62094 4.80354 11 7.50002 11C10.1963 11 12.4661 9.62068 13.8994 7.5C12.4661 5.3793 10.1963 4 7.50002 4ZM7.50002 5.5C8.60459 5.5 9.50002 6.39543 9.50002 7.5C9.50002 8.60457 8.60459 9.5 7.50002 9.5C6.39545 9.5 5.50002 8.60457 5.50002 7.5C5.50002 6.39543 6.39545 5.5 7.50002 5.5Z"

  # The me-chip tile is always `variant-1`: the player topbar asked
  # `GameComponents.tone(name, name)`, which gives the viewer `variant-1`.
  attr :current_scope, :map, default: nil

  @spec topbar_account(map()) :: Phoenix.LiveView.Rendered.t()
  defp topbar_account(assigns) do
    ~H"""
    <nav class="rg-topbar__account" aria-label="Account">
      <%= if user = @current_scope && @current_scope.user do %>
        <.link id="topbar-me-chip" navigate={~p"/users/settings"} class="rg-me-chip">
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
