defmodule Riddlr.Accounts.UserNotifier do
  import Swoosh.Email

  alias Riddlr.Mailer
  alias Riddlr.Accounts.User

  @typedoc "The sent email, or why it did not send."
  @type delivery :: {:ok, Swoosh.Email.t()} | {:error, term()}

  # Delivers the email using the application mailer.
  @spec deliver(String.t(), String.t(), String.t()) :: delivery()
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:riddlr, :mail_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  @spec deliver_update_email_instructions(User.t(), String.t()) :: delivery()
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """
    Hi #{user.email},

    You can change your email by visiting the link below:

    #{url}

    If you didn't request this change, please ignore this.

    ✌️Team Kriddle
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  @spec deliver_login_instructions(User.t(), String.t()) :: delivery()
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  @spec deliver_magic_link_instructions(User.t(), String.t()) :: delivery()
  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in link", """
    Hi #{user.email},

    You can log into your account by visiting the link below:

    #{url}

    If you didn't recently try to log into your account, you may safely ignore this.

    ✌️Team Kriddle
    """)
  end

  @spec deliver_confirmation_instructions(User.t(), String.t()) :: delivery()
  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Account confirmation", """
    Hi #{user.email},

    Confirm your account by visiting the link below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ✌️Team Kriddle
    """)
  end
end
