defmodule Riddlr.SMS do
  @moduledoc """
  Sends text messages through the adapter set in
  `config :riddlr, Riddlr.SMS, adapter: ...`. With no adapter, texting is off
  and the phone UI stays hidden.

  Adapters: `Riddlr.SMS.Local` logs in dev; `Riddlr.SMS.Test` sends to the
  test process; `Riddlr.SMS.AWS` sends real texts in prod.
  """

  defmodule Message do
    @moduledoc "One text: an E.164 number and a body."
    @enforce_keys [:to, :body]
    # The body carries one-time codes, so it stays out of logs and crash
    # reports, as the number does.
    @derive {Inspect, except: [:to, :body]}
    defstruct [:to, :body]

    @type t :: %__MODULE__{to: String.t(), body: String.t()}
  end

  @doc "Delivers one text. Never log `message.to`."
  @callback deliver(Message.t()) :: :ok | {:error, term()}

  @doc "Whether an adapter is set, i.e. players can add a phone."
  @spec enabled?() :: boolean()
  def enabled?, do: adapter() != nil

  @doc "Sends `message` through the configured adapter."
  @spec deliver(Message.t()) :: :ok | {:error, term()}
  def deliver(%Message{} = message) do
    case adapter() do
      nil -> {:error, :sms_disabled}
      adapter -> adapter.deliver(message)
    end
  end

  @doc "The last four digits of an E.164 number, e.g. \"•••• 1234\"."
  @spec mask(String.t()) :: String.t()
  def mask(e164) when is_binary(e164), do: "•••• " <> String.slice(e164, -4, 4)

  @spec adapter() :: module() | nil
  defp adapter do
    :riddlr |> Application.get_env(__MODULE__, []) |> Keyword.get(:adapter)
  end
end
