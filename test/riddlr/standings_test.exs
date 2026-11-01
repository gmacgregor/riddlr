defmodule Riddlr.StandingsTest do
  use Riddlr.DataCase, async: true

  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  alias Riddlr.Standings

  defp names(rows), do: Enum.map(rows, & &1.username)

  defp went_live(riddle, at) do
    riddle |> Ecto.Changeset.change(live_date: at) |> Riddlr.Repo.update!()
  end

  defp set_status(user, status) do
    user |> Ecto.Changeset.change(account_status: status) |> Riddlr.Repo.update!()
  end

  describe "list(:points, :all_time)" do
    test "sums each player's points, wins and podiums across riddles" do
      [r1, r2, r3] = for _ <- 1..3, do: riddle_fixture()
      ann = user_fixture(%{username: "ann"})

      solve_fixture(r1, ann, %{placement: 1, points: 10})
      solve_fixture(r2, ann, %{placement: 3, points: 7})
      solve_fixture(r3, ann, %{placement: 5, points: 5})

      assert [row] = Standings.list(:points, :all_time)

      assert %{rank: 1, user_id: id, username: "ann", points: 22, wins: 1, podiums: 2} = row
      assert id == ann.id
    end

    test "breaks points ties on wins, then podiums, then username A–Z" do
      riddles = for _ <- 1..4, do: riddle_fixture()
      [r1, r2, r3, r4] = riddles

      # All on 10 points.
      winner = user_fixture(%{username: "zed"})
      podium = user_fixture(%{username: "yan"})
      bea = user_fixture(%{username: "bea"})
      abe = user_fixture(%{username: "abe"})

      solve_fixture(r1, winner, %{placement: 1, points: 10})
      solve_fixture(r2, podium, %{placement: 2, points: 9})
      solve_fixture(r3, podium, %{placement: 10, points: 1})
      solve_fixture(r1, bea, %{placement: 4, points: 6})
      solve_fixture(r2, bea, %{placement: 7, points: 4})
      solve_fixture(r3, abe, %{placement: 4, points: 6})
      solve_fixture(r4, abe, %{placement: 7, points: 4})

      assert names(Standings.list(:points, :all_time)) == ~w(zed yan abe bea)
    end

    test "exact ties share a rank and the next rank skips" do
      [r1, r2, r3] = for _ <- 1..3, do: riddle_fixture()
      top = user_fixture(%{username: "top"})
      amy = user_fixture(%{username: "amy"})
      bob = user_fixture(%{username: "bob"})
      low = user_fixture(%{username: "low"})

      solve_fixture(r1, top, %{placement: 1, points: 10})
      solve_fixture(r2, amy, %{placement: 2, points: 9})
      solve_fixture(r3, bob, %{placement: 2, points: 9})
      solve_fixture(r1, low, %{placement: 4, points: 7})

      ranks =
        Standings.list(:points, :all_time) |> Enum.map(&{&1.username, &1.rank})

      assert ranks == [{"top", 1}, {"amy", 2}, {"bob", 2}, {"low", 4}]
    end

    test "leaves out deleted, banned and suspended players, but not admins" do
      riddle = riddle_fixture()
      admin = user_fixture(%{username: "boss", role: :super_admin})
      banned = user_fixture(%{username: "banned"})
      suspended = user_fixture(%{username: "suspended"})
      gone = user_fixture(%{username: "gone"})

      solve_fixture(riddle, admin, %{placement: 1})
      solve_fixture(riddle, banned, %{placement: 2})
      solve_fixture(riddle, suspended, %{placement: 3})
      solve_fixture(riddle, gone, %{placement: 4})

      set_status(banned, :banned)
      set_status(suspended, :suspended)
      Riddlr.Repo.delete!(gone)

      assert names(Standings.list(:points, :all_time)) == ["boss"]
    end

    test "lists the top 50 only" do
      riddle = riddle_fixture()

      for place <- 1..51 do
        solve_fixture(riddle, user_fixture(), %{placement: place, points: 100 - place})
      end

      board = Standings.list(:points, :all_time)
      assert length(board) == 50
      assert List.last(board).points == 50
    end

    test "is empty when nobody has solved" do
      assert Standings.list(:points, :all_time) == []
    end
  end

  describe "list(:wins, window)" do
    test "orders by wins, then podiums, then points, shares exact ties and skips players with no wins" do
      [r1, r2, r3, r4] = for _ <- 1..4, do: riddle_fixture()
      ann = user_fixture(%{username: "ann"})
      bob = user_fixture(%{username: "bob"})
      cat = user_fixture(%{username: "cat"})
      dan = user_fixture(%{username: "dan"})
      eve = user_fixture(%{username: "eve"})

      solve_fixture(r1, ann, %{placement: 1, points: 10})
      solve_fixture(r2, bob, %{placement: 1, points: 10})
      solve_fixture(r3, cat, %{placement: 1, points: 10})
      solve_fixture(r3, bob, %{placement: 2, points: 9})
      solve_fixture(r4, eve, %{placement: 1, points: 10})
      solve_fixture(r4, dan, %{placement: 2, points: 9})
      solve_fixture(r4, cat, %{placement: 5, points: 6})

      ranks = Standings.list(:wins, :all_time) |> Enum.map(&{&1.username, &1.rank})

      # bob: 1 win, 2 podiums. cat: 1 win, 1 podium, 16 points.
      # ann and eve: 1 win, 1 podium, 10 points. dan never won.
      assert ranks == [{"bob", 1}, {"cat", 2}, {"ann", 3}, {"eve", 3}]
    end
  end

  describe "list(:podiums, window)" do
    test "orders by podiums, then wins, then points and skips players with no podium" do
      [r1, r2, r3] = for _ <- 1..3, do: riddle_fixture()
      ann = user_fixture(%{username: "ann"})
      bob = user_fixture(%{username: "bob"})
      cat = user_fixture(%{username: "cat"})
      dan = user_fixture(%{username: "dan"})
      eve = user_fixture(%{username: "eve"})

      solve_fixture(r1, ann, %{placement: 1, points: 10})
      solve_fixture(r1, cat, %{placement: 2, points: 9})
      solve_fixture(r1, bob, %{placement: 3, points: 8})
      solve_fixture(r1, dan, %{placement: 4, points: 7})
      solve_fixture(r2, bob, %{placement: 1, points: 10})
      solve_fixture(r2, cat, %{placement: 2, points: 9})
      solve_fixture(r2, dan, %{placement: 4, points: 7})
      solve_fixture(r3, eve, %{placement: 3, points: 8})
      solve_fixture(r3, dan, %{placement: 4, points: 7})
      solve_fixture(r3, cat, %{placement: 5, points: 6})

      # bob and cat: 2 podiums, but only bob won. cat has the most points.
      # ann: 1 podium, 1 win. eve: 1 podium. dan never made the podium.
      assert names(Standings.list(:podiums, :all_time)) == ~w(bob cat ann eve)
    end

    test "points break podium and win ties; exact ties share a rank, A–Z" do
      [r1, r2, r3] = for _ <- 1..3, do: riddle_fixture()
      hal = user_fixture(%{username: "hal"})
      ivy = user_fixture(%{username: "ivy"})
      jon = user_fixture(%{username: "jon"})
      kim = user_fixture(%{username: "kim"})

      # All on 1 podium and no wins. hal has the most points; the rest tie.
      solve_fixture(r1, hal, %{placement: 2, points: 9})
      solve_fixture(r1, kim, %{placement: 3, points: 8})
      solve_fixture(r2, jon, %{placement: 3, points: 8})
      solve_fixture(r3, ivy, %{placement: 3, points: 8})

      ranks = Standings.list(:podiums, :all_time) |> Enum.map(&{&1.username, &1.rank})

      assert ranks == [{"hal", 1}, {"ivy", 2}, {"jon", 2}, {"kim", 2}]
    end
  end

  describe "list(:fastest, window)" do
    test "shows each player once, with their fastest solve and its riddle" do
      slow = riddle_fixture(%{name: "Slow Riddle"})
      quick = riddle_fixture(%{name: "Quick Riddle"})
      ann = user_fixture(%{username: "ann"})

      solve_fixture(slow, ann, %{placement: 1, solve_time_ms: 9_000})
      solve_fixture(quick, ann, %{placement: 4, points: 7, solve_time_ms: 2_500})

      assert [row] = Standings.list(:fastest, :all_time)
      assert %{rank: 1, username: "ann", solve_time_ms: 2_500} = row
      assert row.riddle_name == "Quick Riddle"
      assert row.riddle_number == quick.number
    end

    test "orders by time, then earlier riddle, then A–Z; shares rank only on same time and date" do
      early = riddle_fixture() |> went_live(~U[2026-10-01 12:00:00Z])
      late = riddle_fixture() |> went_live(~U[2026-10-05 12:00:00Z])

      [ann, bob, cat, dan, eve] =
        for n <- ~w(ann bob cat dan eve), do: user_fixture(%{username: n})

      solve_fixture(late, eve, %{placement: 1, solve_time_ms: 1_000})
      solve_fixture(late, dan, %{placement: 2, solve_time_ms: 2_000})
      solve_fixture(early, cat, %{placement: 1, solve_time_ms: 2_000})
      solve_fixture(late, bob, %{placement: 3, solve_time_ms: 2_000})
      solve_fixture(early, ann, %{placement: 2, solve_time_ms: 5_000})

      ranks = Standings.list(:fastest, :all_time) |> Enum.map(&{&1.username, &1.rank})

      assert ranks == [{"eve", 1}, {"cat", 2}, {"bob", 3}, {"dan", 3}, {"ann", 5}]
    end

    test "skips solves with no time" do
      riddle = riddle_fixture()
      solve_fixture(riddle, user_fixture(), %{solve_time_ms: nil})

      assert Standings.list(:fastest, :all_time) == []
    end
  end

  describe "solves and entries" do
    test "every board carries each player's solves and entries" do
      [r1, r2, r3] = for _ <- 1..3, do: riddle_fixture()
      ann = user_fixture(%{username: "ann"})

      for r <- [r1, r2, r3], do: entry_fixture(r, ann)
      solve_fixture(r1, ann, %{placement: 1})
      solve_fixture(r2, ann, %{placement: 2})

      for board <- [:points, :wins, :podiums, :fastest] do
        assert [%{solves: 2, entries: 3}] = Standings.list(board, :all_time)
      end
    end
  end

  describe "player_row(user_id, board, window)" do
    test "gives the same rank list/2 would, even outside the top 50" do
      riddle = riddle_fixture()
      players = for place <- 1..52, do: {place, user_fixture()}

      # Places 50 and 51 tie on points, wins and podiums.
      for {place, user} <- players do
        points = if place == 51, do: 100 - 50, else: 100 - place
        solve_fixture(riddle, user, %{placement: place, points: points})
      end

      {51, tied} = Enum.at(players, 50)
      {52, last} = Enum.at(players, 51)

      assert %{rank: 50, user_id: id, points: 50} =
               Standings.player_row(tied.id, :points, :all_time)

      assert id == tied.id
      assert %{rank: 52} = Standings.player_row(last.id, :points, :all_time)
      assert %{solves: 1, entries: 0} = Standings.player_row(last.id, :points, :all_time)

      {1, top} = hd(players)

      assert Standings.player_row(top.id, :points, :all_time) ==
               hd(Standings.list(:points, :all_time))
    end

    test "works on the Fastest board" do
      riddle = riddle_fixture()
      ann = user_fixture()
      bob = user_fixture()
      solve_fixture(riddle, ann, %{placement: 1, solve_time_ms: 1_000})
      solve_fixture(riddle, bob, %{placement: 2, solve_time_ms: 2_000})

      assert %{rank: 2, solve_time_ms: 2_000} = Standings.player_row(bob.id, :fastest, :all_time)
    end

    test "is nil for a player not on the board" do
      riddle = riddle_fixture()
      ann = user_fixture()
      solve_fixture(riddle, ann, %{placement: 2, points: 9})

      assert Standings.player_row(ann.id, :wins, :all_time) == nil
      assert Standings.player_row(user_fixture().id, :points, :all_time) == nil
    end
  end
end
