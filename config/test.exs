import Config

# Configure your database
# The repos should be configured with their actual module names

# Default configuration for test environment
# These will be overridden by runtime.exs if DATABASE_URLs are provided
config :autonomous_opponent_core, AutonomousOpponentV2Core.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "autonomous_opponent_core_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :autonomous_opponent_web, AutonomousOpponentV2Web.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "autonomous_opponent_web_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :autonomous_opponent_web, AutonomousOpponentV2Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_at_least_64_characters_long_for_testing_purposes_only",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false
