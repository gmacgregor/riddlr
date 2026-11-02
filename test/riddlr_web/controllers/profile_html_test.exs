defmodule RiddlrWeb.ProfileHTMLTest do
  use ExUnit.Case, async: true

  alias Riddlr.Accounts.User
  alias RiddlrWeb.ProfileHTML

  @confirmed %User{
    phone: "+14165551234",
    phone_confirmed_at: ~U[2026-11-01 12:00:00Z],
    notification_lead_time: :min_30
  }

  describe "notification_summary/1" do
    test "names each channel on, with the last 4 digits for Text" do
      assert ProfileHTML.notification_summary(%{
               @confirmed
               | notify_email: true,
                 notify_sms: true
             }) ==
               "Email + Text (•••• 1234), 30 min before"

      assert ProfileHTML.notification_summary(%{@confirmed | notify_sms: true}) ==
               "Text (•••• 1234), 30 min before"

      assert ProfileHTML.notification_summary(%{@confirmed | notify_email: true}) ==
               "Email, 30 min before"
    end

    test "is Off with no channel on" do
      assert ProfileHTML.notification_summary(@confirmed) == "Off"
    end
  end
end
