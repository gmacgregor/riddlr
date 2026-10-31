defmodule RiddlrWeb.StylesheetsTest do
  use RiddlrWeb.ConnCase, async: true

  alias Riddlr.AccountsFixtures

  @admin_sheets ~w(admin-tokens.css admin-base.css admin.css)
  @player_sheets ~w(themes.css game.css auth.css)

  defp stylesheets(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(~s(link[rel="stylesheet"]))
    |> LazyHTML.attribute("href")
    |> Enum.map(&(&1 |> URI.parse() |> Map.fetch!(:path) |> Path.basename()))
  end

  test "an admin page loads only the admin stylesheets", %{conn: conn} do
    admin = AccountsFixtures.user_fixture(%{role: :editor})

    sheets =
      conn |> log_in_user(admin) |> get(~p"/admin/riddles") |> html_response(200) |> stylesheets()

    for sheet <- @admin_sheets, do: assert(sheet in sheets)
    for sheet <- @player_sheets, do: refute(sheet in sheets)
  end

  test "a player page loads only the player stylesheets", %{conn: conn} do
    sheets = conn |> get(~p"/") |> html_response(200) |> stylesheets()

    for sheet <- @player_sheets, do: assert(sheet in sheets)
    for sheet <- @admin_sheets, do: refute(sheet in sheets)
  end

  test "an account page loads only the player stylesheets", %{conn: conn} do
    sheets = conn |> get(~p"/users/log-in") |> html_response(200) |> stylesheets()

    for sheet <- @player_sheets, do: assert(sheet in sheets)
    for sheet <- @admin_sheets, do: refute(sheet in sheets)
  end
end
