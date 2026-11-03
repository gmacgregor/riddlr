defmodule Riddlr.Games.ScopeTest do
  use Riddlr.DataCase, async: true

  import Riddlr.AccountsFixtures
  import Riddlr.GamesFixtures

  alias Riddlr.Accounts.Scope
  alias Riddlr.Games

  @attrs %{description: "What gets wetter the more it dries?", answer: "towel"}

  describe "admin writes" do
    test "an editor's scope may write" do
      scope = Scope.for_user(user_fixture(%{role: :editor}))

      assert {:ok, _} = Games.create_practice_riddle(scope, @attrs)
    end

    test "the system scope may write" do
      assert {:ok, _} = Games.create_practice_riddle(Scope.for_system(), @attrs)
    end

    test "a moderator's scope may not write" do
      scope = Scope.for_user(user_fixture(%{role: :moderator}))

      assert Games.create_practice_riddle(scope, @attrs) == {:error, :unauthorized}
    end

    test "a guest scope may not write" do
      assert Games.create_category(%Scope{}, %{name: "guests"}) == {:error, :unauthorized}
    end

    test "a scope taken before a demotion may not write" do
      editor = user_fixture(%{role: :editor})
      scope = Scope.for_user(editor)
      editor |> Ecto.Changeset.change(role: :player) |> Repo.update!()
      riddle = riddle_fixture()

      assert Games.save_riddle(scope, riddle, %{"name" => "Renamed"}) == {:error, :unauthorized}
      assert Games.delete_riddle(scope, riddle) == {:error, :unauthorized}
      assert Games.get_riddle!(riddle.id).name == riddle.name
    end

    test "a banned editor's scope may not write" do
      editor = user_fixture(%{role: :editor})
      scope = Scope.for_user(editor)
      editor |> Ecto.Changeset.change(account_status: :banned) |> Repo.update!()

      assert Games.create_category(scope, %{name: "banned"}) == {:error, :unauthorized}
    end
  end
end
