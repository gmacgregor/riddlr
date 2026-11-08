defmodule RiddlrWeb.InfoControllerTest do
  use RiddlrWeb.ConnCase, async: true

  test "GET /info shows the page without login, with how to stop texts", %{conn: conn} do
    html = conn |> get(~p"/info") |> html_response(200)

    assert html =~ "STOP"
    assert html =~ "HELP"
  end

  test "GET /info links the contact address from config", %{conn: conn} do
    {_name, address} = Application.fetch_env!(:riddlr, :mail_from)
    html = conn |> get(~p"/info") |> html_response(200)

    assert has_selector?(html, "#info-contact a[href='mailto:#{address}']")
  end

  test "GET /info says STOP keeps the number until the player removes it", %{conn: conn} do
    html = conn |> get(~p"/info") |> html_response(200)

    assert has_selector?(html, "#info-privacy #info-after-stop a[href='/profile']")
  end
end
