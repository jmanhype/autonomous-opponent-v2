# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
import Config

# Configure Ecto repos for the umbrella apps
config :autonomous_opponent_core, ecto_repos: [AutonomousOpponentV2Core.Repo]
config :autonomous_opponent_web, ecto_repos: [AutonomousOpponentV2Web.Repo]

# Configure Phoenix PubSub
config :autonomous_opponent_web, AutonomousOpponentV2Web.PubSub, adapter: Phoenix.PubSub.PG2

# Configure Phoenix to use Jason for JSON parsing
config :phoenix, :json_library, Jason

# Configure Prometheus metrics endpoint
config :autonomous_opponent_web,
  metrics_endpoint_auth_enabled: false,  # Set to true in production
  metrics_endpoint_auth_token: nil,      # Set via METRICS_AUTH_TOKEN env var
  metrics_endpoint_rate_limit: 10,       # Max requests per minute
  metrics_endpoint_cors_enabled: true    # Enable CORS for cross-origin scraping

# Sample configuration:
#
#     config :logger, :console,
#       level: :info,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
