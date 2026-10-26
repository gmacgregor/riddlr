defmodule Riddlr.Gameplay.SolvesTest do
  use Riddlr.DataCase, async: true

  alias Riddlr.Gameplay
  alias Riddlr.Gameplay.Solve
  alias Riddlr.{AccountsFixtures, GamesFixtures}

  setup do
    riddle = GamesFixtures.riddle_fixture()
    [first, second] = for _ <- 1..2, do: AccountsFixtures.user_fixture()

    # Inserted out of order to prove the read sorts by placement.
    GamesFixtures.solve_fixture(riddle, second, %{placement: 2, points: 9, solve_time_ms: 5_000})
    GamesFixtures.solve_fixture(riddle, first, %{placement: 1, points: 10, solve_time_ms: 3_200})

    %{riddle: riddle, first: first, second: second}
  end

  describe "list_solves/1" do
    test "returns solves by placement with users loaded", %{
      riddle: riddle,
      first: first,
      second: second
    } do
      assert [
               %Solve{placement: 1, points: 10, solve_time_ms: 3_200, user: u1},
               %Solve{placement: 2, points: 9, user: u2}
             ] = Gameplay.list_solves(riddle.id)

      assert {u1.username, u2.username} == {first.username, second.username}
    end

    test "is empty for a riddle with no solves" do
      assert Gameplay.list_solves(GamesFixtures.riddle_fixture().id) == []
    end
  end

  describe "solve_for/2" do
    test "returns the user's solve", %{riddle: riddle, second: second} do
      assert %Solve{placement: 2, points: 9} = Gameplay.solve_for(riddle.id, second.id)
    end

    test "is nil when the user did not solve", %{riddle: riddle} do
      assert Gameplay.solve_for(riddle.id, AccountsFixtures.user_fixture().id) == nil
    end
  end

  describe "count_solves/1" do
    test "counts the riddle's solves", %{riddle: riddle} do
      assert Gameplay.count_solves(riddle.id) == 2
      assert Gameplay.count_solves(GamesFixtures.riddle_fixture().id) == 0
    end
  end
end
