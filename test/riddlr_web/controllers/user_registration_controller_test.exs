defmodule RiddlrWeb.UserRegistrationControllerTest do
  use RiddlrWeb.ConnCase, async: true

  import Riddlr.AccountsFixtures

  require Ecto.Query

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert has_selector?(response, "form[action='/users/register'] input[name='user[email]']")
      assert has_selector?(response, "a[href='/users/log-in']")
    end

    test "renders registration page using the riddlr design system", %{conn: conn} do
      response =
        conn
        |> get(~p"/users/register")
        |> html_response(200)

      assert response =~ ~s(class="rg-auth")
      assert response =~ "rg-auth__submit"
      refute response =~ "btn btn-primary"
    end

    test "uses the shared field and button classes", %{conn: conn} do
      doc = conn |> get(~p"/users/register") |> html_response(200) |> LazyHTML.from_document()

      refute LazyHTML.query(doc, ".rg-field input.rg-input#user_email") |> Enum.empty?()
      refute LazyHTML.query(doc, "button.rg-btn.rg-btn--accent[type=submit]") |> Enum.empty?()
    end

    test "offers an email notification opt-in, unchecked", %{conn: conn} do
      response = conn |> get(~p"/users/register") |> html_response(200)

      assert has_selector?(
               response,
               "fieldset.rg-notify input[type=checkbox][name='user[notify_email]']"
             )

      assert has_selector?(response, "fieldset.rg-notify > legend")
      refute has_selector?(response, "input[name='user[notify_email]'][checked]")
    end

    test "offers a Text opt-in, unchecked, with the consent shown only once ticked", %{
      conn: conn
    } do
      response = conn |> get(~p"/users/register") |> html_response(200)

      assert has_selector?(
               response,
               "fieldset.rg-notify input[type=checkbox][name='user[text_requested]']"
             )

      refute has_selector?(response, "input[name='user[text_requested]'][checked]")
      assert has_selector?(response, "fieldset.rg-notify [data-needs-text] .rg-notify__consent")

      assert has_selector?(
               response,
               "fieldset.rg-notify [data-needs-text] input[type=tel][name='user[signup_phone]']"
             )
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "GET /users/register/check-email" do
    @tag :capture_log
    test "shows the registered email and a way to resend it", %{conn: conn} do
      email = unique_user_email()

      conn = post(conn, ~p"/users/register", %{"user" => valid_user_attributes(email: email)})
      response = conn |> recycle() |> get(~p"/users/register/check-email") |> html_response(200)

      assert has_selector?(response, ".rg-auth [data-registered-email]")
      assert response =~ email
      assert has_selector?(response, "form[action='/users/register/check-email'] button")
      refute has_selector?(response, ".rg-auth a[href='/users/log-in']")
      refute has_selector?(response, "form[action='/users/log-in']")
    end

    test "sends a visitor who has not registered to the sign-up page", %{conn: conn} do
      conn = get(conn, ~p"/users/register/check-email")

      assert redirected_to(conn) == ~p"/users/register"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register/check-email")

      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /users/register/check-email" do
    setup %{conn: conn} do
      email = unique_user_email()
      conn = post(conn, ~p"/users/register", %{"user" => valid_user_attributes(email: email)})
      assert_received {:email, %{to: [{_, ^email}]}}

      %{conn: recycle(conn), email: email}
    end

    @tag :capture_log
    test "refuses a resend within a minute of the last link", %{conn: conn} do
      conn = post(conn, ~p"/users/register/check-email")

      assert redirected_to(conn) == ~p"/users/register/check-email"
      assert conn.assigns.flash["error"]
      refute_received {:email, _}
    end

    @tag :capture_log
    test "resends the link once the last one is over a minute old", %{conn: conn, email: email} do
      age_login_links(email, -61)

      conn = post(conn, ~p"/users/register/check-email")

      assert redirected_to(conn) == ~p"/users/register/check-email"
      assert conn.assigns.flash["info"]
      assert_received {:email, %{to: [{_, ^email}]}}
    end

    @tag :capture_log
    test "sends a banned user nothing, with the same reply", %{conn: conn, email: email} do
      email
      |> Riddlr.Accounts.get_user_by_email()
      |> Ecto.Changeset.change(account_status: :banned)
      |> Riddlr.Repo.update!()

      age_login_links(email, -61)
      conn = post(conn, ~p"/users/register/check-email")

      assert redirected_to(conn) == ~p"/users/register/check-email"
      assert conn.assigns.flash["info"]
      refute_received {:email, _}
    end

    test "sends a visitor who has not registered to the sign-up page" do
      conn = post(build_conn(), ~p"/users/register/check-email")

      assert redirected_to(conn) == ~p"/users/register"
      refute_received {:email, _}
    end
  end

  # Moves every login link sent to `email` back `seconds` in time.
  defp age_login_links(email, seconds) do
    user = Riddlr.Accounts.get_user_by_email(email)
    at = DateTime.add(DateTime.utc_now(:second), seconds, :second)

    Riddlr.Repo.update_all(
      Ecto.Query.where(Riddlr.Accounts.UserToken, user_id: ^user.id, context: "login"),
      set: [inserted_at: at]
    )
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account but does not log in", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/register/check-email"
      refute conn.assigns.flash["info"]
    end

    @tag :capture_log
    test "opt-in checkbox sets notify_email", %{conn: conn} do
      email = unique_user_email()

      post(conn, ~p"/users/register", %{
        "user" => valid_user_attributes(email: email, notify_email: "true")
      })

      assert Riddlr.Accounts.get_user_by_email(email).notify_email
    end

    @tag :capture_log
    test "leaves notify_email off when unchecked", %{conn: conn} do
      email = unique_user_email()

      post(conn, ~p"/users/register", %{
        "user" => valid_user_attributes(email: email, notify_email: "false")
      })

      refute Riddlr.Accounts.get_user_by_email(email).notify_email
    end

    @tag :capture_log
    test "ticking Text holds the number and texts nothing", %{conn: conn} do
      email = unique_user_email()

      post(conn, ~p"/users/register", %{
        "user" =>
          valid_user_attributes(
            email: email,
            text_requested: "true",
            signup_phone: "(416) 555-0123"
          )
      })

      user = Riddlr.Accounts.get_user_by_email(email)
      assert user.text_requested
      assert user.signup_phone == "+14165550123"
      refute_received {:sms, _}
    end

    test "ticking Text without a number shows the error on the field", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(text_requested: "true", signup_phone: "")
        })

      response = html_response(conn, 200)
      assert has_selector?(response, "#user_signup_phone[aria-invalid]")
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert has_selector?(response, "form[action='/users/register'] #user_email[aria-invalid]")
      assert has_selector?(response, "form[action='/users/register'] .rg-field__error")
      refute get_session(conn, :user_token)
    end
  end
end
