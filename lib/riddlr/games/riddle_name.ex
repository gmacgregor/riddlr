defmodule Riddlr.Games.RiddleName do
  @moduledoc """
  Makes random riddle names, such as "Silent Lantern", so an editor does not
  have to think one up.

  A name is one adjective and one noun. The two word lists give 15,000
  distinct names. The names do not have to be unique across riddles.
  """

  @adjectives ~w(
    ancient broken burning clever crimson crooked cryptic curious dusty faded
    forgotten frozen gentle golden haunted hidden hollow idle lonely lost
    mirrored misty murky narrow odd pale puzzling quiet restless rusty
    secret shadowy silent silver sleepy sly still strange sunken tangled
    twisted veiled velvet wandering whispering wicked winding wise wooden riddling
    amber arcane ashen bitter blazing bleak bold brass brittle cloaked
    copper cunning dappled dim distant drowsy eerie elder emerald feral
    fickle gilded glassy gloomy hushed icy iron ivory jagged keen
    lunar marble mossy nimble obscure opal phantom quaint ragged scarlet
    shrouded solemn starlit stormy tarnished timid twilight vanishing wary withered
  )

  @nouns ~w(
    anchor attic badger beetle bell book bottle box bridge button
    candle castle cat cave cellar chest chimney cipher clock cloud
    coin comet compass crown crystal diamond door dream drum echo
    ember feather flame flute forest fox frost garden ghost giant
    hare harp hourglass ink island jester kettle key king knight
    ladder lantern letter library map mask maze meadow mirror moon
    moth mountain needle ocean oracle otter owl pearl pebble puzzle
    queen question quill rainbow raven ribbon ring river sail scroll
    serpent shadow shield ship smoke snowflake sparrow sphinx spider spoon
    star stone storm sword teacup thief thread tortoise tower umbrella
    acorn alchemist apple arrow banner barrel beacon blossom cauldron chalice
    cloak crow dagger dragon falcon fern fiddle goblet gargoyle glacier
    griffin hammer hawk helmet jewel labyrinth locket lighthouse magpie willow
    mill monk nest orchard palace pendulum pilgrim prism puppet rook
    sage satchel scarecrow statue telescope thimble throne tide violin wolf
  )

  @doc """
  Returns a random name made of a capitalized adjective and noun.

  ## Examples

      iex> Riddlr.Games.RiddleName.generate() =~ ~r/^[A-Z][a-z]+ [A-Z][a-z]+$/
      true
  """
  @spec generate() :: String.t()
  def generate do
    format(Enum.random(@adjectives), Enum.random(@nouns))
  end

  @doc """
  Returns every name `generate/0` can make.
  """
  @spec all() :: [String.t()]
  def all do
    for adjective <- @adjectives, noun <- @nouns, do: format(adjective, noun)
  end

  @spec format(String.t(), String.t()) :: String.t()
  defp format(adjective, noun) do
    String.capitalize(adjective) <> " " <> String.capitalize(noun)
  end
end
