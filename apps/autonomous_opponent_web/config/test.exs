import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :autonomous_opponent_web, AutonomousOpponentV2Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_at_least_64_characters_long_for_testing_purposes_only",
  server: false

# In test we don't send emails.
config :autonomous_opponent_web, AutonomousOpponentV2Web.Mailer,
  adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Database configuration is handled in the root config/test.exs file
