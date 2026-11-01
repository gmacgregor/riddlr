defmodule Riddlr.StandingsMonthTest do
  # Freezes the clock, which is global, so not async.
  use Riddlr.DataCase, async: false

  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  alias Riddlr.Clock.Frozen
  alias Riddlr.Standings

  defp went_live(riddle, at) do
    riddle |> Ecto.Changeset.change(live_date: at) |> Riddlr.Repo.update!()
  end

  describe "list(:points, :month)" do
    test "counts only riddles that went live in the current UTC month" do
      Frozen.freeze(~U[2026-11-15 12:00:00Z])

      this_month = riddle_fixture() |> went_live(~U[2026-11-01 00:00:00Z])
      last_month = riddle_fixture() |> went_live(~U[2026-10-31 23:59:59Z])

      ann = user_fixture(%{username: "ann"})
      bob = user_fixture(%{username: "bob"})

      solve_fixture(this_month, ann, %{placement: 1, points: 10})
      solve_fixture(last_month, bob, %{placement: 1, points: 10})
      solve_fixture(last_month, ann, %{placement: 2, points: 9})

      assert [%{username: "ann", points: 10, wins: 1, podiums: 1}] =
               Standings.list(:points, :month)

      assert [%{username: "ann", points: 19}, %{username: "bob", points: 10}] =
               Standings.list(:points, :all_time)
    end

    test "leaves out riddles that go live next month" do
      Frozen.freeze(~U[2026-11-30 23:59:59Z])

      next_month = riddle_fixture() |> went_live(~U[2026-12-01 00:00:00Z])
      solve_fixture(next_month, user_fixture(), %{placement: 1, points: 10})

      assert Standings.list(:points, :month) == []
    end
  end

  test "list(:wins, :month) only counts this month's wins" do
    Frozen.freeze(~U[2026-11-15 12:00:00Z])

    this_month = riddle_fixture() |> went_live(~U[2026-11-02 12:00:00Z])
    last_month = riddle_fixture() |> went_live(~U[2026-10-02 12:00:00Z])

    ann = user_fixture(%{username: "ann"})
    bob = user_fixture(%{username: "bob"})

    solve_fixture(this_month, ann, %{placement: 1, points: 10})
    solve_fixture(last_month, bob, %{placement: 1, points: 10})
    solve_fixture(this_month, bob, %{placement: 2, points: 9})

    assert [%{username: "ann", wins: 1}] = Standings.list(:wins, :month)
  end

  test "list(:fastest, :month) only counts this month's solves" do
    Frozen.freeze(~U[2026-11-15 12:00:00Z])

    this_month = riddle_fixture() |> went_live(~U[2026-11-02 12:00:00Z])
    last_month = riddle_fixture() |> went_live(~U[2026-10-02 12:00:00Z])
    ann = user_fixture(%{username: "ann"})

    solve_fixture(this_month, ann, %{solve_time_ms: 8_000})
    solve_fixture(last_month, ann, %{solve_time_ms: 1_000})

    assert [%{solve_time_ms: 8_000}] = Standings.list(:fastest, :month)
  end

  test "solves and entries count only this month's riddles" do
    Frozen.freeze(~U[2026-11-15 12:00:00Z])

    this_month = riddle_fixture() |> went_live(~U[2026-11-02 12:00:00Z])
    missed = riddle_fixture() |> went_live(~U[2026-11-03 12:00:00Z])
    last_month = riddle_fixture() |> went_live(~U[2026-10-02 12:00:00Z])
    ann = user_fixture(%{username: "ann"})

    for r <- [this_month, missed, last_month], do: entry_fixture(r, ann)
    solve_fixture(this_month, ann, %{placement: 1})
    solve_fixture(last_month, ann, %{placement: 1})

    assert [%{solves: 1, entries: 2}] = Standings.list(:points, :month)
    assert [%{solves: 2, entries: 3}] = Standings.list(:points, :all_time)
  end
end
