defmodule Riddlr.Gameplay.Entry do
  @moduledoc """
  An **Entry**: a player's record of guessing at least once on a riddle,
  kept for good once it completes.

  ETS holds the guesses while the riddle is live. When the riddle completes,
  `Riddlr.Games.transition/3` writes one Entry per distinct guesser, solvers
  included, in the same transaction as the `Riddlr.Gameplay.Solve` rows.
  Solves ÷ Entries gives a player's solve rate.

  `user_id` is nil when the player's account is gone.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          riddle_id: integer() | nil,
          user_id: integer() | nil
        }

  schema "entries" do
    belongs_to :riddle, Riddlr.Games.Riddle
    belongs_to :user, Riddlr.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
