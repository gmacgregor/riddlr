defmodule RiddlrWeb.UnsubscribeControllerTest do
  use RiddlrWeb.ConnCase, async: true

  import Riddlr.AccountsFixtures

  alias Riddlr.Notifications

  setup do
    user = user_fixture() |> Ecto.Changeset.change(notify_email: true) |> Riddlr.Repo.update!()
    %{user: user, token: Notifications.unsubscribe_token(user)}
  end

  describe "GET /notifications/unsubscribe/:token" do
    test "shows a button that posts back, without login, and changes nothing",
         %{conn: conn, user: user, token: token} do
      html = conn |> get(~p"/notifications/unsubscribe/#{token}") |> html_response(200)

      assert has_selector?(
               html,
               "form#unsubscribe_form[method=post][action='/notifications/unsubscribe/#{token}']"
             )

      assert Riddlr.Repo.reload!(user).notify_email
    end

    test "shows no form for a bad token", %{conn: conn} do
      html = conn |> get(~p"/notifications/unsubscribe/nope") |> html_response(200)

      refute has_selector?(html, "#unsubscribe_form")
    end
  end

  describe "POST /notifications/unsubscribe/:token" do
    test "turns email off without login", %{conn: conn, user: user, token: token} do
      html = conn |> post(~p"/notifications/unsubscribe/#{token}") |> html_response(200)

      refute Riddlr.Repo.reload!(user).notify_email
      refute has_selector?(html, "#unsubscribe_form")
    end

    test "accepts a mail client's one-click POST body", %{conn: conn, user: user, token: token} do
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post(~p"/notifications/unsubscribe/#{token}", "List-Unsubscribe=One-Click")

      refute Riddlr.Repo.reload!(user).notify_email
    end

    # ConnTest always skips the CSRF check, so a request cannot prove mail
    # clients get through. Check the route skips the forgery plug instead.
    test "runs without the CSRF check", %{token: token} do
      info =
        Phoenix.Router.route_info(
          RiddlrWeb.Router,
          "POST",
          "/notifications/unsubscribe/#{token}",
          "localhost"
        )

      assert info.pipe_through == [:browser_without_csrf]
    end

    test "answers 400 for a bad token", %{conn: conn} do
      assert conn |> post(~p"/notifications/unsubscribe/nope") |> html_response(400)
    end
  end
end
