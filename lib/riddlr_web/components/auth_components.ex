defmodule RiddlrWeb.AuthComponents do
  @moduledoc """
  Building blocks for the account screens: log in, register, confirm and settings.

  These render the `rg-auth` markup styled by `assets/css/auth.css`, so the
  account screens match the game frame instead of the stock Phoenix look.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: RiddlrWeb.Endpoint,
    router: RiddlrWeb.Router,
    statics: RiddlrWeb.static_paths()

  import RiddlrWeb.CoreComponents, only: [icon: 1, translate_error: 1]

  @doc """
  Account controls for the app header.

  Logged out, it links to the log in page. Logged in, it shows the username as
  a link to the settings page next to a log out button.
  """
  attr :current_scope, :map, default: nil

  def auth_menu(assigns) do
    ~H"""
    <nav class="rg-auth-menu" aria-label="Account">
      <%= if @current_scope && @current_scope.user do %>
        <.link navigate={~p"/users/settings"} class="rg-auth-menu__user">
          {@current_scope.user.username}
        </.link>
        <.link href={~p"/users/log-out"} method="delete" class="rg-auth-menu__link">
          Log out
        </.link>
      <% else %>
        <.link navigate={~p"/users/log-in"} class="rg-auth-menu__link">Log in</.link>
      <% end %>
    </nav>
    """
  end

  @doc """
  Card shell for an account screen.

  Wraps a page in the brand mark, a title and an optional subtitle.
  """
  attr :title, :string, required: true
  slot :subtitle
  slot :inner_block, required: true

  def auth_shell(assigns) do
    ~H"""
    <section class="rg-auth">
      <div class="rg-auth__card">
        <div class="rg-auth__header">
          <h1 class="rg-auth__title">{@title}</h1>
          <p :if={@subtitle != []} class="rg-auth__subtitle">{render_slot(@subtitle)}</p>
        </div>

        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc """
  Labelled text input with its field errors.

  Errors only show once the user has submitted the field, which matches the
  behaviour of `RiddlrWeb.CoreComponents.input/1`.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :rest, :global, include: ~w(autocomplete placeholder readonly required spellcheck)

  def auth_input(assigns) do
    field = assigns.field
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns = assign(assigns, :errors, Enum.map(errors, &translate_error/1))

    ~H"""
    <div class="rg-auth__field">
      <label class="rg-auth__label" for={@field.id}>{@label}</label>
      <input
        type={@type}
        name={@field.name}
        id={@field.id}
        value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
        class={["rg-auth__input", @errors != [] && "rg-auth__input--error"]}
        {@rest}
      />
      <p :for={msg <- @errors} class="rg-auth__error">
        <.icon name="hero-exclamation-circle" class="size-4" />{msg}
      </p>
    </div>
    """
  end

  @doc "Primary submit button."
  attr :rest, :global, include: ~w(name value disabled form)
  slot :inner_block, required: true

  def auth_submit(assigns) do
    ~H"""
    <button class="rg-auth__submit" {@rest}>{render_slot(@inner_block)}</button>
    """
  end

  @doc "Secondary button for the less common choice on a screen."
  attr :rest, :global, include: ~w(name value disabled form)
  slot :inner_block, required: true

  def auth_ghost_button(assigns) do
    ~H"""
    <button class="rg-auth__ghost" {@rest}>{render_slot(@inner_block)}</button>
    """
  end
end
