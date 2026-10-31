defmodule RiddlrWeb.Theme do
  @moduledoc """
  The colour mode a player picked: `"light"` (the default) or `"dark"`.

  The choice lives in a `theme` cookie that the browser writes when the
  player picks a mode in the topbar (see `assets/js/app.js`). It holds no
  secret, so JS can read and write it.

  As a plug in the browser pipeline, this module reads the cookie and assigns
  `:theme`, so the root layout renders `data-theme` on `<html>` and the first
  paint is right. It also copies the theme into the session, where
  `on_mount/4` picks it up for LiveViews.
  """
  @behaviour Plug

  import Plug.Conn

  @themes ~w(light dark)
  @default "light"
  @colors %{"light" => "#f5f7fb", "dark" => "#0d1526"}
  @cookie "theme"

  @typedoc "A colour mode name."
  @type t :: String.t()

  @doc "Every colour mode, in the order the topbar lists them."
  @spec themes() :: [t()]
  def themes, do: @themes

  @doc """
  The other mode. The topbar switch flips between the two.
  """
  @spec next(t()) :: t()
  def next(theme) when theme in @themes do
    index = Enum.find_index(@themes, &(&1 == theme))
    Enum.at(@themes, rem(index + 1, length(@themes)))
  end

  @doc "The name players see for a mode, such as `\"Dark\"`."
  @spec label(t()) :: String.t()
  def label(theme) when theme in @themes, do: String.capitalize(theme)

  @doc """
  The browser bar colour for a mode, for the `theme-color` meta tag. It
  matches the page ground (`--surface`) in `assets/css/themes.css`.
  """
  @spec theme_color(t()) :: String.t()
  def theme_color(theme) when theme in @themes, do: Map.fetch!(@colors, theme)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    theme = cast(conn.cookies[@cookie])

    conn
    |> assign(:theme, theme)
    |> remember(theme)
  end

  # Writes the session only when the theme changed, so most requests leave
  # the session cookie alone.
  @spec remember(Plug.Conn.t(), t()) :: Plug.Conn.t()
  defp remember(conn, theme) do
    case get_session(conn, @cookie) do
      ^theme -> conn
      _other -> put_session(conn, @cookie, theme)
    end
  end

  @doc """
  Assigns `:theme` from the session, for every LiveView.
  """
  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, :theme, cast(session[@cookie]))}
  end

  @spec cast(term()) :: t()
  defp cast(theme) when theme in @themes, do: theme
  defp cast(_theme), do: @default
end
