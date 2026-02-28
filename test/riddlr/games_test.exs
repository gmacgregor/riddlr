defmodule Riddlr.GamesTest do
  use Riddlr.DataCase

  alias Riddlr.Games

  describe "riddles" do
    alias Riddlr.Games.Riddle

    import Riddlr.AccountsFixtures, only: [user_scope_fixture: 0]
    import Riddlr.GamesFixtures

    @invalid_attrs %{name: nil, description: nil, category: nil, hint: nil, answers: nil, play_status: nil, solve_time: nil, difficulty: nil, hint_delay: nil, live_date: nil, publish_status: nil, first_solve_time: nil, completion_rate: nil, average_solve_time: nil}

    test "list_riddles/1 returns all scoped riddles" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      riddle = riddle_fixture(scope)
      other_riddle = riddle_fixture(other_scope)
      assert Games.list_riddles(scope) == [riddle]
      assert Games.list_riddles(other_scope) == [other_riddle]
    end

    test "get_riddle!/2 returns the riddle with given id" do
      scope = user_scope_fixture()
      riddle = riddle_fixture(scope)
      other_scope = user_scope_fixture()
      assert Games.get_riddle!(scope, riddle.id) == riddle
      assert_raise Ecto.NoResultsError, fn -> Games.get_riddle!(other_scope, riddle.id) end
    end

    test "create_riddle/2 with valid data creates a riddle" do
      valid_attrs = %{name: "some name", description: "some description", category: "some category", hint: "some hint", answers: ["option1", "option2"], play_status: "some play_status", solve_time: 42, difficulty: "some difficulty", hint_delay: 42, live_date: ~U[2026-02-27 04:45:00Z], publish_status: "some publish_status", first_solve_time: 42, completion_rate: 120.5, average_solve_time: 120.5}
      scope = user_scope_fixture()

      assert {:ok, %Riddle{} = riddle} = Games.create_riddle(scope, valid_attrs)
      assert riddle.name == "some name"
      assert riddle.description == "some description"
      assert riddle.category == "some category"
      assert riddle.hint == "some hint"
      assert riddle.answers == ["option1", "option2"]
      assert riddle.play_status == "some play_status"
      assert riddle.solve_time == 42
      assert riddle.difficulty == "some difficulty"
      assert riddle.hint_delay == 42
      assert riddle.live_date == ~U[2026-02-27 04:45:00Z]
      assert riddle.publish_status == "some publish_status"
      assert riddle.first_solve_time == 42
      assert riddle.completion_rate == 120.5
      assert riddle.average_solve_time == 120.5
      assert riddle.user_id == scope.user.id
    end

    test "create_riddle/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Games.create_riddle(scope, @invalid_attrs)
    end

    test "update_riddle/3 with valid data updates the riddle" do
      scope = user_scope_fixture()
      riddle = riddle_fixture(scope)
      update_attrs = %{name: "some updated name", description: "some updated description", category: "some updated category", hint: "some updated hint", answers: ["option1"], play_status: "some updated play_status", solve_time: 43, difficulty: "some updated difficulty", hint_delay: 43, live_date: ~U[2026-02-28 04:45:00Z], publish_status: "some updated publish_status", first_solve_time: 43, completion_rate: 456.7, average_solve_time: 456.7}

      assert {:ok, %Riddle{} = riddle} = Games.update_riddle(scope, riddle, update_attrs)
      assert riddle.name == "some updated name"
      assert riddle.description == "some updated description"
      assert riddle.category == "some updated category"
      assert riddle.hint == "some updated hint"
      assert riddle.answers == ["option1"]
      assert riddle.play_status == "some updated play_status"
      assert riddle.solve_time == 43
      assert riddle.difficulty == "some updated difficulty"
      assert riddle.hint_delay == 43
      assert riddle.live_date == ~U[2026-02-28 04:45:00Z]
      assert riddle.publish_status == "some updated publish_status"
      assert riddle.first_solve_time == 43
      assert riddle.completion_rate == 456.7
      assert riddle.average_solve_time == 456.7
    end

    test "update_riddle/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      riddle = riddle_fixture(scope)

      assert_raise MatchError, fn ->
        Games.update_riddle(other_scope, riddle, %{})
      end
    end

    test "update_riddle/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      riddle = riddle_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Games.update_riddle(scope, riddle, @invalid_attrs)
      assert riddle == Games.get_riddle!(scope, riddle.id)
    end

    test "delete_riddle/2 deletes the riddle" do
      scope = user_scope_fixture()
      riddle = riddle_fixture(scope)
      assert {:ok, %Riddle{}} = Games.delete_riddle(scope, riddle)
      assert_raise Ecto.NoResultsError, fn -> Games.get_riddle!(scope, riddle.id) end
    end

    test "delete_riddle/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      riddle = riddle_fixture(scope)
      assert_raise MatchError, fn -> Games.delete_riddle(other_scope, riddle) end
    end

    test "change_riddle/2 returns a riddle changeset" do
      scope = user_scope_fixture()
      riddle = riddle_fixture(scope)
      assert %Ecto.Changeset{} = Games.change_riddle(scope, riddle)
    end
  end
end
