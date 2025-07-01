ExUnit.start()

# Set up Ecto for testing
# Only set sandbox mode if the repo is configured with the sandbox pool
if Application.get_env(:autonomous_opponent_web, AutonomousOpponentV2Web.Repo)[:pool] == Ecto.Adapters.SQL.Sandbox do
  Ecto.Adapters.SQL.Sandbox.mode(AutonomousOpponentV2Web.Repo, :manual)
end
