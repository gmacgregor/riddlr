defmodule RiddlrWeb.ContentSecurityPolicyTest do
  use RiddlrWeb.ConnCase, async: true

  # The policy as a map of directive => sources, so a test can check one
  # directive without caring about order.
  defp csp(conn) do
    [header] = get_resp_header(conn, "content-security-policy")

    header
    |> String.split(";", trim: true)
    |> Enum.map(&String.split(String.trim(&1), " "))
    |> Map.new(fn [directive | sources] -> {directive, sources} end)
  end

  test "a browser page sends a policy that allows only its own scripts", %{conn: conn} do
    policy = conn |> get(~p"/") |> csp()

    assert policy["default-src"] == ["'self'"]
    assert policy["script-src"] == ["'self'"]
    assert policy["object-src"] == ["'none'"]
    assert policy["base-uri"] == ["'self'"]
    assert policy["frame-ancestors"] == ["'self'"]
    assert policy["form-action"] == ["'self'"]
  end

  test "the policy allows Google Fonts, inline styles and data: images and fonts", %{conn: conn} do
    policy = conn |> get(~p"/") |> csp()

    assert "'unsafe-inline'" in policy["style-src"]
    assert "https://fonts.googleapis.com" in policy["style-src"]
    assert "https://fonts.gstatic.com" in policy["font-src"]
    assert "data:" in policy["font-src"]
    assert "data:" in policy["img-src"]
    assert policy["connect-src"] == ["'self'"]
  end

  test "the one-click unsubscribe pipeline sends the policy too", %{conn: conn} do
    policy = conn |> post(~p"/notifications/unsubscribe/bad-token") |> csp()

    assert policy["script-src"] == ["'self'"]
  end
end
