# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
import Config

# Configure Ecto repos for the umbrella apps
config :autonomous_opponent_core, ecto_repos: [AutonomousOpponentV2Core.Repo]
config :autonomous_opponent_web, ecto_repos: [AutonomousOpponentV2Web.Repo]

# Sample configuration:
#
#     config :logger, :console,
#       level: :info,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
