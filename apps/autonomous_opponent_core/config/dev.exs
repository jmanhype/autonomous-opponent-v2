import Config

# For development, we use the PostgreSQL adapter.
config :autonomous_opponent_core, AutonomousOpponentV2Core.Repo,
  database: "autonomous_opponent_v2_core_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true

# Do not print debug messages for Ecto if it is not needed.
config :ecto, debug_queries: true

# AMQP Configuration
config :autonomous_opponent_core, :amqp_enabled, false  # Set to true when AMQP library supports OTP 27+

# AMQP Connection Configuration
config :autonomous_opponent_core, :amqp_connection, [
  hostname: "localhost",
  username: "guest",
  password: "guest",
  port: 5672,
  virtual_host: "/",
  heartbeat: 30,
  connection_timeout: 5_000
]