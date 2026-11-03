defmodule RiddlrWeb.GameCopy.Errors do
  @moduledoc """
  The words the error pages show: the 404 page and the crisis page for any
  other error.
  """

  @doc "The browser title of the 404 page."
  @spec not_found_title() :: String.t()
  def not_found_title, do: "Page not found"

  @doc "The riddle the 404 page poses in place of an error message."
  @spec not_found_riddle() :: String.t()
  def not_found_riddle do
    "I am the digital knock on a door that leads to an empty room; " <>
      "everyone knows I am here, yet the thing you seek is gone."
  end

  @doc "The 404 page's link back to Home."
  @spec not_found_home() :: String.t()
  def not_found_home, do: "Back to the homepage"

  @doc "The browser title of the error page for anything but a 404."
  @spec crisis_title() :: String.t()
  def crisis_title, do: "Something went wrong"

  @doc "The riddle the error page poses in place of an error message."
  @spec crisis_riddle() :: String.t()
  def crisis_riddle, do: "I hide a crisis I cannot explain. What am I?"

  @doc "The error page's answer to its own riddle."
  @spec crisis_tail() :: String.t()
  def crisis_tail, do: "Good question!"
end
