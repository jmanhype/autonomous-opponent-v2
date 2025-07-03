defmodule AutonomousOpponentV2Web.HealthCheck do
  @moduledoc """
  Health check module for Docker and monitoring
  """

  def check do
    checks = %{
      server: check_server(),
      core_repo: check_repo(AutonomousOpponentV2Core.Repo),
      web_repo: check_repo(AutonomousOpponentV2Web.Repo)
    }
    
    system = %{
      memory: get_memory_usage(),
      process_count: System.schedulers_online()
    }
    
    all_healthy = Enum.all?(checks, fn {_name, result} -> result == :ok end)
    
    health_data = %{
      status: if(all_healthy, do: "healthy", else: "unhealthy"),
      checks: checks,
      system: system,
      timestamp: DateTime.utc_now()
    }
    
    if all_healthy do
      {:ok, health_data}
    else
      {:error, health_data}
    end
  end
  
  defp check_server do
    # In test environment, we might not have a running server
    if Application.get_env(:autonomous_opponent_web, AutonomousOpponentV2Web.Endpoint)[:server] do
      :ok
    else
      :not_running
    end
  end

  defp check_repo(repo) do
    try do
      Ecto.Adapters.SQL.query!(repo, "SELECT 1", [])
      :ok
    rescue
      _ -> :error
    end
  end
  
  defp get_memory_usage do
    :erlang.memory(:total)
  end
end