defmodule RiddlrWeb.AdminLayouts do
  @moduledoc """
  The admin's layouts: its own root layout and the admin shell.

  The root layout loads only the frozen admin stylesheets
  (`admin-tokens.css`, `admin-base.css`, `admin.css`) and the admin fonts,
  never the player ones, so the player screens can change without moving
  the admin. The router sets both layouts on the admin `live_session` and
  pipeline. The shell (`admin.html.heex`) renders the topbar and flash from
  `RiddlrWeb.AdminComponents`.
  """
  use RiddlrWeb, :admin_html

  embed_templates "admin_layouts/*"

  @doc """
  Returns `"page"` when `current_path` is `section_path` or a page under it,
  so the admin nav can mark the current section. Returns `nil` otherwise.
  """
  @spec admin_nav_current(String.t() | nil, String.t()) :: String.t() | nil
  def admin_nav_current(current_path, section_path) when is_binary(current_path) do
    if current_path == section_path or String.starts_with?(current_path, section_path <> "/"),
      do: "page"
  end

  def admin_nav_current(_current_path, _section_path), do: nil
end
