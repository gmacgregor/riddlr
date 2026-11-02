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

  With `text`, it adds a Text box and renders the `text_steps` slot under it,
  e.g. the profile's phone steps. `text_field` names the field the Text box
  sets: `notify_sms` on the profile, `text_requested` at sign-up.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :text, :boolean, default: false, doc: "show the Text box"
  attr :text_field, :atom, default: :notify_sms, doc: "the field the Text box sets"
  slot :text_steps, doc: "shown under the Text box"

  def notify_me_group(assigns) do
    ~H"""
    <fieldset class="rg-notify">
      <legend class="rg-field__label">Notify me of upcoming games</legend>
      <.input field={@form[:notify_email]} type="checkbox" label="Email" />
      <.input :if={@text} field={@form[@text_field]} type="checkbox" label="Text" />
      {render_slot(@text_steps)}
    </fieldset>
    """
  end

  @doc """
  What a player agrees to by turning Text on, with a link to the info page
  (contact and privacy).
  """
  def text_consent(assigns) do
    assigns = assign(assigns, :info_url, Application.fetch_env!(:riddlr, :info_url))

    ~H"""
    <p class="rg-phone__note rg-notify__consent">
      Kriddle will text you before riddles go live. Message and data rates may apply.
      Reply STOP to end, HELP for help. <a href={@info_url} class="rg-auth__link">Privacy policy</a>
    </p>
    """
  end

  @doc """
  The mobile number field, with the note that texts only go to Canadian
  numbers. Every place a player can give a number for texts uses it.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :required, :boolean, default: true, doc: "false when the field hides inside a bigger form"
  attr :rest, :global, include: ~w(form)

  def phone_field(assigns) do
    ~H"""
    <.input
      {@rest}
      field={@field}
      type="tel"
      label="Mobile number"
      inputmode="tel"
      autocomplete="tel-national"
      placeholder="(416) 555-1234"
      required={@required}
    />
    <p class="rg-phone__note rg-phone__canada-note">Texts go to Canadian mobile numbers only.</p>
    """
  end
end
