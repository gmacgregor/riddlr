defmodule RiddlrWeb.Router do
  use RiddlrWeb, :router

  import RiddlrWeb.UserAuth

  pipeline :browser do
    plug :browser_without_csrf
    plug :protect_from_forgery
  end

  # Scripts load only from app.js: colocated hooks go into it at build time,
  # so no page has an inline script. Styles need 'unsafe-inline' because
  # templates set style attributes and LiveView patches them. Fonts come from
  # Google Fonts; the CSS draws data: SVGs and the dev LiveDashboard loads a
  # data: font. 'self' in connect-src covers the /live websocket.
  @content_security_policy "default-src 'self'; " <>
                             "script-src 'self'; " <>
                             "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " <>
                             "font-src 'self' https://fonts.gstatic.com data:; " <>
                             "img-src 'self' data:; " <>
                             "connect-src 'self'; " <>
                             "object-src 'none'; " <>
                             "base-uri 'self'; " <>
                             "frame-ancestors 'self'; " <>
                             "form-action 'self'"

  # Everything in :browser but the CSRF check. Only the one-click unsubscribe
  # POST uses it on its own: mail clients send that with no CSRF token.
  pipeline :browser_without_csrf do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug RiddlrWeb.Theme
    plug :put_root_layout, html: {RiddlrWeb.Layouts, :root}
    plug :put_secure_browser_headers, %{"content-security-policy" => @content_security_policy}
    plug :fetch_current_scope_for_user
  end

  # Swaps in the admin root layout, which loads only the frozen admin
  # stylesheets (see RiddlrWeb.AdminLayouts).
  pipeline :admin_browser do
    plug :put_root_layout, html: {RiddlrWeb.AdminLayouts, :root}
  end

  # Sends a guest to log in with no flash, so the admin pages give no hint
  # that they exist.
  pipeline :require_authenticated_user_quietly do
    plug :require_authenticated_user, flash: false
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RiddlrWeb do
    pipe_through :browser

    live_session :public, on_mount: [{RiddlrWeb.UserAuth, :mount_current_user}] do
      live "/", HomeLive, :home
      live "/standings", StandingsLive, :index
      # Guests may watch a game but not guess or chat.
      live "/game/:id/lobby", GameLive.Lobby, :lobby
      live "/game/:id/play", GameLive.Play, :play
      live "/game/:id/results", GameLive.Results, :results
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", RiddlrWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:riddlr, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    # LiveDashboard and the mailbox preview have inline scripts, which the
    # policy blocks unless they carry the nonce RiddlrWeb.ScriptNonce allows.
    pipeline :dev_script_nonce do
      plug RiddlrWeb.ScriptNonce
    end

    scope "/dev" do
      pipe_through [:browser, :dev_script_nonce]

      live_dashboard "/dashboard",
        metrics: RiddlrWeb.Telemetry,
        csp_nonce_assign_key: :csp_nonce

      forward "/mailbox", Plug.Swoosh.MailboxPreview,
        csp_nonce_assign_key: %{script: :csp_nonce, style: :csp_nonce}
    end
  end

  ## Authentication routes

  scope "/", RiddlrWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/register/check-email", UserRegistrationController, :check_email
    post "/users/register/check-email", UserRegistrationController, :resend
  end

  scope "/", RiddlrWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/profile", ProfileController, :show
    put "/profile", ProfileController, :update
    get "/profile/confirm-email/:token", ProfileController, :confirm_email
  end

  scope "/", RiddlrWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete

    get "/notifications/unsubscribe/:token", UnsubscribeController, :show

    get "/info", InfoController, :show
  end

  # Mail clients POST here for one-click unsubscribe (RFC 8058) with no CSRF
  # token. The signed token in the path is the only proof needed, and it can
  # only turn email off.
  scope "/", RiddlrWeb do
    pipe_through [:browser_without_csrf]

    post "/notifications/unsubscribe/:token", UnsubscribeController, :create
  end

  ## Admin routes

  # A guest goes to log in, with no flash. A signed-in player who is not an
  # admin gets a 404.
  scope "/admin", RiddlrWeb do
    pipe_through [:browser, :admin_browser, :require_authenticated_user_quietly]

    # AdminController redirect - requires admin permission via plug in controller
    get "/", AdminController, :redirect_to_riddles
  end

  scope "/admin", RiddlrWeb.Admin do
    pipe_through [:browser, :admin_browser, :require_authenticated_user_quietly]

    live_session :admin,
      on_mount: [{RiddlrWeb.AdminAuth, :require_admin}],
      root_layout: {RiddlrWeb.AdminLayouts, :root},
      layout: {RiddlrWeb.AdminLayouts, :admin} do
      live "/riddles", RiddleLive.Index, :index
      live "/riddles/new", RiddleLive.Index, :new
      live "/riddles/:id/edit", RiddleLive.Index, :edit
      live "/riddles/:id", RiddleLive.Index, :show

      live "/categories", CategoryLive.Index, :index
      live "/categories/new", CategoryLive.Index, :new
      live "/categories/:id/edit", CategoryLive.Index, :edit

      live "/seasons", SeasonLive.Index, :index
      live "/seasons/new", SeasonLive.Index, :new
      live "/seasons/:id/edit", SeasonLive.Index, :edit

      live "/practice-riddles", PracticeRiddleLive.Index, :index
      live "/practice-riddles/new", PracticeRiddleLive.Index, :new
      live "/practice-riddles/:id/edit", PracticeRiddleLive.Index, :edit
    end
  end

  # Must stay last. Unknown pages raise a 404 after the browser pipeline, so
  # the 404 page shows the player's own topbar (see RiddlrWeb.ErrorHTML).
  scope "/", RiddlrWeb do
    pipe_through :browser

    get "/*path", NotFoundController, :show
  end
end
