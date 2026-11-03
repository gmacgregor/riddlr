defmodule Riddlr.SMS.LocalTest do
  # Lowers the global log level, which other tests would see.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Riddlr.SMS.Local
  alias Riddlr.SMS.Message

  setup do
    # The test config only lets warnings through.
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)
  end

  test "logs the text with only the last four digits of the number" do
    message = %Message{to: "+14165550123", body: "Your code is 123456"}

    log = capture_log(fn -> assert :ok = Local.deliver(message) end)

    assert log =~ "•••• 0123"
    assert log =~ "Your code is 123456"
    refute log =~ "4165550123"
  end
end
