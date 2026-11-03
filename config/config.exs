# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :riddlr, :scopes,
  user: [
    default: true,
    module: Riddlr.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Riddlr.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :riddlr,
  ecto_repos: [Riddlr.Repo],
  generators: [timestamp_type: :utc_datetime],
  clock: Riddlr.Clock.System,
  # Live dates in emails show in this zone.
  display_time_zone: "America/Toronto"

# Guesses reach the live feed in one batch per riddle every feed_flush_ms,
# not one message each.
config :riddlr, Riddlr.GameClock, batch_feed: true, feed_flush_ms: 100

# Configure Oban
# Queue limits add up to 15, under the Repo pool of 20, so jobs at full tilt
# leave connections for web requests. Lifeline puts a job back once it has
# run 5 minutes, which means its node died: a notification send times out at
# 30 seconds, and nothing else runs that long.
config :riddlr, Oban,
  repo: Riddlr.Repo,
  lifeline: [rescue_after: {5, :minutes}],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron, crontab: [{"0 * * * *", Riddlr.Workers.PrunePhoneCodesWorker}]}
  ],
  queues: [game_lifecycle: 5, notifications: 5, default: 5]

# Configure the endpoint
config :riddlr, RiddlrWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RiddlrWeb.ErrorHTML, json: RiddlrWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Riddlr.PubSub,
  live_view: [signing_salt: "Y54XRpLV"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :riddlr, Riddlr.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.28.2",
  riddlr: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  css: [
    args:
      ~w(css/themes.css css/game.css css/auth.css css/admin-tokens.css css/admin-base.css css/admin.css --bundle --outdir=../priv/static/assets/css),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  riddlr: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Keep phone numbers and phone codes out of request logs.
config :phoenix, :filter_parameters, ["password", "phone", "code"]

# enable timezone conversions of UTC dates
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
