defmodule AutonomousOpponentV2Web.HealthCheck do
  @moduledoc """
  Health check module for Docker and monitoring
  """

  def check do
    server_check = check_server()
    
    checks = %{
      server: case server_check do
        :ok -> :ok
        {:not_running, missing} -> "not_running: #{Enum.join(missing, ", ")}"
      end,
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
    # Check if critical processes are actually running
    critical_processes = [
      {AutonomousOpponentV2Core.EventBus, "EventBus"},
      {AutonomousOpponentV2Core.VSM.S1.Operations, "VSM S1"},
      {AutonomousOpponentV2Core.VSM.S5.Policy, "VSM S5"},
      {AutonomousOpponentV2Core.MCP.Server, "MCP Server"},
      {AutonomousOpponentV2Core.AMQP.ConnectionPool, "AMQP Pool"}
    ]
    
    missing_processes = Enum.filter(critical_processes, fn {process_name, _desc} ->
      Process.whereis(process_name) == nil
    end)
    
    if Enum.empty?(missing_processes) do
      :ok
    else
      {:not_running, Enum.map(missing_processes, fn {_name, desc} -> desc end)}
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