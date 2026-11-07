defmodule RiddlrWeb.ScriptNonceTest do
  use RiddlrWeb.ConnCase, async: true

  alias RiddlrWeb.ScriptNonce

  defp with_policy(conn) do
    Plug.Conn.put_resp_header(
      conn,
      "content-security-policy",
      "default-src 'self'; script-src 'self'; style-src 'self'"
    )
  end

  test "assigns a nonce and allows it in script-src", %{conn: conn} do
    conn = conn |> with_policy() |> ScriptNonce.call(ScriptNonce.init([]))

    nonce = conn.assigns.csp_nonce
    assert is_binary(nonce) and byte_size(nonce) > 0

    assert get_resp_header(conn, "content-security-policy") == [
             "default-src 'self'; script-src 'nonce-#{nonce}' 'self'; style-src 'self'"
           ]
  end

  test "allows the nonce whatever sources script-src already lists", %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_resp_header(
        "content-security-policy",
        "script-src https://a.example 'self'"
      )
      |> ScriptNonce.call(ScriptNonce.init([]))

    assert get_resp_header(conn, "content-security-policy") == [
             "script-src 'nonce-#{conn.assigns.csp_nonce}' https://a.example 'self'"
           ]
  end

  test "makes a new nonce for each request", %{conn: conn} do
    a = conn |> with_policy() |> ScriptNonce.call(ScriptNonce.init([]))
    b = build_conn() |> with_policy() |> ScriptNonce.call(ScriptNonce.init([]))

    refute a.assigns.csp_nonce == b.assigns.csp_nonce
  end
end
