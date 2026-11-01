defmodule Riddlr.Workers.PrunePhoneCodesWorkerTest do
  # Freezes the global clock.
  use Riddlr.DataCase, async: false
  use Oban.Testing, repo: Riddlr.Repo

  import Riddlr.AccountsFixtures

  alias Riddlr.Accounts
  alias Riddlr.Accounts.PhoneCode
  alias Riddlr.Clock.Frozen
  alias Riddlr.Workers.PrunePhoneCodesWorker

  setup do
    Frozen.freeze()
    user = user_fixture()
    {:ok, _} = Accounts.send_phone_code(user, %{"phone" => "(416) 555-0123"})
    %{user: user}
  end

  test "keeps a pending number while its code is live", %{user: user} do
    Frozen.advance(9, :minute)
    assert :ok = perform_job(PrunePhoneCodesWorker, %{})

    assert {:ok, _} = Accounts.resend_phone_code(user)
  end

  test "wipes the pending number once its code expires", %{user: user} do
    Frozen.advance(10, :minute)
    assert :ok = perform_job(PrunePhoneCodesWorker, %{})

    assert {:error, :no_code} = Accounts.resend_phone_code(user)

    %{rows: [[phone, code_hash]]} =
      Repo.query!("SELECT phone, code_hash FROM phone_codes WHERE user_id = $1", [user.id])

    assert {phone, code_hash} == {nil, nil}
  end

  test "deletes rows after a day" do
    Frozen.advance(1, :day)
    assert :ok = perform_job(PrunePhoneCodesWorker, %{})

    assert Repo.aggregate(PhoneCode, :count) == 0
  end
end
