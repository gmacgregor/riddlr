defmodule Riddlr.Gameplay.SendChatTest do
  use Riddlr.DataCase, async: false

  alias Riddlr.Clock.Frozen
  alias Riddlr.Gameplay
  alias Riddlr.Gameplay.Answer
  alias Riddlr.{AccountsFixtures, GamesFixtures}

  # The cooldown is one second, so a slow run on the real clock could let a
  # second message through.
  setup do
    Frozen.freeze()

    riddle =
      %{publish_status: "published"}
      |> GamesFixtures.riddle_fixture()
      |> Ecto.Changeset.change(play_status: "live")
      |> Repo.update!()
      |> then(&Riddlr.Games.get_riddle!(&1.id))

    Phoenix.PubSub.subscribe(Riddlr.PubSub, Answer.topic(riddle.id))

    %{riddle: riddle, user: AccountsFixtures.user_fixture()}
  end

  describe "send_chat/3" do
    test "broadcasts the message as chat", %{riddle: riddle, user: user} do
      assert Gameplay.send_chat(riddle, user, "gg") == :ok

      assert_receive {:answer_submitted, %Answer{text: "gg", chat: true}}
    end

    test "turns away a second message inside the cooldown", %{riddle: riddle, user: user} do
      assert Gameplay.send_chat(riddle, user, "gg") == :ok
      assert Gameplay.send_chat(riddle, user, "gg again") == {:error, :cooldown}

      assert_receive {:answer_submitted, %Answer{text: "gg"}}
      refute_receive {:answer_submitted, %Answer{text: "gg again"}}
    end

    test "lets the user chat again once the cooldown second is up", %{
      riddle: riddle,
      user: user
    } do
      assert Gameplay.send_chat(riddle, user, "one") == :ok
      Frozen.advance(999, :millisecond)
      assert Gameplay.send_chat(riddle, user, "two") == {:error, :cooldown}
      Frozen.advance(1, :millisecond)
      assert Gameplay.send_chat(riddle, user, "three") == :ok
    end

    test "does not block another user", %{riddle: riddle, user: user} do
      other = AccountsFixtures.user_fixture()

      assert Gameplay.send_chat(riddle, user, "gg") == :ok
      assert Gameplay.send_chat(riddle, other, "gg") == :ok
    end

    test "does not block that user's guess", %{riddle: riddle, user: user} do
      assert Gameplay.send_chat(riddle, user, "gg") == :ok

      assert Gameplay.submit_answer(riddle, user, "mouse") == :incorrect
    end

    test "cleanup_riddle/1 drops the chat cooldown", %{riddle: riddle, user: user} do
      assert Gameplay.send_chat(riddle, user, "gg") == :ok

      Gameplay.cleanup_riddle(riddle.id)

      assert Gameplay.send_chat(riddle, user, "gg") == :ok
    end
  end
end
