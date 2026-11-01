defmodule RiddlrWeb.AuthComponents do
  @moduledoc """
  Building blocks for the account screens: log in, register, confirm and settings.

  The `rg-auth` page layout lives in `assets/css/auth.css`. Buttons use the
  shared `rg-btn` classes from `assets/css/game.css`, and fields use
  `RiddlrWeb.CoreComponents.input/1`, so account screens match the player
  screens.
  """
  use Phoenix.Component

  import RiddlrWeb.CoreComponents, only: [input: 1]

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

  @doc "Primary submit button."
  attr :rest, :global, include: ~w(name value disabled form)
  slot :inner_block, required: true

  def auth_submit(assigns) do
    ~H"""
    <button type="submit" class="rg-btn rg-btn--accent rg-btn--wide rg-auth__submit" {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc "Secondary button for the less common choice on a screen."
  attr :rest, :global, include: ~w(name value disabled form)
  slot :inner_block, required: true

  def auth_ghost_button(assigns) do
    ~H"""
    <button type="submit" class="rg-btn rg-btn--wide rg-auth__ghost" {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  The "Notify me of upcoming games" group: one checkbox per channel the
  player can turn on. Sign-up and the profile both use it.
  """
  attr :form, Phoenix.HTML.Form, required: true

  def notify_me_group(assigns) do
    ~H"""
    <fieldset class="rg-notify">
      <legend class="rg-field__label">Notify me of upcoming games</legend>
      <.input field={@form[:notify_email]} type="checkbox" label="Email" />
    </fieldset>
    """
  end
end
