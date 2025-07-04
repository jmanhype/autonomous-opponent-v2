defmodule AutonomousOpponentV2Core.MCP.Gateway do
  @moduledoc """
  Main supervisor for MCP Gateway Transport implementation.
  
  Manages HTTP+SSE and WebSocket transports with connection pooling,
  load balancing, and VSM integration.
  """
  use Supervisor
  
  alias AutonomousOpponentV2Core.EventBus
  
  @doc """
  Starts the MCP Gateway supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: AutonomousOpponentV2Core.MCP.ConnectionRegistry},
      {Registry, keys: :duplicate, name: AutonomousOpponentV2Core.MCP.TransportRegistry},
      AutonomousOpponentV2Core.MCP.Pool.ConnectionPool,
      AutonomousOpponentV2Core.MCP.LoadBalancer.ConsistentHash,
      AutonomousOpponentV2Core.MCP.Transport.Router,
      {Task.Supervisor, name: AutonomousOpponentV2Core.MCP.TaskSupervisor}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Reports gateway metrics to VSM S4 (Intelligence) subsystem.
  """
  def report_metrics(metrics) do
    EventBus.publish(:vsm_s4_metrics, %{
      source: :mcp_gateway,
      metrics: metrics,
      timestamp: DateTime.utc_now()
    })
  end
  
  @doc """
  Triggers algedonic signal for critical transport failures.
  """
  def trigger_algedonic(severity, reason) do
    EventBus.publish(:vsm_algedonic, %{
      type: :pain,
      severity: severity,
      source: :mcp_gateway,
      reason: reason,
      timestamp: DateTime.utc_now()
    })
  end
end