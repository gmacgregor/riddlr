defmodule Riddlr.SMS.Local do
  @moduledoc "Dev adapter: logs the text with only the last four digits shown."
  @behaviour Riddlr.SMS

  require Logger

  @impl Riddlr.SMS
  def deliver(%Riddlr.SMS.Message{to: to, body: body}) do
    Logger.info("SMS to #{Riddlr.SMS.mask(to)}: #{body}")
    :ok
  end
end
