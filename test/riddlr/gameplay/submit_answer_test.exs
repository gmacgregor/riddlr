defmodule Riddlr.Gameplay.SubmitAnswerTest do
  use Riddlr.DataCase, async: false

  alias Riddlr.Gameplay
  alias Riddlr.{AccountsFixtures, GamesFixtures}

  setup do
    riddle = live_riddle()
    user = AccountsFixtures.user_fixture()
    %{riddle: riddle, user: user}
  end

  describe "submit_answer/3 — incorrect answers" do
    test "returns :incorrect, stores the answer and broadcasts it", %{
      riddle: riddle,
      user: user
    } do
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{riddle.id}:answer_submitted")

      assert Gameplay.submit_answer(riddle, user, "mouse") == :incorrect

      assert_receive {:answer_submitted, %{text: "mouse", correct: false} = answer}
      assert answer.username == user.username
      assert [%{text: "mouse", correct: false}] = Gameplay.get_answers(riddle.id)
    end

    test "flags an answer that trips moderation", %{riddle: riddle, user: user} do
      Phoenix.PubSub.subscribe(Riddlr.PubSub, "gameplay:#{riddle.id}:answer_flagged")

      assert Gameplay.submit_answer(riddle, user, "this is spam") == :incorrect

      assert_receive {:answer_flagged, _answer_id}, 500
    end
  end

  describe "submit_answer/3 — correct answers" do
    test "first solver gets placement 1, points and is recorded on the riddle", %{
      riddle: riddle,
      user: user
    } do
      assert Gameplay.submit_answer(riddle, user, "keyboard") == {:correct, 1, 10}

      assert Repo.get!(Riddlr.Accounts.User, user.id).total_points == 10

      reloaded = Riddlr.Games.get_riddle!(riddle.id)
      assert reloaded.first_solver_id == user.id
      assert reloaded.play_status == "live"
    end

    test "second solver gets placement 2 and does not overwrite the first solver", %{
      riddle: riddle,
      user: user
    } do
      other = AccountsFixtures.user_fixture()

      assert {:correct, 1, 10} = Gameplay.submit_answer(riddle, user, "keyboard")
      assert {:correct, 2, 9} = Gameplay.submit_answer(riddle, other, "keyboard")

      assert Riddlr.Games.get_riddle!(riddle.id).first_solver_id == user.id
    end
  end

  describe "submit_answer/3 — guards" do
    test "blocks a second submission once the user has solved it", %{
      riddle: riddle,
      user: user
    } do
      assert {:correct, 1, 10} = Gameplay.submit_answer(riddle, user, "keyboard")

      assert Gameplay.submit_answer(riddle, user, "keyboard") == {:error, :already_solved}
    end

    test "rate-limits rapid submissions from the same user", %{riddle: riddle, user: user} do
      assert Gameplay.submit_answer(riddle, user, "mouse") == :incorrect

      assert Gameplay.submit_answer(riddle, user, "monitor") == {:error, :cooldown}
    end

    test "rejects submissions when the riddle is not live", %{user: user} do
      riddle = GamesFixtures.riddle_fixture()

      assert Gameplay.submit_answer(riddle, user, "keyboard") == {:error, {:not_live, "closed"}}
      assert Gameplay.get_answers(riddle.id) == []
    end

    test "rejects submissions from a banned user", %{riddle: riddle, user: user} do
      {:ok, banned} = Riddlr.Accounts.set_user_status(user, :banned)

      assert Gameplay.submit_answer(riddle, banned, "keyboard") == {:error, :banned}
      assert Gameplay.get_answers(riddle.id) == []
    end

    test "rejects blank and over-long answers", %{riddle: riddle, user: user} do
      assert Gameplay.submit_answer(riddle, user, "   ") == {:error, :empty_answer}

      assert Gameplay.submit_answer(riddle, user, String.duplicate("a", 501)) ==
               {:error, :answer_too_long}

      assert Gameplay.get_answers(riddle.id) == []
    end
  end

  describe "submit_answer/3 — live until solved" do
    test "completes the riddle on the first correct answer", %{user: user} do
      riddle = live_riddle(%{live_until_solved: true})

      assert {:correct, 1, 10} = Gameplay.submit_answer(riddle, user, "keyboard")

      reloaded = Riddlr.Games.get_riddle!(riddle.id)
      assert reloaded.play_status == "completed"
      assert reloaded.first_solver_id == user.id
      assert reloaded.completion_rate == 100.0
    end
  end

  defp live_riddle(attrs \\ %{}) do
    attrs
    |> GamesFixtures.riddle_fixture()
    |> Ecto.Changeset.change(play_status: "live")
    |> Repo.update!()
    |> then(&Riddlr.Games.get_riddle!(&1.id))
  end
end
