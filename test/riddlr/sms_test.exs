defmodule Riddlr.SMSTest do
  use ExUnit.Case, async: true

  alias Riddlr.SMS.Message

  test "inspecting a message hides the number and the body" do
    inspected = inspect(%Message{to: "+14165550123", body: "Your code is 123456"})

    refute inspected =~ "4165550123"
    refute inspected =~ "123456"
  end
end
