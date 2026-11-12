defmodule Riddlr.MailerResendTest do
  # Sets the global Swoosh API client, so not async.
  use Riddlr.DataCase, async: false

  import Swoosh.Email, except: [from: 2]

  alias Riddlr.Mailer

  @api_key "re_test_synthetic_key"
  @config [adapter: Swoosh.Adapters.Resend, api_key: @api_key]

  # Notifications build the email inside `deliver/2`, so this client adds
  # the stub route before the real one sends.
  defmodule StubClient do
    @moduledoc false
    @behaviour Swoosh.ApiClient

    @impl true
    def post(url, headers, body, email) do
      email =
        Swoosh.Email.put_private(email, :client_options,
          plug: {Req.Test, Riddlr.MailerResendTest},
          retry: false
        )

      Riddlr.Mailer.ResendApiClient.post(url, headers, body, email)
    end
  end

  setup do
    previous = Application.fetch_env!(:swoosh, :api_client)
    Application.put_env(:swoosh, :api_client, Riddlr.Mailer.ResendApiClient)
    on_exit(fn -> Application.put_env(:swoosh, :api_client, previous) end)
  end

  # Routes the request to the Req.Test stub, with no automatic retry.
  defp via_stub(email),
    do: put_private(email, :client_options, plug: {Req.Test, __MODULE__}, retry: false)

  # Stubs Resend, sends the request payload to the test and replies `status`.
  defp stub_resend(status, reply) do
    test = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:resend, conn, Jason.decode!(body)})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(reply))
    end)
  end

  test "posts an account email to Resend and returns its id" do
    stub_resend(200, %{id: "email-123"})

    assert {:ok, %{id: "email-123"}} = account_email() |> via_stub() |> Mailer.deliver(@config)

    assert_received {:resend, conn, payload}
    assert conn.method == "POST"
    assert conn.host == "api.resend.com"
    assert conn.request_path == "/emails"
    assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer #{@api_key}"]

    assert payload == %{
             "from" => "Kriddle <hello@kriddle.test>",
             "to" => ["player@example.com"],
             "subject" => "Log in instructions",
             "text" => "Log in here: https://kriddle.test/users/log-in/abc"
           }
  end

  test "sends a Notification's unsubscribe headers as a JSON object, without the riddle text" do
    stub_resend(200, %{id: "email-456"})

    riddle = Riddlr.GamesFixtures.scheduled_riddle_fixture() |> Repo.preload(:category)
    user = Riddlr.AccountsFixtures.user_fixture()
    email = Riddlr.Notifications.Email.notification(riddle, user, "token", DateTime.utc_now())

    assert {:ok, %{id: "email-456"}} = email |> via_stub() |> Mailer.deliver(@config)

    assert_received {:resend, _conn, payload}

    assert payload["headers"] == %{
             "List-Unsubscribe" => email.headers["List-Unsubscribe"],
             "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click"
           }

    refute payload["subject"] =~ riddle.description
    refute payload["text"] =~ riddle.description
  end

  describe "a Notification sent through Notifications.deliver/2" do
    alias Riddlr.Clock.Frozen
    alias Riddlr.Notifications
    alias Riddlr.Notifications.RiddleNotification

    setup do
      Application.put_env(:swoosh, :api_client, StubClient)

      riddle = Riddlr.GamesFixtures.scheduled_riddle_fixture()

      Riddlr.AccountsFixtures.user_fixture()
      |> Ecto.Changeset.change(notify_email: true)
      |> Repo.update!()

      {:ok, 1} = Notifications.fan_out(riddle.id, :lobby_open)
      row = Repo.get_by!(RiddleNotification, riddle_id: riddle.id)
      Frozen.freeze(DateTime.add(riddle.live_date, -600, :second))

      %{row: row}
    end

    test "stays unsent after a rejection and sends once on a later retry", %{row: row} do
      stub_resend(500, %{name: "application_error", message: "Try again."})

      assert {:error, {500, _}} = Notifications.deliver(row.id, mailer_config: @config)
      assert_received {:resend, _conn, _payload}
      assert %{sent_at: nil, sending_at: nil} = Repo.reload!(row)

      stub_resend(200, %{id: "email-789"})

      assert {:ok, %{sent_at: %DateTime{}}} =
               Notifications.deliver(row.id, mailer_config: @config)

      assert_received {:resend, _conn, _payload}
      assert %{sent_at: %DateTime{}, sending_at: nil} = Repo.reload!(row)

      assert {:skip, _} = Notifications.deliver(row.id, mailer_config: @config)
      refute_received {:resend, _conn, _payload}
    end
  end

  test "returns an error when Resend rejects the request" do
    stub_resend(422, %{name: "validation_error", message: "Invalid `from` field."})

    assert {:error, {422, %{"name" => "validation_error"}}} =
             account_email() |> via_stub() |> Mailer.deliver(@config)
  end

  test "returns an error when the request cannot reach Resend" do
    Req.Test.stub(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             account_email() |> via_stub() |> Mailer.deliver(@config)
  end

  defp account_email do
    new()
    |> to("player@example.com")
    |> Swoosh.Email.from({"Kriddle", "hello@kriddle.test"})
    |> subject("Log in instructions")
    |> text_body("Log in here: https://kriddle.test/users/log-in/abc")
  end
end
