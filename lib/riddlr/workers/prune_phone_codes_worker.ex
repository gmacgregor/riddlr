defmodule Riddlr.Workers.PrunePhoneCodesWorker do
  @moduledoc """
  Runs every minute from Oban's cron. Wipes pending numbers whose code has
  expired, and deletes sent-code rows older than a day. The work lives in
  `Riddlr.Accounts.prune_phone_codes/0`.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Riddlr.Accounts.prune_phone_codes()
    :ok
  end
end
