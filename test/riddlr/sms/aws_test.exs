defmodule Riddlr.SMS.AWSTest do
  use ExUnit.Case, async: true

  alias Riddlr.SMS.AWS
  alias Riddlr.SMS.Message

  @message %Message{to: "+14165550123", body: "Your Riddlr code is 123456."}

  test "posts a signed SendTextMessage request and returns :ok" do
    Req.Test.stub(AWS, fn conn ->
      assert conn.method == "POST"
      assert conn.host == "sms-voice.ca-central-1.amazonaws.com"

      assert Plug.Conn.get_req_header(conn, "x-amz-target") ==
               ["PinpointSMSVoiceV2.SendTextMessage"]

      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/x-amz-json-1.0"]
      assert [auth] = Plug.Conn.get_req_header(conn, "authorization")
      assert auth =~ ~r/^AWS4-HMAC-SHA256 .*sms-voice/

      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "DestinationPhoneNumber" => "+14165550123",
               "OriginationIdentity" => "+15555550100",
               "MessageBody" => "Your Riddlr code is 123456.",
               "MessageType" => "TRANSACTIONAL"
             }

      conn
      |> Plug.Conn.put_resp_content_type("application/x-amz-json-1.0")
      |> Plug.Conn.send_resp(200, ~s({"MessageId":"abc"}))
    end)

    assert AWS.deliver(@message) == :ok
  end

  test "maps an opted-out number to :opted_out" do
    stub_error(400, "ConflictException", %{"Reason" => "DESTINATION_PHONE_NUMBER_OPTED_OUT"})
    assert_error(:opted_out)
  end

  test "maps an unverified sandbox number to :not_verified" do
    stub_error(400, "ConflictException", %{"Reason" => "DESTINATION_PHONE_NUMBER_NOT_VERIFIED"})
    assert_error(:not_verified)
  end

  test "maps the monthly spend cap to :spend_limit" do
    stub_error(402, "ServiceQuotaExceededException", %{
      "Reason" => "MONTHLY_SPEND_LIMIT_REACHED_FOR_TEXT"
    })

    assert_error(:spend_limit)
  end

  test "maps throttling to :throttled" do
    stub_error(400, "ThrottlingException", %{})
    assert_error(:throttled)
  end

  test "maps any other AWS error to {:aws, type}, with no number or body in it" do
    stub_error(500, "InternalServerException", %{})

    assert_error({:aws, "InternalServerException"})
  end

  test "reads the type from __type when the header is missing" do
    Req.Test.stub(AWS, fn conn ->
      body = ~s({"__type":"com.amazonaws.pinpointsmsvoicev2#ValidationException"})
      Plug.Conn.send_resp(conn, 400, body)
    end)

    assert_error({:aws, "ValidationException"})
  end

  test "gives {:aws, \"Unknown\"} when the error names no type" do
    Req.Test.stub(AWS, &Plug.Conn.send_resp(&1, 503, "Service Unavailable"))
    assert_error({:aws, "Unknown"})
  end

  test "maps a transport failure to :transport" do
    Req.Test.stub(AWS, &Req.Test.transport_error(&1, :econnrefused))
    assert_error(:transport)
  end

  # Every error must leave out the number and the body.
  defp assert_error(expected) do
    assert {:error, reason} = AWS.deliver(@message)
    assert reason == expected
    refute inspect(reason) =~ "4165550123"
    refute inspect(reason) =~ "123456"
  end

  # AWS JSON-1.0 errors name their type in `x-amzn-errortype` and in `__type`.
  defp stub_error(status, type, fields) do
    Req.Test.stub(AWS, fn conn ->
      body = Map.put(fields, "__type", "com.amazonaws.pinpointsmsvoicev2##{type}")

      conn
      |> Plug.Conn.put_resp_header("x-amzn-errortype", "#{type}:http://internal.amazon.com/")
      |> Plug.Conn.put_resp_content_type("application/x-amz-json-1.0")
      |> Plug.Conn.send_resp(status, Jason.encode!(Map.put(body, "Message", "+14165550123")))
    end)
  end
end
