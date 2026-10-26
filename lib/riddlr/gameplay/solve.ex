defmodule Riddlr.Gameplay.Solve do
  @moduledoc """
  A **Solve**: one player's correct answer to a riddle, kept in the database.

  ETS holds the race while the riddle is live. When the riddle completes,
  `Riddlr.Games.transition/3` copies every solver into this table, so the
  Results board still works after archive drops the ETS rows.

  `user_id` is nil when the player's account is gone. The row stays so the
  board keeps every place.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          riddle_id: integer() | nil,
          user_id: integer() | nil,
          placement: pos_integer() | nil,
          points: non_neg_integer() | nil,
          solve_time_ms: non_neg_integer() | nil
        }

  schema "solves" do
    field :placement, :integer
    field :points, :integer
    field :solve_time_ms, :integer

    belongs_to :riddle, Riddlr.Games.Riddle
    belongs_to :user, Riddlr.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
