defmodule RiddlrWeb.ProfileControllerTest do
  use RiddlrWeb.ConnCase, async: true

  alias Riddlr.Accounts
  import Riddlr.AccountsFixtures

  setup :register_and_log_in_user

  describe "GET /profile" do
    test "sums up the notification choice", %{conn: conn, user: user} do
      off = conn |> get(~p"/profile") |> html_response(200) |> summary()

      {:ok, _} =
        Accounts.update_user_notifications(user, %{
          notify_email: true,
          notification_lead_time: :min_30
        })

      on = conn |> get(~p"/profile") |> html_response(200) |> summary()

      assert off =~ "Off"
      assert on =~ "Email"
      assert on =~ "30 min"
    end

    test "renders the current user's profile", %{conn: conn, user: user} do
      conn = get(conn, ~p"/profile")
      response = html_response(conn, 200)
      assert has_selector?(response, "#update_email input[name='user[email]']")
      assert response =~ user.username
    end

    test "renders settings page using the riddlr design system", %{conn: conn} do
      response =
        conn
        |> get(~p"/profile")
        |> html_response(200)

      assert response =~ ~s(class="rg-auth")
      assert response =~ "rg-auth__submit"
      refute response =~ "btn btn-primary"
    end

    test "does not offer password management", %{conn: conn} do
      response =
        conn
        |> get(~p"/profile")
        |> html_response(200)

      refute has_selector?(response, "[name='user[password]']")
    end

    test "redirects if user is not logged in" do
      conn = build_conn()
      conn = get(conn, ~p"/profile")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
    test "renders without sudo mode", %{conn: conn} do
      conn = get(conn, ~p"/profile")
      assert has_selector?(html_response(conn, 200), "#update_email")
    end
  end

  describe "PUT /profile (change password form)" do
    test "updates the user password and resets tokens", %{conn: conn, user: user} do
      new_password_conn =
        put(conn, ~p"/profile", %{
          "action" => "update_password",
          "user" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(new_password_conn) == ~p"/profile"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info)

      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "disconnects the LiveViews of the user's other sessions", %{conn: conn, user: user} do
      other_token = Accounts.generate_user_session_token(user)
      topic = "users_sessions:#{Base.url_encode64(other_token)}"
      RiddlrWeb.Endpoint.subscribe(topic)

      put(conn, ~p"/profile", %{
        "action" => "update_password",
        "user" => %{
          "password" => "new valid password",
          "password_confirmation" => "new valid password"
        }
      })

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^topic}
    end

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
    test "requires sudo mode", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/profile", %{
          "action" => "update_password",
          "user" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      refute Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "does not update password on invalid data", %{conn: conn, user: user} do
      old_password_conn =
        put(conn, ~p"/profile", %{
          "action" => "update_password",
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert has_selector?(html_response(old_password_conn, 200), "#update_email")
      refute Accounts.get_user_by_email_and_password(user.email, "too short")
      assert get_session(old_password_conn, :user_token) == get_session(conn, :user_token)
    end
  end

  describe "PUT /profile (unknown action)" do
    test "redirects back with an error", %{conn: conn} do
      conn = put(conn, ~p"/profile", %{"action" => "nope", "user" => %{}})

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
    end

    for action <- ["update_email", "update_password", "update_notifications"] do
      test "treats #{action} with no user params as unknown", %{conn: conn} do
        conn = put(conn, ~p"/profile", %{"action" => unquote(action)})

        assert redirected_to(conn) == ~p"/profile"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Unknown form."
      end
    end
  end

  describe "PUT /profile (change email form)" do
    @tag :capture_log
    test "updates the user email", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/profile", %{
          "action" => "update_email",
          "user" => %{"email" => unique_user_email()}
        })

      assert redirected_to(conn) == ~p"/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :info)

      assert Accounts.get_user_by_email(user.email)
    end

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
    test "requires sudo mode", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/profile", %{
          "action" => "update_email",
          "user" => %{"email" => unique_user_email()}
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Accounts.get_user_by_email(user.email)
    end

    test "does not update email on invalid data", %{conn: conn} do
      conn =
        put(conn, ~p"/profile", %{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert has_selector?(response, "#update_email_email[aria-invalid]")
      assert has_selector?(response, "#update_email .rg-field__error")
    end
  end

  describe "PUT /profile (notifications form)" do
    test "renders an email toggle that is off by default", %{conn: conn} do
      response = conn |> get(~p"/profile") |> html_response(200)

      assert has_selector?(
               response,
               "#update_notifications fieldset.rg-notify input[type=checkbox][name='user[notify_email]']"
             )

      assert has_selector?(response, "#update_notifications fieldset.rg-notify > legend")

      refute has_selector?(
               response,
               "#update_notifications input[name='user[notify_email]'][checked]"
             )

      assert has_selector?(
               response,
               "#update_notifications select[name='user[notification_lead_time]'] option[value=lobby_open][selected]"
             )
    end

    test "saves the lead time", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/profile", %{
          "action" => "update_notifications",
          "user" => %{"notify_email" => "true", "notification_lead_time" => "min_60"}
        })

      assert redirected_to(conn) == ~p"/profile"
      assert Accounts.get_user!(user.id).notification_lead_time == :min_60
    end

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
    test "turns email notifications on and off without sudo mode", %{conn: conn, user: user} do
      on_conn =
        put(conn, ~p"/profile", %{
          "action" => "update_notifications",
          "user" => %{"notify_email" => "true"}
        })

      assert redirected_to(on_conn) == ~p"/profile"
      assert Phoenix.Flash.get(on_conn.assigns.flash, :info)
      assert Accounts.get_user!(user.id).notify_email

      response = conn |> get(~p"/profile") |> html_response(200)

      assert has_selector?(
               response,
               "#update_notifications input[name='user[notify_email]'][checked]"
             )

      put(conn, ~p"/profile", %{
        "action" => "update_notifications",
        "user" => %{"notify_email" => "false"}
      })

      refute Accounts.get_user!(user.id).notify_email
    end
  end

  describe "GET /profile/confirm-email/:token" do
    setup %{user: user} do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{token: token, email: email}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      conn = get(conn, ~p"/profile/confirm-email/#{token}")
      assert redirected_to(conn) == ~p"/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :info)

      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      conn = get(conn, ~p"/profile/confirm-email/#{token}")

      assert redirected_to(conn) == ~p"/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :error)
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      conn = get(conn, ~p"/profile/confirm-email/oops")
      assert redirected_to(conn) == ~p"/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :error)

      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, ~p"/profile/confirm-email/#{token}")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  defp summary(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#profile-notifications")
    |> LazyHTML.text()
  end
end
