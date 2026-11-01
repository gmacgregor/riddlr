defmodule Riddlr.SMS.Test do
  @moduledoc "Test adapter: sends `{:sms, message}` to the calling process."
  @behaviour Riddlr.SMS

  @impl Riddlr.SMS
  def deliver(%Riddlr.SMS.Message{} = message) do
    send(self(), {:sms, message})
    :ok
  end
end
