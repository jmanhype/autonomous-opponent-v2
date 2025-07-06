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

# AMQP Configuration for development
# Set to false if RabbitMQ is not available locally
config :autonomous_opponent_core,
  amqp_enabled: true

# Override connection settings from environment if available
if System.get_env("AMQP_URL") do
  config :autonomous_opponent_core,
    amqp_connection: System.get_env("AMQP_URL")
else
  config :autonomous_opponent_core,
    amqp_connection: [
      host: System.get_env("AMQP_HOST", "localhost"),
      port: String.to_integer(System.get_env("AMQP_PORT", "5672")),
      username: System.get_env("AMQP_USERNAME", "guest"),
      password: System.get_env("AMQP_PASSWORD", "guest"),
      virtual_host: System.get_env("AMQP_VHOST", "/"),
      heartbeat: 30,
      connection_timeout: 10_000
    ]
end

# Connection Pool Configuration for development
# Smaller pools for local development
config :autonomous_opponent_core, :connection_pools,
  openai: [
    size: 10,
    max_idle_time: 10_000,
    circuit_breaker: [threshold: 3, timeout: 30_000]
  ],
  anthropic: [
    size: 5,
    max_idle_time: 10_000,
    circuit_breaker: [threshold: 3, timeout: 30_000]
  ],
  google_ai: [
    size: 5,
    max_idle_time: 10_000,
    circuit_breaker: [threshold: 3, timeout: 30_000]
  ],
  local_llm: [
    size: 5,
    max_idle_time: 30_000,
    circuit_breaker: [threshold: 2, timeout: 15_000]
  ],
  vault: [
    size: 3,
    max_idle_time: 30_000,
    circuit_breaker: [threshold: 2, timeout: 15_000]
  ],
  default: [
    size: 5,
    max_idle_time: 30_000,
    circuit_breaker: [threshold: 3, timeout: 30_000]
  ]

# Enable debug logging for connection pools in development
config :logger, level: :debug