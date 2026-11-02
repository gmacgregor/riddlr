import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :riddlr, Riddlr.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "riddlr_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :riddlr, RiddlrWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "mIiEcrgpaS7aAjsZ4nLam7f48oRNAr5KKFQ/U4krB1cbaoCrXOG4AP2S3g85Wc+b",
  server: false

# Tests run over plain http, so the session cookie is not marked Secure.
config :riddlr, :secure_session_cookie, false

# Tests read time through a clock they can hold still — see Riddlr.Clock.Frozen.
# Unfrozen, it passes through to the system clock.
config :riddlr, clock: Riddlr.Clock.Frozen

# Broadcast each guess at once, so a LiveView test sees it without waiting
# for a flush. GameClock tests turn batching on.
config :riddlr, Riddlr.GameClock, batch_feed: false

# Lobby tests apply presence diffs by sending :flush_room themselves.
config :riddlr, RiddlrWeb.GameLive.Lobby, room_flush_ms: 60_000

# Navigate at once when a riddle goes live or ends.
config :riddlr, RiddlrWeb.GameLive.Stagger, max_ms: 0

# Test-only keys for phone encryption and its blind index.
config :riddlr, Riddlr.Vault,
  keys: [{"AES.GCM.V1", "DK9n/Z+Qm/aL3aYHe8LKIci3vbLxJYIaxKh2YtgH0qM="}]

config :riddlr, Riddlr.Hashed.HMAC, secret: "kVDJlKooIlBSKLJURFsZs6KIjGt+vt71C+1MyXqKK74="

# Texts go to the test process. See Riddlr.SMS.Test.
config :riddlr, Riddlr.SMS, adapter: Riddlr.SMS.Test

# In test we don't send emails
config :riddlr, Riddlr.Mailer, adapter: Swoosh.Adapters.Test

# Configure Oban for testing (manual mode - jobs don't auto-execute)
config :riddlr, Oban, testing: :manual

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# One page with contact and privacy details, linked from emails, texts and
# the text consent copy.
config :riddlr, info_url: "http://localhost:4000/info"
