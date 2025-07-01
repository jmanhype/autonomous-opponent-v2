# Config for autonomous_opponent_core
import Config

config :autonomous_opponent_core, 
  ecto_repos: [AutonomousOpponentV2Core.Repo]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

