defmodule RiddlrWeb.ProfilePhoneTest do
  # One test changes the global SMS adapter config, so this module cannot run
  # async. Others freeze the clock.
  use RiddlrWeb.ConnCase, async: false

  setup :register_and_log_in_user

  @ca "(416) 555-0123"

  describe "GET /profile" do
    test "offers to add a number, with the Canada-only note", %{conn: conn} do
      html = conn |> get(~p"/profile") |> html_response(200)

      assert has_selector?(html, "input[form=send_phone_code][name='phone[phone]'][type='tel']")
      assert has_selector?(html, ".rg-notify__phone .rg-phone__canada-note")
      assert has_selector?(html, "form#send_phone_code input[name='_method'][value='put']")
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

  describe "Text in the Notify me group" do
    test "shows a Text box, with the number step under it, gated on the box",
         %{conn: conn} do
      html = conn |> get(~p"/profile") |> html_response(200)
      group = "#update_notifications fieldset.rg-notify"

      assert has_selector?(html, "#{group} input[type=checkbox][name='user[notify_sms]']")
      refute has_selector?(html, "#{group} input[name='user[notify_sms]'][checked]")

      assert has_selector?(
               html,
               "#{group} .rg-notify__phone[data-needs-text] input[form=send_phone_code][name='phone[phone]']"
             )

      assert has_selector?(
               html,
               "#{group} .rg-notify__consent a[href='http://localhost:4000/info']"
             )
    end

    test "saving Text with no confirmed number shows an error and keeps Text off",
         %{conn: conn, user: user} do
      html =
        conn
        |> put(~p"/profile", %{
          "action" => "update_notifications",
          "user" => %{"notify_sms" => "true"}
        })
        |> html_response(200)

      assert has_selector?(
               html,
               ".rg-field:has(input[type=checkbox][name='user[notify_sms]']) .rg-field__error"
             )

      refute Riddlr.Accounts.get_user!(user.id).notify_sms
    end

    test "confirming a first number ticks Text; unticking pauses and keeps the number",
         %{conn: conn, user: user} do
      code = conn |> send_code(@ca) |> code_from_text()
      confirm(conn, code)

      html = conn |> get(~p"/profile") |> html_response(200)
      assert has_selector?(html, "input[name='user[notify_sms]'][checked]")
      refute has_selector?(html, "[data-needs-text]")

      put(conn, ~p"/profile", %{
        "action" => "update_notifications",
        "user" => %{"notify_sms" => "false"}
      })

      user = Riddlr.Accounts.get_user!(user.id)
      refute user.notify_sms
      assert user.phone == "+14165550123"

      html = conn |> get(~p"/profile") |> html_response(200)
      refute has_selector?(html, "input[name='user[notify_sms]'][checked]")
      assert has_selector?(html, "#phone-confirmed")
    end

    test "a refused number stays shown with its error, Text box or not", %{conn: conn} do
      html = conn |> send_code("(212) 555-0123") |> html_response(200)

      assert has_selector?(html, "input[form=send_phone_code][name='phone[phone]']")
      refute has_selector?(html, "[data-needs-text]")
    end
  end

  describe "PUT /profile (send_phone_code)" do
    test "shows an error under the field for a number outside Canada", %{conn: conn} do
      html = conn |> send_code("(212) 555-0123") |> html_response(200)

      assert has_selector?(html, "input[form=send_phone_code][name='phone[phone]'][aria-invalid]")
      refute_received {:sms, _}
    end

    test "texts a code and moves to the code step, showing only the last 4 digits",
         %{conn: conn} do
      assert conn |> send_code(@ca) |> redirected_to() == ~p"/profile"
      assert_received {:sms, _}

      html = conn |> get(~p"/profile") |> html_response(200)

      assert has_selector?(html, "input[form=confirm_phone][name='phone[code]']")
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

    test "shows an error and sends nothing when the send limit is hit", %{conn: conn} do
      for _ <- 1..3, do: conn |> send_code(@ca) |> code_from_text()

      conn = put(conn, ~p"/profile", %{"action" => "resend_phone_code"})

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
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
      refute has_selector?(html, "#send_phone_code")
      refute has_selector?(html, "[name='user[notify_sms]']")

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

    test "a wrong code marks the code field and keeps the code step", %{conn: conn} do
      code = conn |> send_code(@ca) |> code_from_text()

      html = conn |> confirm(wrong(code)) |> html_response(200)

      assert has_selector?(html, "input[form=confirm_phone][name='phone[code]'][aria-invalid]")
    end

    test "the 5th wrong code shows an error and blocks new codes", %{conn: conn} do
      code = conn |> send_code(@ca) |> code_from_text()
      for _ <- 1..4, do: confirm(conn, wrong(code))

      conn = confirm(conn, wrong(code))

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)

      conn = send_code(conn, "(613) 555-0199")
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      refute_received {:sms, _}
    end

    test "an expired code shows an error and leaves no number", %{conn: conn, user: user} do
      Riddlr.Clock.Frozen.freeze()
      code = conn |> send_code(@ca) |> code_from_text()
      Riddlr.Clock.Frozen.advance(10, :minute)

      conn = confirm(conn, code)

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Riddlr.Accounts.get_user!(user.id).phone == nil
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
