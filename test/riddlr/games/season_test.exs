defmodule Riddlr.Games.SeasonTest do
  use Riddlr.DataCase, async: false

  alias Riddlr.Clock.Frozen
  alias Riddlr.Games

  import Riddlr.GamesFixtures, only: [riddle_fixture: 1, season_fixture: 1, system_scope: 0]

  setup do
    Frozen.freeze(~U[2030-06-15 12:00:00Z])
    :ok
  end

  defp attrs(overrides) do
    Enum.into(overrides, %{name: "Summer", starts_on: ~D[2030-07-01], ends_on: ~D[2030-07-31]})
  end

  describe "create_season/2 name and description" do
    test "accepts accented letters, digits, punctuation and spaces" do
      assert {:ok, season} =
               Games.create_season(system_scope(), attrs(name: "Saison d'été #2 — ¡Olé!"))

      assert season.name == "Saison d'été #2 — ¡Olé!"
    end

    test "requires a name of 2 to 50 characters" do
      for name <- [nil, "", "a", String.duplicate("a", 51)] do
        assert {:error, changeset} = Games.create_season(system_scope(), attrs(name: name))
        assert %{name: [_]} = errors_on(changeset)
      end

      assert {:ok, _} = Games.create_season(system_scope(), attrs(name: "ab"))
    end

    test "refuses a name another season uses, ignoring case" do
      season_fixture(%{name: "Winter"})

      assert {:error, changeset} = Games.create_season(system_scope(), attrs(name: "wINTER"))
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "takes an optional description of at most 500 characters" do
      assert {:ok, %{description: nil}} = Games.create_season(system_scope(), attrs(%{}))

      assert {:error, changeset} =
               Games.create_season(
                 system_scope(),
                 attrs(name: "Long", description: String.duplicate("x", 501))
               )

      assert %{description: [_]} = errors_on(changeset)
    end
  end

  describe "create_season/2 dates" do
    test "refuses an end date before the start date" do
      assert {:error, changeset} =
               Games.create_season(
                 system_scope(),
                 attrs(starts_on: ~D[2030-07-10], ends_on: ~D[2030-07-09])
               )

      assert %{ends_on: [_]} = errors_on(changeset)
    end

    test "allows a one-day season" do
      assert {:ok, _} =
               Games.create_season(
                 system_scope(),
                 attrs(starts_on: ~D[2030-07-10], ends_on: ~D[2030-07-10])
               )
    end
  end

  describe "display time zone" do
    # The display time zone is America/Toronto: UTC-4 in summer, UTC-5 in winter.
    test "stores a season as UTC instants from midnight on its first day to midnight after its last" do
      {:ok, summer} =
        Games.create_season(
          system_scope(),
          attrs(starts_on: ~D[2030-07-01], ends_on: ~D[2030-07-31])
        )

      assert summer.starts_at == ~U[2030-07-01 04:00:00Z]
      assert summer.ends_at == ~U[2030-08-01 04:00:00Z]

      {:ok, winter} =
        Games.create_season(
          system_scope(),
          attrs(name: "Winter", starts_on: ~D[2031-01-01], ends_on: ~D[2031-01-31])
        )

      assert winter.starts_at == ~U[2031-01-01 05:00:00Z]
      assert winter.ends_at == ~U[2031-02-01 05:00:00Z]
    end

    test "reads back the days in the display time zone" do
      season = season_fixture(%{starts_on: ~D[2030-11-02], ends_on: ~D[2030-11-03]})

      assert %{starts_on: ~D[2030-11-02], ends_on: ~D[2030-11-03]} =
               Games.get_season!(season.id)

      assert %{starts_on: ~D[2030-11-02], ends_on: ~D[2030-11-03]} =
               Enum.find(Games.list_seasons(), &(&1.id == season.id))
    end
  end

  describe "list_seasons/0" do
    test "counts each season's riddles" do
      busy = season_fixture(%{})
      empty = season_fixture(%{})
      riddle_fixture(%{season_id: busy.id})
      riddle_fixture(%{season_id: busy.id})

      counts = Map.new(Games.list_seasons(), &{&1.id, &1.riddle_count})
      assert counts[busy.id] == 2
      assert counts[empty.id] == 0
    end
  end

  describe "list_current_and_upcoming_seasons/0" do
    # The clock is frozen at 2030-06-15.
    test "lists the current season, then upcoming seasons soonest first" do
      season_fixture(days(~D[2030-05-01], ~D[2030-05-31]))
      later = season_fixture(days(~D[2030-08-01], ~D[2030-08-31]))
      current = season_fixture(days(~D[2030-06-01], ~D[2030-06-30]))
      sooner = season_fixture(days(~D[2030-07-01], ~D[2030-07-31]))

      assert [current.id, sooner.id, later.id] ==
               Enum.map(Games.list_current_and_upcoming_seasons(), & &1.id)
    end
  end

  describe "default_season/2" do
    setup do
      %{
        current: season_fixture(days(~D[2030-06-01], ~D[2030-06-30])),
        sooner: season_fixture(days(~D[2030-07-01], ~D[2030-07-31])),
        later: season_fixture(days(~D[2030-08-01], ~D[2030-08-31]))
      }
    end

    test "picks the season holding the Live date", %{later: later} do
      seasons = Games.list_current_and_upcoming_seasons()
      assert Games.default_season(seasons, ~U[2030-08-10 12:00:00Z]).id == later.id
    end

    test "falls back to the current season with no Live date, or one in no listed season",
         %{current: current} do
      seasons = Games.list_current_and_upcoming_seasons()
      assert Games.default_season(seasons, nil).id == current.id
      assert Games.default_season(seasons, ~U[2031-01-10 12:00:00Z]).id == current.id
    end

    test "falls back to the soonest upcoming season with no current one",
         %{current: current, sooner: sooner} do
      seasons = Games.list_current_and_upcoming_seasons() |> Enum.reject(&(&1.id == current.id))
      assert Games.default_season(seasons, nil).id == sooner.id
    end

    test "is nil with no seasons" do
      assert Games.default_season([], nil) == nil
    end
  end

  describe "season_status/1" do
    test "derives upcoming, current and past from the clock" do
      # The clock is frozen at 2030-06-15 08:00 Toronto time.
      assert :past == Games.season_status(season_fixture(days(~D[2030-06-01], ~D[2030-06-14])))
      assert :current == Games.season_status(season_fixture(days(~D[2030-06-15], ~D[2030-06-15])))

      assert :upcoming ==
               Games.season_status(season_fixture(days(~D[2030-06-16], ~D[2030-06-30])))
    end

    test "turns at midnight in the display time zone, not UTC" do
      summer = season_fixture(days(~D[2030-06-16], ~D[2030-06-16]))

      # Midnight UTC is still the evening before in Toronto.
      Frozen.freeze(~U[2030-06-16 00:00:00Z])
      assert :upcoming == Games.season_status(summer)

      Frozen.freeze(~U[2030-06-16 03:59:59Z])
      assert :upcoming == Games.season_status(summer)

      Frozen.advance(1, :second)
      assert :current == Games.season_status(summer)

      Frozen.freeze(~U[2030-06-17 03:59:59Z])
      assert :current == Games.season_status(summer)

      Frozen.advance(1, :second)
      assert :past == Games.season_status(summer)
    end

    defp days(starts_on, ends_on), do: %{starts_on: starts_on, ends_on: ends_on}
  end

  describe "overlap in the display time zone" do
    test "allows back-to-back seasons across a daylight saving change" do
      # Toronto falls back on 2030-11-03.
      assert {:ok, autumn} =
               Games.create_season(
                 system_scope(),
                 attrs(name: "Autumn", starts_on: ~D[2030-10-01], ends_on: ~D[2030-11-02])
               )

      assert {:ok, winter} =
               Games.create_season(
                 system_scope(),
                 attrs(name: "Winter", starts_on: ~D[2030-11-03], ends_on: ~D[2030-12-31])
               )

      assert autumn.ends_at == winter.starts_at
    end
  end

  describe "update_season/3 locks" do
    # The clock is frozen at 2030-06-15.
    setup do
      %{
        past:
          season_fixture(%{name: "Spring", starts_on: ~D[2030-04-01], ends_on: ~D[2030-05-31]}),
        current:
          season_fixture(%{name: "June", starts_on: ~D[2030-06-01], ends_on: ~D[2030-06-30]}),
        upcoming:
          season_fixture(%{name: "Autumn", starts_on: ~D[2030-09-01], ends_on: ~D[2030-09-30]})
      }
    end

    test "lets an upcoming season change name, description and dates", %{upcoming: upcoming} do
      assert {:ok, season} =
               Games.update_season(system_scope(), upcoming, %{
                 name: "Fall",
                 description: "Leaves",
                 starts_on: ~D[2030-08-15],
                 ends_on: ~D[2030-10-15]
               })

      assert {season.name, season.description, season.starts_on, season.ends_on} ==
               {"Fall", "Leaves", ~D[2030-08-15], ~D[2030-10-15]}
    end

    test "refuses to change a past season's dates", %{past: past} do
      assert {:error, changeset} =
               Games.update_season(system_scope(), past, %{starts_on: ~D[2030-03-01]})

      assert %{starts_on: [_]} = errors_on(changeset)

      assert {:error, changeset} =
               Games.update_season(system_scope(), past, %{ends_on: ~D[2030-05-30]})

      assert %{ends_on: [_]} = errors_on(changeset)
    end

    test "lets a past season change its name and description", %{past: past} do
      assert {:ok, %{name: "Spring!", description: "Fixed"}} =
               Games.update_season(system_scope(), past, %{
                 name: "Spring!",
                 description: "Fixed",
                 starts_on: past.starts_on,
                 ends_on: past.ends_on
               })
    end

    test "refuses to change the current season's start date", %{current: current} do
      assert {:error, changeset} =
               Games.update_season(system_scope(), current, %{starts_on: ~D[2030-06-02]})

      assert %{starts_on: [_]} = errors_on(changeset)
    end

    test "lets the current season move its end date", %{current: current} do
      assert {:ok, %{ends_on: ~D[2030-06-20]}} =
               Games.update_season(system_scope(), current, %{ends_on: ~D[2030-06-20]})

      assert {:ok, %{ends_on: ~D[2030-07-31]}} =
               Games.update_season(system_scope(), Games.get_season!(current.id), %{
                 ends_on: ~D[2030-07-31]
               })
    end
  end

  describe "delete_season/2" do
    test "deletes a season" do
      season = season_fixture(%{})

      assert {:ok, _} = Games.delete_season(system_scope(), season)
      assert_raise Ecto.NoResultsError, fn -> Games.get_season!(season.id) end
    end

    test "refuses to delete a season that has riddles" do
      season = season_fixture(%{})
      riddle_fixture(%{season_id: season.id})

      assert {:error, changeset} = Games.delete_season(system_scope(), season)
      assert %{riddles: [_]} = errors_on(changeset)
      assert Games.get_season!(season.id)
    end
  end

  describe "authorization" do
    for role <- [:moderator, :viewer, :player] do
      test "refuses every write to a #{role}" do
        scope =
          %{role: unquote(role)}
          |> Riddlr.AccountsFixtures.user_fixture()
          |> Riddlr.Accounts.Scope.for_user()

        season = season_fixture(%{name: "Kept"})

        assert {:error, :unauthorized} = Games.create_season(scope, attrs(%{}))
        assert {:error, :unauthorized} = Games.update_season(scope, season, %{name: "Taken"})
        assert {:error, :unauthorized} = Games.delete_season(scope, season)
        assert Games.get_season!(season.id).name == "Kept"
      end
    end

    for role <- [:editor, :super_admin] do
      test "lets a #{role} create, update and delete" do
        scope =
          %{role: unquote(role)}
          |> Riddlr.AccountsFixtures.user_fixture()
          |> Riddlr.Accounts.Scope.for_user()

        assert {:ok, season} = Games.create_season(scope, attrs(%{}))
        assert {:ok, season} = Games.update_season(scope, season, %{name: "Renamed"})
        assert {:ok, _} = Games.delete_season(scope, season)
      end
    end
  end

  describe "overlap" do
    setup do
      %{
        summer:
          season_fixture(%{name: "Summer", starts_on: ~D[2030-07-01], ends_on: ~D[2030-07-31]})
      }
    end

    test "refuses a season that shares a day with another, naming it" do
      for {starts_on, ends_on} <- [
            {~D[2030-06-20], ~D[2030-07-01]},
            {~D[2030-07-31], ~D[2030-08-10]},
            {~D[2030-07-10], ~D[2030-07-12]},
            {~D[2030-06-01], ~D[2030-09-01]}
          ] do
        assert {:error, changeset} =
                 Games.create_season(
                   system_scope(),
                   attrs(name: "Clash", starts_on: starts_on, ends_on: ends_on)
                 )

        assert %{ends_on: [message]} = errors_on(changeset)
        assert message =~ "Summer"
      end
    end

    test "allows back-to-back seasons" do
      assert {:ok, _} =
               Games.create_season(
                 system_scope(),
                 attrs(name: "Before", starts_on: ~D[2030-06-20], ends_on: ~D[2030-06-30])
               )

      assert {:ok, _} =
               Games.create_season(
                 system_scope(),
                 attrs(name: "After", starts_on: ~D[2030-08-01], ends_on: ~D[2030-08-31])
               )
    end

    test "allows a gap between seasons" do
      assert {:ok, _} =
               Games.create_season(
                 system_scope(),
                 attrs(name: "Autumn", starts_on: ~D[2030-09-15], ends_on: ~D[2030-10-31])
               )
    end

    test "refuses an update that runs into another season, naming it", %{summer: summer} do
      {:ok, autumn} =
        Games.create_season(
          system_scope(),
          attrs(name: "Autumn", starts_on: ~D[2030-09-01], ends_on: ~D[2030-09-30])
        )

      assert {:error, changeset} =
               Games.update_season(system_scope(), autumn, %{starts_on: ~D[2030-07-31]})

      assert %{ends_on: [message]} = errors_on(changeset)
      assert message =~ summer.name
    end

    test "lets a season keep its own days on update", %{summer: summer} do
      assert {:ok, %{ends_on: ~D[2030-08-05]}} =
               Games.update_season(system_scope(), summer, %{ends_on: ~D[2030-08-05]})
    end
  end
end
