defmodule AutonomousOpponentV2Core.MCPGateway.Handlers.APIHandler do
  @moduledoc """
  API request handler for MCP Gateway.
  
  Handles standard REST-like API requests through the gateway,
  routing them to appropriate VSM subsystems.
  """
  require Logger
  
  alias AutonomousOpponentV2Core.Core.Metrics
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM
  
  @doc """
  Handle an API request
  """
  def handle_request(request, connection, backend) do
    start_time = System.monotonic_time(:millisecond)
    
    # Extract method and path
    method = request[:method] || "GET"
    path = request[:path]
    
    # Route based on path
    result = case route_api_request(method, path, request) do
      {:ok, response} ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        Metrics.histogram(:mcp_gateway_metrics, "api.request_duration", duration, %{
          method: method,
          path: path,
          status: "success"
        })
        
        {:ok, format_response(response)}
        
      {:error, reason} = error ->
        Logger.error("API request failed: #{inspect(reason)}")
        
        Metrics.counter(:mcp_gateway_metrics, "api.errors", 1, %{
          method: method,
          path: path,
          error: inspect(reason)
        })
        
        error
    end
    
    # Use connection to send response
    result
  end
  
  # Private functions
  
  defp route_api_request("GET", "/api/v1/status", _request) do
    status = %{
      vsm: VSM.System.get_status(),
      timestamp: System.system_time(:millisecond)
    }
    
    {:ok, status}
  end
  
  defp route_api_request("POST", "/api/v1/events", request) do
    # Publish event to EventBus
    event_type = request[:body]["event_type"]
    data = request[:body]["data"]
    
    EventBus.publish(String.to_atom(event_type), data)
    
    {:ok, %{status: "event_published"}}
  end
  
  defp route_api_request("GET", "/api/v1/vsm/" <> subsystem, _request) do
    # Query VSM subsystem
    case String.to_atom(subsystem) do
      s when s in [:s1, :s2, :s3, :s4, :s5] ->
        # Get subsystem status (simplified)
        {:ok, %{subsystem: s, status: "operational"}}
        
      _ ->
        {:error, :invalid_subsystem}
    end
  end
  
  defp route_api_request(_method, _path, _request) do
    {:error, :not_found}
  end
  
  defp format_response(response) do
    %{
      success: true,
      data: response,
      timestamp: System.system_time(:millisecond)
    }
  end
end