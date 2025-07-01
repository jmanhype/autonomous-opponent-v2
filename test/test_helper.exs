ExUnit.start()

# Set up Ecto for testing
# Only set sandbox mode if the repos are configured with the sandbox pool
if Application.get_env(:autonomous_opponent_core, AutonomousOpponentV2Core.Repo)[:pool] == Ecto.Adapters.SQL.Sandbox do
  Ecto.Adapters.SQL.Sandbox.mode(AutonomousOpponentV2Core.Repo, :manual)
end

if Application.get_env(:autonomous_opponent_web, AutonomousOpponentV2Web.Repo)[:pool] == Ecto.Adapters.SQL.Sandbox do
  Ecto.Adapters.SQL.Sandbox.mode(AutonomousOpponentV2Web.Repo, :manual)
end