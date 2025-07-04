defmodule AutonomousOpponentV2Core.MCP.Gateway do
  @moduledoc """
  Main supervisor for MCP Gateway Transport implementation.
  
  Manages HTTP+SSE and WebSocket transports with connection pooling,
  load balancing, and VSM integration.
  """
  use Supervisor
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  
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
      {Registry, keys: :unique, name: AutonomousOpponentV2Core.MCP.ConfigRegistry},
      AutonomousOpponentV2Core.MCP.Pool.ConnectionPool,
      AutonomousOpponentV2Core.MCP.LoadBalancer.ConsistentHash,
      AutonomousOpponentV2Core.MCP.Transport.Router,
      AutonomousOpponentV2Core.MCP.ConnectionDrainer,
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
  
  @doc """
  Retrieves dashboard metrics for the monitoring LiveView.
  
  Returns metrics including:
  - Connection counts by transport
  - Message throughput
  - Circuit breaker states
  - VSM integration metrics
  - Error rates
  - Connection pool status
  """
  def get_dashboard_metrics do
    try do
      # Get connection counts from registries
      websocket_count = Registry.count(AutonomousOpponentV2Core.MCP.TransportRegistry, {:transport, :websocket})
      sse_count = Registry.count(AutonomousOpponentV2Core.MCP.TransportRegistry, {:transport, :http_sse})
      
      # Get circuit breaker states
      websocket_cb = try do
        cb_info = CircuitBreaker.get_state(:websocket_transport)
        cb_info[:state] || :closed
      catch
        :exit, _ -> :closed
      end
      
      sse_cb = try do
        cb_info = CircuitBreaker.get_state(:http_sse_transport)
        cb_info[:state] || :closed
      catch
        :exit, _ -> :closed
      end
      
      # Get pool status
      pool_status = AutonomousOpponentV2Core.MCP.Pool.ConnectionPool.get_status()
      
      # Get throughput from router
      throughput = AutonomousOpponentV2Core.MCP.Transport.Router.get_throughput()
      
      # Get VSM metrics
      vsm_metrics = get_vsm_metrics()
      
      # Calculate error rates
      error_rates = calculate_error_rates()
      
      metrics = %{
        connections: %{
          websocket: websocket_count,
          http_sse: sse_count,
          total: websocket_count + sse_count
        },
        throughput: throughput,
        circuit_breakers: %{
          websocket: websocket_cb,
          http_sse: sse_cb
        },
        vsm_metrics: vsm_metrics,
        error_rates: error_rates,
        pool_status: pool_status
      }
      
      # Publish to PubSub for LiveView
      Phoenix.PubSub.broadcast(AutonomousOpponentV2.PubSub, "mcp:metrics", {:mcp_metrics_update, metrics})
      
      {:ok, metrics}
    rescue
      e ->
        Logger.error("Failed to get dashboard metrics: #{inspect(e)}")
        {:error, :metrics_unavailable}
    end
  end
  
  defp get_vsm_metrics do
    # Gather VSM-related metrics
    %{
      s1_variety_absorption: get_s1_absorption_rate(),
      s2_coordination_active: is_s2_active?(),
      s3_resource_usage: get_s3_resource_usage(),
      s4_intelligence_events: get_s4_event_count(),
      s5_policy_violations: get_s5_violations(),
      algedonic_signals: get_recent_algedonic_signals()
    }
  end
  
  defp get_s1_absorption_rate do
    # Get variety absorption rate from S1
    case EventBus.call(:vsm_s1_metrics, :get_absorption_rate, 1000) do
      {:ok, rate} -> rate
      _ -> 0
    end
  end
  
  defp is_s2_active? do
    # Check if S2 coordination is active
    case EventBus.call(:vsm_s2_status, :is_coordinating, 1000) do
      {:ok, active} -> active
      _ -> false
    end
  end
  
  defp get_s3_resource_usage do
    # Get resource usage percentage from S3
    case EventBus.call(:vsm_s3_metrics, :get_resource_usage, 1000) do
      {:ok, usage} -> round(usage)
      _ -> 0
    end
  end
  
  defp get_s4_event_count do
    # Get intelligence event count from S4
    case EventBus.call(:vsm_s4_metrics, :get_event_count, 1000) do
      {:ok, count} -> count
      _ -> 0
    end
  end
  
  defp get_s5_violations do
    # Get policy violation count from S5
    case EventBus.call(:vsm_s5_metrics, :get_violation_count, 1000) do
      {:ok, count} -> count
      _ -> 0
    end
  end
  
  defp get_recent_algedonic_signals do
    # Get recent algedonic signals (last 5)
    case EventBus.call(:vsm_algedonic_history, :get_recent, 1000) do
      {:ok, signals} -> Enum.take(signals, 5)
      _ -> []
    end
  end
  
  defp calculate_error_rates do
    # Calculate error rates for each transport
    %{
      websocket: calculate_transport_error_rate(:websocket),
      http_sse: calculate_transport_error_rate(:http_sse)
    }
  end
  
  defp calculate_transport_error_rate(transport) do
    case AutonomousOpponentV2Core.MCP.Transport.Router.get_error_rate(transport) do
      {:ok, rate} -> rate
      _ -> 0.0
    end
  end
  
  @doc """
  Initiates graceful shutdown of the gateway.
  
  This will:
  1. Stop accepting new connections
  2. Notify connected clients
  3. Wait for connections to close (with timeout)
  4. Complete shutdown
  
  Options:
  - timeout: Max time to wait for connections to close (default: 30s)
  """
  def graceful_shutdown(opts \\ []) do
    Logger.info("Initiating graceful shutdown of MCP Gateway")
    
    # Trigger algedonic signal for shutdown
    trigger_algedonic(:medium, :planned_shutdown)
    
    # Start connection draining
    case AutonomousOpponentV2Core.MCP.ConnectionDrainer.start_draining(opts) do
      :ok ->
        Logger.info("Connection draining started successfully")
        {:ok, :draining}
      {:error, reason} ->
        Logger.error("Failed to start connection draining: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Checks if the gateway is currently accepting new connections.
  """
  def accepting_connections? do
    AutonomousOpponentV2Core.MCP.ConnectionDrainer.accepting_connections?()
  end
  
  @doc """
  Forces immediate shutdown without waiting for connections.
  """
  def force_shutdown do
    Logger.warning("Forcing immediate shutdown of MCP Gateway")
    
    # Trigger critical algedonic signal
    trigger_algedonic(:critical, :forced_shutdown)
    
    # Force shutdown
    AutonomousOpponentV2Core.MCP.ConnectionDrainer.force_shutdown()
    
    :ok
  end
end