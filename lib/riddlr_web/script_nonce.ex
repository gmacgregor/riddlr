defmodule RiddlrWeb.ScriptNonce do
  @moduledoc """
  Lets a page run inline scripts that carry a fresh nonce.

  The browser pipeline's Content-Security-Policy allows only `'self'`
  scripts. This plug makes a random nonce for the request, assigns it as
  `:csp_nonce`, and adds `'nonce-…'` to the policy's `script-src`. Run it
  after the browser pipeline, so the policy header is already set.

  Only dev pages use it: LiveDashboard and the Swoosh mailbox preview have
  inline scripts.
  """
  @behaviour Plug

  import Plug.Conn

  @header "content-security-policy"

  @impl Plug
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> assign(:csp_nonce, nonce)
    |> update_policy(nonce)
  end

  # Puts the nonce first in script-src, so it does not matter which sources
  # the policy already lists there.
  @spec update_policy(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp update_policy(conn, nonce) do
    case get_resp_header(conn, @header) do
      [policy] ->
        put_resp_header(
          conn,
          @header,
          String.replace(policy, "script-src ", "script-src 'nonce-#{nonce}' ", global: false)
        )

      _ ->
        conn
    end
  end
end
