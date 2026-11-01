defmodule RiddlrWeb.PrototypeSmsOptIn do
  @moduledoc """
  PROTOTYPE, throwaway (issue #59 SMS). Lives on branch prototype/sms-opt-in only.

  Shows the "Notify me of upcoming games" flow on /users/register and /profile.
  Nothing saves: buttons only move between steps via `?state=`. The floating
  bar flips through the profile steps. Dev only.
  """
  use Phoenix.Component
  use RiddlrWeb, :verified_routes

  alias Phoenix.LiveView.JS

  @states ~w(off text_checked code_sent confirmed after_signup stopped)
  @labels %{
    "off" => "1. Nothing on",
    "text_checked" => "2. Text checked, enter number",
    "code_sent" => "3. Code sent, enter code",
    "confirmed" => "4. Number confirmed",
    "after_signup" => "5b. Profile, after tapping the log-in flash",
    "stopped" => "6. After player replied STOP"
  }

  def enabled?, do: Application.get_env(:riddlr, :dev_routes, false)
  def states, do: @states

  def state(params) do
    if params["state"] in @states, do: params["state"], else: "off"
  end

  @doc "Profile summary text per step."
  def summary("confirmed"), do: "Email + Text (•••• 1234), 30 min before"
  def summary(_), do: "Email, 30 min before"

  # ── Sign-up ──────────────────────────────────────────────────────────────

  attr :form, :any, required: true

  def signup_fields(assigns) do
    ~H"""
    <fieldset class="proto-notify">
      <legend class="rg-field__label">Notify me of upcoming games</legend>

      <div class="rg-field__check">
        <input type="checkbox" id="proto-su-email" name={@form[:notify_email].name} value="true" class="rg-check" />
        <label for="proto-su-email" class="rg-field__label">Email</label>
      </div>

      <div class="rg-field__check">
        <input
          type="checkbox"
          id="proto-su-text"
          class="rg-check"
          phx-click={JS.toggle(to: "#proto-su-phone", display: "grid")}
        />
        <label for="proto-su-text" class="rg-field__label">Text</label>
      </div>

      <div id="proto-su-phone" class="proto-notify__phone" style="display: none">
        <.phone_input id="proto-su-phone-input" />
        <.consent_copy />
        <p class="proto-note">
          We text you a code after you first log in. No texts go out until then.
        </p>
      </div>
    </fieldset>
    """
  end

  # ── Profile ──────────────────────────────────────────────────────────────

  attr :state, :string, required: true

  def profile_section(assigns) do
    ~H"""
    <div id="proto-profile-notify" class="rg-auth__form">
      <div :if={@state == "stopped"} class="proto-banner">
        You replied STOP to a text, so we turned texts off and removed your number.
        To get texts again, add your number below.
      </div>

      <fieldset class="proto-notify">
        <legend class="rg-field__label">Notify me of upcoming games</legend>

        <div class="rg-field__check">
          <input type="checkbox" id="proto-pf-email" class="rg-check" checked />
          <label for="proto-pf-email" class="rg-field__label">Email</label>
        </div>

        <div class="rg-field__check">
          <input
            type="checkbox"
            id="proto-pf-text"
            class="rg-check"
            checked={@state in ~w(text_checked code_sent confirmed after_signup)}
            phx-click={
              @state in ~w(off stopped) &&
                JS.toggle(to: "#proto-pf-phone", display: "grid")
            }
          />
          <label for="proto-pf-text" class="rg-field__label">Text</label>
        </div>

        <%!-- Steps 1, 2, 6: enter a number --%>
        <div
          :if={@state in ~w(off text_checked stopped)}
          id="proto-pf-phone"
          class="proto-notify__phone"
          style={if @state == "text_checked", do: "display: grid", else: "display: none"}
        >
          <.phone_input id="proto-pf-phone-input" />
          <.consent_copy />
          <.link href={~p"/profile?state=code_sent"} class="rg-btn rg-btn--wide">
            Text me a code
          </.link>
        </div>

        <%!-- Steps 3, 5: enter the code --%>
        <div :if={@state in ~w(code_sent after_signup)} class="proto-notify__phone">
          <p class="proto-note">We texted a 6-digit code to •••• 1234. It works for 10 min.</p>
          <div class="rg-field">
            <label for="proto-code" class="rg-field__label">Code</label>
            <input
              id="proto-code"
              type="text"
              inputmode="numeric"
              autocomplete="one-time-code"
              maxlength="6"
              placeholder="123456"
              class="rg-input"
            />
          </div>
          <.link href={~p"/profile?state=confirmed"} class="rg-btn rg-btn--wide">
            Confirm number
          </.link>
          <p class="proto-links">
            <a href="#" class="rg-auth__link">Send a new code</a>
            <.link href={~p"/profile?state=text_checked"} class="rg-auth__link">
              Use another number
            </.link>
          </p>
        </div>

        <%!-- Step 4: confirmed --%>
        <div :if={@state == "confirmed"} class="proto-notify__phone">
          <p class="proto-confirmed">•••• 1234 <span>Confirmed</span></p>
          <p class="proto-links">
            <.link href={~p"/profile?state=text_checked"} class="rg-auth__link">
              Change number
            </.link>
            <.link href={~p"/profile?state=off"} class="rg-auth__link">Remove number</.link>
          </p>
          <p class="proto-note">
            Unchecking Text pauses texts and keeps your number. Remove number deletes it.
          </p>
        </div>
      </fieldset>

      <div class="rg-field">
        <label for="proto-lead" class="rg-field__label">When</label>
        <select id="proto-lead" class="rg-input">
          <option>When the Lobby opens</option>
          <option selected>30 min before</option>
          <option>1 hour before</option>
        </select>
      </div>

      <button type="button" class="rg-btn rg-btn--accent rg-btn--wide rg-auth__submit">
        Save notifications
      </button>
    </div>
    """
  end

  # ── Shared bits ──────────────────────────────────────────────────────────

  attr :id, :string, required: true

  defp phone_input(assigns) do
    ~H"""
    <div class="rg-field">
      <label for={@id} class="rg-field__label">Mobile number (Canada)</label>
      <input
        id={@id}
        type="tel"
        inputmode="tel"
        autocomplete="tel-national"
        placeholder="(416) 555-1234"
        class="rg-input"
      />
    </div>
    """
  end

  defp consent_copy(assigns) do
    ~H"""
    <p class="proto-note">
      Riddlr will text you before riddles go live. Message and data rates may apply.
      Reply STOP to end, HELP for help. <a href="#" class="rg-auth__link">Privacy policy</a>
    </p>
    """
  end

  # ── Floating step switcher ───────────────────────────────────────────────

  attr :state, :string, required: true

  def switcher(assigns) do
    i = Enum.find_index(@states, &(&1 == assigns.state))
    n = length(@states)

    assigns =
      assign(assigns,
        prev: Enum.at(@states, rem(i - 1 + n, n)),
        next: Enum.at(@states, rem(i + 1, n)),
        label: @labels[assigns.state]
      )

    ~H"""
    <style>
      .proto-notify { border: 0; padding: 0; margin: 0; display: grid; gap: var(--space-2xs); }
      .proto-notify legend { margin-bottom: var(--space-2xs); }
      .proto-notify__phone { display: grid; gap: var(--space-xs); padding-left: var(--space-m); }
      .proto-notify__phone .rg-field { margin-bottom: 0; }
      .proto-note { font-size: var(--step--1); color: var(--fg-muted); line-height: 1.4; }
      .proto-links { display: flex; gap: var(--space-m); font-size: var(--step--1); }
      .proto-confirmed { font-weight: 700; }
      .proto-confirmed span { font-weight: 400; color: var(--fg-muted); margin-left: var(--space-2xs); }
      .proto-banner { border: 2px dashed var(--fg); padding: var(--space-xs); font-size: var(--step--1); }
      .proto-bar { position: fixed; bottom: 1rem; left: 50%; transform: translateX(-50%); z-index: 9999;
        display: flex; gap: .75rem; align-items: center; padding: .5rem 1rem; border-radius: 999px;
        background: #111; color: #fff; font: 600 14px/1.2 system-ui, sans-serif; box-shadow: 0 4px 16px #0006; }
      .proto-bar a { color: #fff; text-decoration: none; padding: 0 .25rem; }
    </style>
    <nav class="proto-bar" aria-label="Prototype steps">
      <a id="proto-prev" href={~p"/profile?state=#{@prev}"}>←</a>
      <span>PROTOTYPE · {@label}</span>
      <a id="proto-next" href={~p"/profile?state=#{@next}"}>→</a>
      <a href={~p"/users/register"}>· Sign-up</a>
      <a href="/dev/proto-sms-login">· 5a. Log-in flash</a>
    </nav>
    <script>
      document.addEventListener("keydown", (e) => {
        const t = e.target;
        if (t.matches("input, textarea, select, [contenteditable]")) return;
        if (e.key === "ArrowLeft") document.getElementById("proto-prev").click();
        if (e.key === "ArrowRight") document.getElementById("proto-next").click();
      });
    </script>
    """
  end

  @doc "Bar on the sign-up page: CSS plus a link to the profile steps."
  def signup_bar(assigns) do
    ~H"""
    <.switcher state="off" />
    """
  end
end

defmodule RiddlrWeb.PrototypeSmsLoginController do
  @moduledoc """
  PROTOTYPE, throwaway. Fakes landing after the first log-in for a player who
  gave a phone at sign-up: we just texted them a code, so a flash points them
  to the code field.
  """
  use RiddlrWeb, :controller

  def show(conn, _params) do
    msg =
      Phoenix.HTML.raw(
        ~s(We texted a code to •••• 1234. ) <>
          ~s(<a href="/profile?state=after_signup" class="rg-auth__link">Enter it to turn on texts</a>)
      )

    conn
    |> put_flash(:info, msg)
    |> redirect(to: ~p"/")
  end
end
