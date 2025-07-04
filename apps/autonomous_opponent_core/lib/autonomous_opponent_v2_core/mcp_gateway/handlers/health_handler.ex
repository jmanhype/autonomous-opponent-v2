defmodule AutonomousOpponentV2Core.MCPGateway.Handlers.HealthHandler do
  @moduledoc """
  Health check handler for MCP Gateway.
  
  Provides health status information for monitoring and load balancers.
  """
  
  alias AutonomousOpponentV2Core.MCPGateway.HealthMonitor
  
  @doc """
  Handle health check request
  """
  def handle_request(_request, _connection, _backend) do
    # Get health status from monitor
    health_status = HealthMonitor.status()
    
    # Format response based on overall status
    response = case health_status.overall do
      :healthy ->
        {:ok, format_health_response(health_status, 200)}
        
      :degraded ->
        {:ok, format_health_response(health_status, 200)}  # Still return 200 but with degraded status
        
      :unhealthy ->
        {:error, format_health_response(health_status, 503)}
    end
    
    response
  end
  
  # Private functions
  
  defp format_health_response(health_status, _http_status) do
    %{
      status: health_status.overall,
      timestamp: System.system_time(:millisecond),
      components: health_status.components,
      details: %{
        uptime: System.monotonic_time(:second),
        version: Application.spec(:autonomous_opponent_core, :vsn) |> to_string()
      }
    }
  end
end