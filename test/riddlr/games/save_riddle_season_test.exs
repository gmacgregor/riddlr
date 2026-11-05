defmodule Riddlr.Games.SaveRiddleSeasonTest do
  # The clock is frozen, and the frozen clock is global.
  use Riddlr.DataCase, async: false

  import Riddlr.GamesFixtures

  alias Riddlr.Clock.Frozen
  alias Riddlr.Games

  # Today is 15 June 2030. May is past, June is current, July and September
  # are upcoming, and August is a gap.
  setup do
    Frozen.freeze(~U[2030-06-15 12:00:00Z])

    %{
      may: season_fixture(%{name: "May", starts_on: ~D[2030-05-01], ends_on: ~D[2030-05-31]}),
      june: season_fixture(%{name: "June", starts_on: ~D[2030-06-01], ends_on: ~D[2030-06-30]}),
      july: season_fixture(%{name: "July", starts_on: ~D[2030-07-01], ends_on: ~D[2030-07-31]}),
      september:
        season_fixture(%{name: "September", starts_on: ~D[2030-09-01], ends_on: ~D[2030-09-30]})
    }
  end

  describe "the Season follows the Live date" do
    test "changing only the Live date into another Season moves the riddle", %{
      june: june,
      july: july
    } do
      riddle = riddle_fixture(%{season_id: june.id, live_date: ~U[2030-06-20 12:00:00Z]})

      assert {:ok, saved} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-07-10 12:00:00Z]
               })

      assert saved.season_id == july.id
    end

    test "keeps the Season when the Live date moves into a gap", %{june: june} do
      riddle = riddle_fixture(%{season_id: june.id, live_date: ~U[2030-06-20 12:00:00Z]})

      assert {:ok, saved} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-08-10 12:00:00Z]
               })

      assert saved.season_id == june.id
    end

    test "a draft keeps its Season when its Live date is in a past Season", %{july: july} do
      riddle = riddle_fixture(%{season_id: july.id})

      assert {:ok, saved} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-05-10 12:00:00Z]
               })

      assert saved.season_id == july.id
    end

    test "a draft keeps a Season picked earlier when only other fields change", %{
      july: july
    } do
      riddle = riddle_fixture(%{season_id: july.id, live_date: ~U[2030-06-20 12:00:00Z]})

      assert {:ok, saved} = Games.save_riddle(system_scope(), riddle, %{"name" => "Renamed"})
      assert saved.season_id == july.id
    end

    test "never overrules a Season the editor picks in the same save", %{
      june: june,
      september: september
    } do
      riddle = riddle_fixture(%{season_id: june.id, live_date: ~U[2030-06-20 12:00:00Z]})

      assert {:ok, saved} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-07-10 12:00:00Z],
                 "season_id" => september.id
               })

      assert saved.season_id == september.id
    end
  end

  describe "Schedule" do
    test "is refused when the Live date is in a gap", %{july: july} do
      riddle = riddle_fixture(%{season_id: july.id, publish_status: "published"})

      assert {:error, changeset} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-08-10 12:00:00Z]
               })

      assert %{live_date: ["must fall within July (2030-07-01 to 2030-07-31)"]} =
               errors_on(changeset)

      assert Repo.reload(riddle).play_status == "closed"
    end

    test "reports the Season error alongside other errors", %{july: july} do
      riddle = riddle_fixture(%{season_id: july.id, publish_status: "published"})

      assert {:error, changeset} =
               Games.save_riddle(system_scope(), riddle, %{
                 "name" => "",
                 "live_date" => ~U[2030-08-10 12:00:00Z]
               })

      assert %{name: [_], live_date: ["must fall within July (2030-07-01 to 2030-07-31)"]} =
               errors_on(changeset)
    end

    test "is refused when the Live date is outside the riddle's Season", %{july: july} do
      riddle = riddle_fixture(%{season_id: july.id, live_date: ~U[2030-06-20 12:00:00Z]})

      assert {:error, changeset} =
               Games.save_riddle(system_scope(), riddle, %{"publish_status" => "published"})

      assert %{live_date: ["must fall within July (2030-07-01 to 2030-07-31)"]} =
               errors_on(changeset)
    end

    test "is refused when the Live date is in a past Season", %{june: june} do
      riddle = riddle_fixture(%{season_id: june.id, publish_status: "published"})

      assert {:error, changeset} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-05-10 12:00:00Z]
               })

      assert %{live_date: ["must fall within June (2030-06-01 to 2030-06-30)"]} =
               errors_on(changeset)
    end

    test "into another Season moves the riddle there", %{june: june, july: july} do
      riddle = riddle_fixture(%{season_id: june.id, publish_status: "published"})

      assert {:ok, saved} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-07-10 12:00:00Z]
               })

      assert saved.play_status == "scheduled"
      assert saved.season_id == july.id
    end
  end

  describe "Reschedule" do
    setup %{june: june} do
      %{riddle: scheduled_in(june, ~U[2030-06-20 12:00:00Z])}
    end

    test "into another Season moves the riddle there", %{riddle: riddle, july: july} do
      assert {:ok, saved} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-07-10 12:00:00Z]
               })

      assert saved.play_status == "scheduled"
      assert saved.season_id == july.id
    end

    test "into a gap is refused", %{riddle: riddle} do
      assert {:error, changeset} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-08-10 12:00:00Z]
               })

      assert %{live_date: ["must fall within June (2030-06-01 to 2030-06-30)"]} =
               errors_on(changeset)

      assert Repo.reload(riddle).live_date == riddle.live_date
    end

    test "into a past Season is refused", %{riddle: riddle} do
      assert {:error, changeset} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-05-10 12:00:00Z]
               })

      assert %{live_date: ["must fall within June (2030-06-01 to 2030-06-30)"]} =
               errors_on(changeset)
    end
  end

  describe "a Season the editor picks for a published riddle" do
    test "must hold the Live date", %{june: june, july: july} do
      riddle = scheduled_in(june, ~U[2030-06-20 12:00:00Z])

      assert {:error, changeset} =
               Games.save_riddle(system_scope(), riddle, %{"season_id" => july.id})

      assert %{live_date: ["must fall within July (2030-07-01 to 2030-07-31)"]} =
               errors_on(changeset)
    end

    test "is kept when it holds the new Live date", %{june: june, september: september} do
      riddle = scheduled_in(june, ~U[2030-06-20 12:00:00Z])

      assert {:ok, saved} =
               Games.save_riddle(system_scope(), riddle, %{
                 "season_id" => september.id,
                 "live_date" => ~U[2030-09-10 12:00:00Z]
               })

      assert saved.season_id == september.id
    end
  end

  describe "Unschedule" do
    test "keeps the Season", %{july: july} do
      riddle = scheduled_in(july, ~U[2030-07-10 12:00:00Z])

      assert {:ok, saved} =
               Games.save_riddle(system_scope(), riddle, %{"publish_status" => "draft"})

      assert saved.play_status == "closed"
      assert saved.season_id == july.id
    end
  end

  describe "a past Season" do
    test "takes no new riddles", %{may: may} do
      attrs = %{
        name: unique_riddle_name(),
        description: "Too late",
        answers: ["late"],
        category_id: category_fixture().id,
        season_id: may.id
      }

      assert {:error, changeset} = Games.create_riddle(system_scope(), attrs)

      assert %{season_id: ["is a past season; pick a current or upcoming one"]} =
               errors_on(changeset)
    end
  end

  describe "a riddle in a past Season" do
    setup %{may: may} do
      # Filed in May while May was current; today it is past.
      Frozen.freeze(~U[2030-05-15 12:00:00Z])
      riddle = riddle_fixture(%{season_id: may.id, live_date: ~U[2030-05-20 12:00:00Z]})
      Frozen.freeze(~U[2030-06-15 12:00:00Z])

      %{riddle: riddle}
    end

    test "can't be moved to another Season", %{riddle: riddle, june: june, may: may} do
      assert {:error, changeset} =
               Games.save_riddle(system_scope(), riddle, %{"season_id" => june.id})

      assert %{season_id: ["can't change: May is a past season"]} = errors_on(changeset)
      assert Repo.reload(riddle).season_id == may.id
    end

    test "can't follow its Live date into another Season", %{riddle: riddle, may: may} do
      assert {:error, changeset} =
               Games.save_riddle(system_scope(), riddle, %{
                 "live_date" => ~U[2030-06-20 12:00:00Z]
               })

      assert %{live_date: ["would move this riddle out of May, a past season"]} =
               errors_on(changeset)

      assert Repo.reload(riddle).season_id == may.id
    end

    test "keeps its Season on other edits", %{riddle: riddle, may: may} do
      assert {:ok, saved} = Games.save_riddle(system_scope(), riddle, %{"name" => "Renamed"})
      assert saved.season_id == may.id
    end
  end

  defp scheduled_in(season, live_date) do
    riddle = riddle_fixture(%{season_id: season.id, publish_status: "published"})
    {:ok, scheduled} = Games.save_riddle(system_scope(), riddle, %{"live_date" => live_date})
    scheduled
  end
end
