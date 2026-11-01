defmodule RiddlrWeb.ProfilePhoneTest do
  # One test changes the global SMS adapter config, so this module cannot run
  # async. Others freeze the clock.
  use RiddlrWeb.ConnCase, async: false

  setup :register_and_log_in_user

  @ca "(416) 555-0123"

  describe "GET /profile" do
    test "offers to add a number, with the Canada-only note", %{conn: conn} do
      html = conn |> get(~p"/profile") |> html_response(200)

      assert has_selector?(html, "#send_phone_code input[name='phone[phone]'][type='tel']")
      assert has_selector?(html, "#send_phone_code .rg-phone__canada-note")
      assert has_selector?(html, "#send_phone_code input[name='_method'][value='put']")
    end

    test "?phone=new offers a new number while a code is pending", %{conn: conn} do
      conn |> send_code(@ca) |> code_from_text()

      html = conn |> get(~p"/profile?phone=new") |> html_response(200)

      assert has_selector?(html, "#send_phone_code")
      refute has_selector?(html, "#confirm_phone")
    end

    test "a confirmed number shows with change and remove, and ?phone=new keeps it shown",
         %{conn: conn} do
      code = conn |> send_code(@ca) |> code_from_text()
      confirm(conn, code)

      html = conn |> get(~p"/profile") |> html_response(200)
      assert has_selector?(html, "#phone-confirmed a[href='/profile?phone=new']")
      assert has_selector?(html, "#remove_phone")
      refute has_selector?(html, "#send_phone_code")

      html = conn |> get(~p"/profile?phone=new") |> html_response(200)
      assert has_selector?(html, "#phone-confirmed")
      assert has_selector?(html, "#send_phone_code")
    end
  end

  describe "PUT /profile (send_phone_code)" do
    test "shows an error under the field for a number outside Canada", %{conn: conn} do
      html = conn |> send_code("(212) 555-0123") |> html_response(200)

      assert html =~ "must be a Canadian number"
      refute_received {:sms, _}
    end

    test "texts a code and moves to the code step, showing only the last 4 digits",
         %{conn: conn} do
      assert conn |> send_code(@ca) |> redirected_to() == ~p"/profile"
      assert_received {:sms, _}

      html = conn |> get(~p"/profile") |> html_response(200)

      assert has_selector?(html, "#confirm_phone input[name='phone[code]']")
      refute has_selector?(html, "#send_phone_code")
      assert html =~ "•••• 0123"
      refute html =~ "555"
    end
  end

  describe "PUT /profile (resend_phone_code)" do
    test "texts a new code to the pending number", %{conn: conn} do
      conn |> send_code(@ca) |> code_from_text()

      conn = put(conn, ~p"/profile", %{"action" => "resend_phone_code"})

      assert redirected_to(conn) == ~p"/profile"
      assert_received {:sms, %{to: "+14165550123"}}
    end

    test "says so when the send limit is hit", %{conn: conn} do
      for _ <- 1..3, do: conn |> send_code(@ca) |> code_from_text()

      conn = put(conn, ~p"/profile", %{"action" => "resend_phone_code"})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many codes"
      refute_received {:sms, _}
    end
  end

  describe "with no SMS adapter" do
    setup do
      original = Application.get_env(:riddlr, Riddlr.SMS)
      Application.put_env(:riddlr, Riddlr.SMS, adapter: nil)
      on_exit(fn -> Application.put_env(:riddlr, Riddlr.SMS, original) end)
    end

    test "hides the phone section and refuses phone actions", %{conn: conn} do
      html = conn |> get(~p"/profile") |> html_response(200)
      refute has_selector?(html, "#profile-phone")

      conn = send_code(conn, @ca)
      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Riddlr.Accounts.get_pending_phone_code(conn.assigns.current_scope.user) == nil
    end
  end

  describe "PUT /profile (remove_phone)" do
    test "removes the number and offers to add one again", %{conn: conn} do
      code = conn |> send_code(@ca) |> code_from_text()
      confirm(conn, code)

      conn = put(conn, ~p"/profile", %{"action" => "remove_phone"})
      assert redirected_to(conn) == ~p"/profile"

      html = conn |> get(~p"/profile") |> html_response(200)
      refute has_selector?(html, "#phone-confirmed")
      assert has_selector?(html, "#send_phone_code")
    end
  end

  describe "PUT /profile (confirm_phone)" do
    test "the right code shows the number as confirmed", %{conn: conn} do
      code = conn |> send_code(@ca) |> code_from_text()

      assert conn |> confirm(code) |> redirected_to() == ~p"/profile"

      html = conn |> get(~p"/profile") |> html_response(200)
      assert has_selector?(html, "#phone-confirmed")
      assert html =~ "•••• 0123"
      refute has_selector?(html, "#send_phone_code")
      refute has_selector?(html, "#confirm_phone")
    end

    test "a wrong code says so and keeps the code step", %{conn: conn} do
      code = conn |> send_code(@ca) |> code_from_text()

      html = conn |> confirm(wrong(code)) |> html_response(200)

      assert has_selector?(html, "#confirm_phone input[name='phone[code]']")
      assert html =~ "Invalid verification code. Try again"
    end

    test "the 5th wrong code says to try again in 24 hours", %{conn: conn} do
      code = conn |> send_code(@ca) |> code_from_text()
      for _ <- 1..4, do: confirm(conn, wrong(code))

      conn = confirm(conn, wrong(code))

      assert redirected_to(conn) == ~p"/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Maximum verification attempts exceeded. Try again in 24hrs."
    end

    test "an expired code says to send a new one", %{conn: conn} do
      Riddlr.Clock.Frozen.freeze()
      code = conn |> send_code(@ca) |> code_from_text()
      Riddlr.Clock.Frozen.advance(10, :minute)

      conn = confirm(conn, code)

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    end
  end

  defp wrong(code), do: if(code == "000000", do: "111111", else: "000000")

  defp confirm(conn, code) do
    put(conn, ~p"/profile", %{"action" => "confirm_phone", "phone" => %{"code" => code}})
  end

  defp code_from_text(_conn) do
    assert_received {:sms, %{body: body}}
    [code] = Regex.run(~r/\b\d{6}\b/, body)
    code
  end

  defp send_code(conn, phone) do
    put(conn, ~p"/profile", %{"action" => "send_phone_code", "phone" => %{"phone" => phone}})
  end
end
