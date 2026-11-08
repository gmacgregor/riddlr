defmodule Riddlr.SMS.AWS do
  @moduledoc """
  Sends texts through AWS End User Messaging SMS (`SendTextMessage`).

  Set `config :riddlr, Riddlr.SMS.AWS` with `:region`, `:access_key_id`,
  `:secret_access_key` and `:origination_identity` (the number or ID texts
  come from). `:req_options` merge into the request; tests use it to plug in
  a `Req.Test` stub.

  AWS handles STOP and HELP replies and the monthly spend cap. Its refusals
  come back as atoms:

    * `:opted_out` - the number texted STOP
    * `:not_verified` - sandbox only: the number is not a verified destination
    * `:spend_limit` - the monthly spend cap is reached
    * `:throttled` - too many requests
    * `{:aws, type}` - any other AWS error, by its type name
    * `:transport` - no response came back

  Errors never hold the number, the body or the raw response.
  """
  @behaviour Riddlr.SMS

  alias Riddlr.SMS.Message

  @impl Riddlr.SMS
  @spec deliver(Message.t()) :: :ok | {:error, atom() | {:aws, String.t()}}
  def deliver(%Message{to: to, body: body}) do
    config = Application.fetch_env!(:riddlr, __MODULE__)
    region = Keyword.fetch!(config, :region)

    response =
      [
        url: "https://sms-voice.#{region}.amazonaws.com/",
        method: :post,
        json: %{
          "DestinationPhoneNumber" => to,
          "OriginationIdentity" => Keyword.fetch!(config, :origination_identity),
          "MessageBody" => body,
          "MessageType" => "TRANSACTIONAL"
        },
        headers: [
          {"content-type", "application/x-amz-json-1.0"},
          {"x-amz-target", "PinpointSMSVoiceV2.SendTextMessage"}
        ],
        aws_sigv4: [
          access_key_id: Keyword.fetch!(config, :access_key_id),
          secret_access_key: Keyword.fetch!(config, :secret_access_key),
          service: "sms-voice",
          region: region
        ],
        decode_body: false,
        retry: false
      ]
      |> Req.new()
      |> Req.merge(Keyword.get(config, :req_options, []))
      |> Req.request()

    case response do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{} = response} -> {:error, error_reason(response)}
      {:error, _exception} -> {:error, :transport}
    end
  end

  @spec error_reason(Req.Response.t()) :: atom() | {:aws, String.t()}
  defp error_reason(response) do
    fields = decode_error_body(response.body)

    case {error_type(response, fields), fields["Reason"]} do
      {"ConflictException", "DESTINATION_PHONE_NUMBER_OPTED_OUT"} -> :opted_out
      {"ConflictException", "DESTINATION_PHONE_NUMBER_NOT_VERIFIED"} -> :not_verified
      {"ServiceQuotaExceededException", "MONTHLY_SPEND_LIMIT_REACHED_FOR_TEXT"} -> :spend_limit
      {"ThrottlingException", _} -> :throttled
      {type, _reason} -> {:aws, type}
    end
  end

  # The type sits in the `x-amzn-errortype` header ("Type:uri") or in the
  # body's `__type` ("namespace#Type").
  @spec error_type(Req.Response.t(), map()) :: String.t()
  defp error_type(response, fields) do
    case Req.Response.get_header(response, "x-amzn-errortype") do
      [header | _] -> header |> String.split(":") |> hd()
      [] -> fields |> Map.get("__type", "") |> String.split("#") |> List.last()
    end
    |> case do
      "" -> "Unknown"
      type -> type
    end
  end

  @spec decode_error_body(binary()) :: map()
  defp decode_error_body(body) do
    case Jason.decode(body) do
      {:ok, %{} = fields} -> fields
      _ -> %{}
    end
  end
end
