# Config for autonomous_opponent_core
import Config

config :autonomous_opponent_core, 
  ecto_repos: [AutonomousOpponentV2Core.Repo]

# AMQP Configuration
config :autonomous_opponent_core,
  amqp_enabled: true,
  amqp_connection: [
    host: "localhost",
    port: 5672,
    username: "guest",
    password: "guest",
    virtual_host: "/",
    heartbeat: 30,
    connection_timeout: 10_000
  ],
  amqp_pool_size: 10,
  amqp_max_overflow: 5

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

