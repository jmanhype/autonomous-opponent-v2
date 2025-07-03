# Start the EventBus before tests
Application.ensure_all_started(:autonomous_opponent_core)

ExUnit.start()

# Set up Ecto for testing
# Only set sandbox mode if the repo is configured with the sandbox pool
if Application.get_env(:autonomous_opponent_core, AutonomousOpponentV2Core.Repo)[:pool] == Ecto.Adapters.SQL.Sandbox do
  Ecto.Adapters.SQL.Sandbox.mode(AutonomousOpponentV2Core.Repo, :manual)
end