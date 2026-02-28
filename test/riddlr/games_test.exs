defmodule Riddlr.GamesTest do
  use Riddlr.DataCase

  alias Riddlr.Games

  describe "riddles" do
    alias Riddlr.Games.Riddle

    import Riddlr.GamesFixtures

    @invalid_attrs %{name: nil, description: nil, answers: [], solve_time: nil}

    test "list_riddles/0 returns all riddles" do
      riddle = riddle_fixture()
      assert Games.list_riddles() == [riddle]
    end

    test "get_riddle!/1 returns the riddle with given id" do
      riddle = riddle_fixture()
      assert Games.get_riddle!(riddle.id) == riddle
    end

    test "create_riddle/1 with valid data creates a riddle" do
      valid_attrs = %{
        name: "Test Riddle",
        description: "A test riddle description",
        answers: ["answer1", "answer2"],
        solve_time: 60,
        category: "logic",
        difficulty: "medium"
      }

      assert {:ok, %Riddle{} = riddle} = Games.create_riddle(valid_attrs)
      assert riddle.name == "Test Riddle"
      assert riddle.description == "A test riddle description"
      assert riddle.answers == ["answer1", "answer2"]
      assert riddle.solve_time == 60
      assert riddle.play_status == "closed"
      assert riddle.publish_status == "draft"
    end

    test "create_riddle/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Games.create_riddle(@invalid_attrs)
    end

    test "create_riddle/1 requires at least one answer" do
      attrs = %{
        name: "Test",
        description: "Test",
        answers: [],
        solve_time: 60
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{answers: ["must have at least one answer"]} = errors_on(changeset)
    end

    test "create_riddle/1 validates play_status enum" do
      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        play_status: "invalid_status"
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{play_status: ["is invalid"]} = errors_on(changeset)
    end

    test "create_riddle/1 validates difficulty enum" do
      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        difficulty: "impossible"
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{difficulty: ["is invalid"]} = errors_on(changeset)
    end

    test "create_riddle/1 validates publish_status enum" do
      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["answer"],
        solve_time: 60,
        publish_status: "invalid_status"
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{publish_status: ["is invalid"]} = errors_on(changeset)
    end

    test "create_riddle/1 rejects empty strings in answers array" do
      attrs = %{
        name: "Test",
        description: "Test",
        answers: ["valid answer", "", "  "],
        solve_time: 60
      }

      assert {:error, changeset} = Games.create_riddle(attrs)
      assert %{answers: ["all answers must be non-empty strings"]} = errors_on(changeset)
    end

    test "update_riddle/2 with valid data updates the riddle" do
      riddle = riddle_fixture()
      update_attrs = %{
        name: "Updated Name",
        description: "Updated description",
        answers: ["new_answer"],
        solve_time: 120
      }

      assert {:ok, %Riddle{} = riddle} = Games.update_riddle(riddle, update_attrs)
      assert riddle.name == "Updated Name"
      assert riddle.description == "Updated description"
      assert riddle.answers == ["new_answer"]
      assert riddle.solve_time == 120
    end

    test "update_riddle/2 with invalid data returns error changeset" do
      riddle = riddle_fixture()
      assert {:error, %Ecto.Changeset{}} = Games.update_riddle(riddle, @invalid_attrs)
      assert riddle == Games.get_riddle!(riddle.id)
    end

    test "delete_riddle/1 deletes the riddle" do
      riddle = riddle_fixture()
      assert {:ok, %Riddle{}} = Games.delete_riddle(riddle)
      assert_raise Ecto.NoResultsError, fn -> Games.get_riddle!(riddle.id) end
    end

    test "change_riddle/1 returns a riddle changeset" do
      riddle = riddle_fixture()
      assert %Ecto.Changeset{} = Games.change_riddle(riddle)
    end
  end
end
