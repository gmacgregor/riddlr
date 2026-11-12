defmodule Riddlr.Mailer.ResendApiClient do
  @moduledoc """
  The Swoosh API client for email. Sends with `Swoosh.ApiClient.Req`, but
  first fixes the custom headers in each Resend send.

  Resend wants `headers` as a JSON object of name to value. The
  `Swoosh.Adapters.Resend` in Swoosh 1.29.3 (and upstream `main` when this
  was written) sends a list of `{"name", "value"}` objects instead. Notification
  emails need their `List-Unsubscribe` and `List-Unsubscribe-Post` headers,
  so this client turns that list into an object for `POST /emails`. It leaves
  every other request as it is.

  Remove this module, and set `:swoosh, :api_client` back to
  `Swoosh.ApiClient.Req` in `config/prod.exs`, once a Swoosh release sends
  Resend headers as an object.
  """

  @behaviour Swoosh.ApiClient

  @resend_send_url "https://api.resend.com/emails"

  @impl true
  @spec init() :: :ok
  defdelegate init, to: Swoosh.ApiClient.Req

  @doc """
  Posts with `Swoosh.ApiClient.Req`. For a Resend send, first turns the
  `headers` list in `body` into an object.
  """
  @impl true
  @spec post(iodata(), [{String.t(), String.t()}], String.t(), Swoosh.Email.t()) ::
          {:ok, pos_integer(), list(), term()} | {:error, term()}
  def post(url, headers, body, email) do
    body =
      if IO.iodata_to_binary(url) == @resend_send_url, do: fix_headers(body), else: body

    Swoosh.ApiClient.Req.post(url, headers, body, email)
  end

  @spec fix_headers(String.t()) :: String.t()
  defp fix_headers(body) do
    case Jason.decode!(body) do
      %{"headers" => headers} = payload when is_list(headers) ->
        object = Map.new(headers, fn %{"name" => name, "value" => value} -> {name, value} end)
        Jason.encode!(%{payload | "headers" => object})

      _payload ->
        body
    end
  end
end
