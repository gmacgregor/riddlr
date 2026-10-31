defmodule RiddlrWeb.UserRegistrationControllerTest do
  use RiddlrWeb.ConnCase, async: true

  import Riddlr.AccountsFixtures

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

      assert has_selector?(response, "input[type=checkbox][name='user[notify_email]']")
      refute has_selector?(response, "input[name='user[notify_email]'][checked]")
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/"
    end
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
      assert redirected_to(conn) == ~p"/users/log-in"

      assert conn.assigns.flash["info"] =~ email
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
