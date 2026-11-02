defmodule Riddlr.Workers.PrunePhoneCodesWorker do
  @moduledoc """
  Runs every hour from Oban's cron. Wipes pending numbers whose code has
  expired, numbers held from sign-up for over a day, and deletes sent-code
  rows older than a day. Codes still fail after 10 minutes between runs: the
  check reads the send time. The work lives in
  `Riddlr.Accounts.prune_phone_codes/0`.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Riddlr.Accounts.prune_phone_codes()
    :ok
  end
end
