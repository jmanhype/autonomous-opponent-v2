# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :autonomous_opponent_web,
  ecto_repos: [AutonomousOpponentV2Web.Repo],
  generators: [timestamp_type: :utc_datetime_usec]

# Configures the endpoint
config :autonomous_opponent_web, AutonomousOpponentV2Web.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: AutonomousOpponentV2Web.ErrorHTML, json: AutonomousOpponentV2Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: AutonomousOpponentV2Web.PubSub,
  live_view: [signing_salt: "aBcDeFgH"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
