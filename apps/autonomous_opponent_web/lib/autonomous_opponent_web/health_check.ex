defmodule AutonomousOpponentV2Web.HealthCheck do
  @moduledoc """
  Health check module for Docker and monitoring
  """

  def check do
    # Check if the application is running
    if Application.get_env(:autonomous_opponent_web, AutonomousOpponentV2Web.Endpoint)[:server] do
      # Check database connectivity for both repos
      core_repo_healthy = check_repo(AutonomousOpponentV2Core.Repo)
      web_repo_healthy = check_repo(AutonomousOpponentV2.Repo)
      if core_repo_healthy && web_repo_healthy do
        IO.puts("Health check passed")
        :ok
      else
        IO.puts("Health check failed: Database connection error")
        exit({:shutdown, 1})
      end
    else
      IO.puts("Health check failed: Server not running")
      exit({:shutdown, 1})
    end
  end

  defp check_repo(repo) do
    Ecto.Adapters.SQL.query!(repo, "SELECT 1", [])
    true
  rescue
    _ -> false
  end
end