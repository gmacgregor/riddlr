defmodule RiddlrWeb.LiveAuthQueriesTest do
  # Counts every query on the node.
  use RiddlrWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Riddlr.CacheHelpers

  alias Riddlr.AccountsFixtures

  test "a LiveView's first render looks the session token up once", %{conn: conn} do
    conn = log_in_user(conn, AccountsFixtures.user_fixture())

    {sources, conn} = query_sources(fn -> get(conn, ~p"/") end)

    assert html_response(conn, 200)
    assert Enum.count(sources, &(&1 == "users_tokens")) == 1
  end

  test "an admin LiveView's first render looks the session token up once", %{conn: conn} do
    conn = log_in_user(conn, AccountsFixtures.user_fixture(%{role: :editor}))

    {sources, conn} = query_sources(fn -> get(conn, ~p"/admin/riddles") end)

    assert html_response(conn, 200)
    assert Enum.count(sources, &(&1 == "users_tokens")) == 1
  end

  test "the connected mount looks the token up again, so a ban since load counts", %{
    conn: conn
  } do
    user = AccountsFixtures.user_fixture()
    conn = conn |> log_in_user(user) |> get(~p"/")
    refute html_response(conn, 200) =~ ~s(id="join-note")

    # A ban deletes the user's tokens, so the session's token finds no one.
    {:ok, _} = Riddlr.Accounts.set_user_status(user, :banned)

    {:ok, live, _html} = live(conn)
    assert has_element?(live, "#join-note")
  end
end
