defmodule RiddlrWeb.ProfileController do
  @moduledoc """
  The signed-in player's own account page: who they are, plus the forms that
  change their account. Only changing a log-in credential needs a recent log-in.
  The phone steps show, and work, only while an SMS adapter is set.
  """
  use RiddlrWeb, :controller

  alias Riddlr.Accounts
  alias RiddlrWeb.UserAuth

  @sudo_actions ~w(update_email update_password)
  # Removing a number stays open with texting off, so a player can always
  # delete their data.
  @sms_actions ~w(send_phone_code resend_phone_code confirm_phone)
  @locked_message "Maximum verification attempts exceeded. Try again in 24hrs."

  plug :require_sudo_for_credentials when action == :update
  plug :require_sms when action == :update
  plug :assign_changesets
  plug :assign_phone

  @doc "Renders the current user's profile and account forms."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    render(conn, :show)
  end

  @doc """
  Saves one profile form. The hidden `action` param names the form:
  `update_email`, `update_password`, `update_notifications`, or a phone step:
  `send_phone_code`, `resend_phone_code`, `confirm_phone`, `remove_phone`.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"action" => "update_email"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/profile/confirm-email/#{&1}")
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: ~p"/profile")

      changeset ->
        render(conn, :show, email_changeset: %{changeset | action: :insert})
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.update_user_password(user, user_params) do
      {:ok, {user, _}} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> put_session(:user_return_to, ~p"/profile")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, :show, password_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "update_notifications"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.update_user_notifications(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Notification settings saved.")
        |> redirect(to: ~p"/profile")

      {:error, changeset} ->
        render(conn, :show, notifications_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "send_phone_code", "phone" => phone_params}) do
    case Accounts.send_phone_code(conn.assigns.current_scope.user, phone_params) do
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :show,
          phone_form: Phoenix.Component.to_form(changeset, as: :phone),
          phone_step: :enter
        )

      result ->
        after_phone_send(conn, result)
    end
  end

  def update(conn, %{"action" => "resend_phone_code"}) do
    result = Accounts.resend_phone_code(conn.assigns.current_scope.user)
    after_phone_send(conn, result)
  end

  def update(conn, %{"action" => "confirm_phone", "phone" => %{"code" => code}})
      when is_binary(code) do
    user = conn.assigns.current_scope.user

    case Accounts.confirm_phone(user, String.trim(code)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Number confirmed.")
        |> redirect(to: ~p"/profile")

      {:error, :invalid_code} ->
        render_code_error(conn, code, "Invalid verification code. Try again")

      {:error, :too_many_attempts} ->
        conn
        |> put_flash(:error, @locked_message)
        |> redirect(to: ~p"/profile")

      {:error, :expired} ->
        conn
        |> put_flash(:error, "That code has expired. Enter your number to get a new one.")
        |> redirect(to: ~p"/profile")

      {:error, :no_code} ->
        conn
        |> put_flash(:error, "Enter your number to get a code.")
        |> redirect(to: ~p"/profile")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "That number is already used by another account.")
        |> redirect(to: ~p"/profile")
    end
  end

  def update(conn, %{"action" => "remove_phone"}) do
    {:ok, _user} = Accounts.remove_phone(conn.assigns.current_scope.user)

    conn
    |> put_flash(:info, "Number removed.")
    |> redirect(to: ~p"/profile")
  end

  def update(conn, _params) do
    conn
    |> put_flash(:error, "Unknown form.")
    |> redirect(to: ~p"/profile")
  end

  @doc "Applies an email change from the link sent to the new address."
  @spec confirm_email(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_scope.user, token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/profile")

      {:error, _} ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/profile")
    end
  end

  defp after_phone_send(conn, {:ok, _phone_code}) do
    conn
    |> put_flash(:info, "Code sent.")
    |> redirect(to: ~p"/profile")
  end

  defp after_phone_send(conn, {:error, reason}) do
    message =
      case reason do
        :locked -> @locked_message
        :rate_limited -> "Too many codes. Try again later."
        :no_code -> "Enter your number to get a code."
        _ -> "We could not send the text. Try again later."
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/profile")
  end

  defp render_code_error(conn, code, message) do
    form = Phoenix.Component.to_form(%{"code" => code}, as: :phone, errors: [code: {message, []}])
    render(conn, :show, code_form: form, phone_step: :code)
  end

  @spec require_sms(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp require_sms(%{params: %{"action" => action}} = conn, _opts) when action in @sms_actions do
    if Riddlr.SMS.enabled?() do
      conn
    else
      conn
      |> put_flash(:error, "Texts are not available yet.")
      |> redirect(to: ~p"/profile")
      |> halt()
    end
  end

  defp require_sms(conn, _opts), do: conn

  @spec require_sudo_for_credentials(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp require_sudo_for_credentials(%{params: %{"action" => action}} = conn, opts)
       when action in @sudo_actions do
    UserAuth.require_sudo_mode(conn, opts)
  end

  defp require_sudo_for_credentials(conn, _opts), do: conn

  @spec assign_changesets(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp assign_changesets(conn, _opts) do
    user = conn.assigns.current_scope.user

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
    |> assign(:notifications_changeset, Accounts.change_user_notifications(user))
  end

  # The phone section: whether it shows at all, and which step it is on.
  # `:enter` asks for a number, `:code` asks for the texted code, `nil` shows
  # only the confirmed number. `?phone=new` asks for a new number.
  @spec assign_phone(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp assign_phone(conn, _opts) do
    user = conn.assigns.current_scope.user
    pending = Accounts.get_pending_phone_code(user)

    step =
      cond do
        conn.params["phone"] == "new" -> :enter
        pending -> :code
        user.phone_confirmed_at -> nil
        true -> :enter
      end

    conn
    |> assign(:sms_enabled?, Riddlr.SMS.enabled?())
    |> assign(:phone_step, step)
    |> assign(:pending_phone, pending && Riddlr.SMS.mask(pending.phone))
    |> assign(:phone_form, Phoenix.Component.to_form(%{}, as: :phone))
    |> assign(:code_form, Phoenix.Component.to_form(%{}, as: :phone))
  end
end
