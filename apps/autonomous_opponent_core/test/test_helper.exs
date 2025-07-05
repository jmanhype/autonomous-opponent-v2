# Disable VSM subsystems in tests
Application.put_env(:autonomous_opponent_core, :start_vsm, false)
Application.put_env(:autonomous_opponent_core, :disable_algedonic_signals, true)
Application.put_env(:autonomous_opponent_core, :amqp_enabled, false)

# Start the EventBus before tests
Application.ensure_all_started(:autonomous_opponent_core)

# Compile test mocks
Code.compile_file("lib/autonomous_opponent_v2_core/test_mocks/phoenix_pubsub.ex")
Code.compile_file("lib/autonomous_opponent_v2_core/test_mocks/vaultex.ex")
Code.compile_file("lib/autonomous_opponent_v2_core/test_mocks/httpoison.ex")
Code.compile_file("lib/autonomous_opponent_v2_core/test_mocks/plug_cowboy.ex")
Code.compile_file("lib/autonomous_opponent_v2_core/test_mocks/plug_cowboy_app.ex")
Code.compile_file("lib/autonomous_opponent_v2_core/test_mocks/autonomous_opponent_web_endpoint.ex")
Code.compile_file("lib/autonomous_opponent_v2_core/test_mocks/pbkdf2.ex")

ExUnit.start()

# Set up Ecto for testing
# Only set sandbox mode if the repo is configured and started
repo_config = Application.get_env(:autonomous_opponent_core, AutonomousOpponentV2Core.Repo)
if repo_config && repo_config[:pool] == Ecto.Adapters.SQL.Sandbox && Process.whereis(AutonomousOpponentV2Core.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(AutonomousOpponentV2Core.Repo, :manual)
end