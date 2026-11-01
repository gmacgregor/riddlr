defmodule Riddlr.StandingsPubSubTest do
  # The "standings" topic is global, and async tests complete riddles too.
  use Riddlr.DataCase, async: false

  import Riddlr.GamesFixtures

  alias Riddlr.Standings

  describe "subscribe/0" do
    test "tells subscribers when a riddle completes" do
      Standings.subscribe()
      riddle = riddle_fixture(%{play_status: "live", publish_status: "published"})

      assert {:ok, _} = Riddlr.Games.transition(riddle.id, :completed)

      assert_receive :standings_changed
    end

    test "says nothing on other transitions" do
      Standings.subscribe()
      riddle = riddle_fixture(%{play_status: "completed", publish_status: "published"})

      assert {:ok, _} = Riddlr.Games.transition(riddle.id, :archived)

      refute_receive :standings_changed
    end
  end
end
