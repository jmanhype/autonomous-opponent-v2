defmodule AutonomousOpponentV2Core.Connections.Dashboard do
  @moduledoc """
  Connection Pool Dashboard for monitoring and management.
  
  Provides real-time insights into:
  - Pool utilization and health
  - Circuit breaker states
  - Request metrics and latencies
  - Error rates and types
  
  ## Usage
  
      # Get dashboard data
      {:ok, metrics} = Dashboard.get_metrics()
      
      # Get specific pool metrics
      {:ok, openai_metrics} = Dashboard.get_pool_metrics(:openai)
      
      # Export Prometheus metrics
      prometheus_text = Dashboard.export_prometheus()
  """
  
  alias AutonomousOpponentV2Core.Connections.{PoolManager, HealthChecker, Telemetry}
  alias AutonomousOpponentV2Core.EventBus
  
  @doc """
  Gets comprehensive metrics for all pools.
  """
  def get_metrics do
    pools = get_pool_list()
    
    metrics = %{
      summary: %{
        total_pools: length(pools),
        healthy_pools: count_healthy_pools(pools),
        total_requests: get_total_requests(pools),
        error_rate: calculate_error_rate(pools),
        avg_latency_ms: calculate_avg_latency(pools)
      },
      pools: Enum.map(pools, &get_pool_details/1),
      circuit_breakers: get_circuit_breaker_states(pools),
      health_checks: HealthChecker.get_status(),
      timestamp: DateTime.utc_now()
    }
    
    {:ok, metrics}
  end
  
  @doc """
  Gets detailed metrics for a specific pool.
  """
  def get_pool_metrics(pool_name) do
    case PoolManager.get_stats(pool_name) do
      %{} = stats ->
        details = %{
          pool: pool_name,
          stats: stats,
          health: get_pool_health(pool_name),
          recent_errors: get_recent_errors(pool_name),
          latency_percentiles: calculate_latency_percentiles(pool_name),
          timestamp: DateTime.utc_now()
        }
        
        {:ok, details}
        
      _ ->
        {:error, :pool_not_found}
    end
  end
  
  @doc """
  Exports metrics in Prometheus format.
  """
  def export_prometheus do
    Telemetry.export_prometheus()
  end
  
  @doc """
  Gets real-time stream of pool events.
  """
  def stream_events(callback) do
    # Subscribe to pool events
    events = [
      :pool_request_success,
      :pool_request_failure,
      :pool_circuit_open,
      :pool_circuit_close,
      :pool_unhealthy,
      :pool_recovered
    ]
    
    Enum.each(events, fn event ->
      EventBus.subscribe(event)
    end)
    
    # Start streaming
    spawn(fn ->
      stream_loop(callback, events)
    end)
    
    {:ok, :streaming}
  end
  
  @doc """
  Performs administrative actions on pools.
  """
  def admin_action(pool_name, action) do
    case action do
      :reset_circuit_breaker ->
        reset_circuit_breaker(pool_name)
        
      :force_health_check ->
        PoolManager.health_check(pool_name)
        
      :drain ->
        drain_pool(pool_name)
        
      _ ->
        {:error, :invalid_action}
    end
  end
  
  # Private Functions
  
  defp get_pool_list do
    Application.get_env(:autonomous_opponent_core, :connection_pools, [])
    |> Keyword.keys()
  end
  
  defp count_healthy_pools(pools) do
    health_status = HealthChecker.get_status()
    
    Enum.count(pools, fn pool ->
      case Map.get(health_status, pool) do
        {:healthy, _} -> true
        _ -> false
      end
    end)
  end
  
  defp get_total_requests(pools) do
    metrics = Telemetry.get_metrics()
    
    pools
    |> Enum.map(fn pool ->
      get_in(metrics, [:pools, pool, :total]) || 0
    end)
    |> Enum.sum()
  end
  
  defp calculate_error_rate(pools) do
    metrics = Telemetry.get_metrics()
    
    total = get_total_requests(pools)
    
    if total == 0 do
      0.0
    else
      failures = pools
        |> Enum.map(fn pool ->
          get_in(metrics, [:pools, pool, :failure]) || 0
        end)
        |> Enum.sum()
      
      Float.round(failures / total * 100, 2)
    end
  end
  
  defp calculate_avg_latency(pools) do
    metrics = Telemetry.get_metrics()
    
    latencies = pools
      |> Enum.map(fn pool ->
        get_in(metrics, [:pools, pool, :avg_duration]) || 0
      end)
      |> Enum.filter(&(&1 > 0))
    
    if Enum.empty?(latencies) do
      0
    else
      round(Enum.sum(latencies) / length(latencies))
    end
  end
  
  defp get_pool_details(pool_name) do
    stats = PoolManager.get_stats(pool_name)
    telemetry = Telemetry.get_metrics()
    health = HealthChecker.get_status()[pool_name]
    
    %{
      name: pool_name,
      state: get_pool_state(stats, health),
      requests: %{
        total: get_in(telemetry, [:pools, pool_name, :total]) || 0,
        success: get_in(telemetry, [:pools, pool_name, :success]) || 0,
        failure: get_in(telemetry, [:pools, pool_name, :failure]) || 0,
        error_rate: calculate_pool_error_rate(telemetry, pool_name)
      },
      latency: %{
        avg_ms: get_in(telemetry, [:pools, pool_name, :avg_duration]) || 0,
        p50_ms: 0, # Would need histogram data
        p95_ms: 0,
        p99_ms: 0
      },
      circuit_breaker: stats[:circuit_breaker],
      health_check: health,
      configuration: get_pool_config(pool_name)
    }
  end
  
  defp get_pool_state(stats, health) do
    cond do
      match?({:unhealthy, _}, health) -> :unhealthy
      stats[:circuit_breaker][:state] == :open -> :circuit_open
      true -> :healthy
    end
  end
  
  defp calculate_pool_error_rate(telemetry, pool_name) do
    total = get_in(telemetry, [:pools, pool_name, :total]) || 0
    failures = get_in(telemetry, [:pools, pool_name, :failure]) || 0
    
    if total == 0 do
      0.0
    else
      Float.round(failures / total * 100, 2)
    end
  end
  
  defp get_circuit_breaker_states(pools) do
    telemetry = Telemetry.get_metrics()
    
    Map.new(pools, fn pool ->
      state = get_in(telemetry, [:circuit_breakers, pool]) || %{}
      {pool, state}
    end)
  end
  
  defp get_pool_health(pool_name) do
    case HealthChecker.get_status()[pool_name] do
      {:healthy, duration} ->
        %{status: :healthy, last_check_ms: duration}
        
      {:unhealthy, reason} ->
        %{status: :unhealthy, reason: reason}
        
      _ ->
        %{status: :unknown}
    end
  end
  
  defp get_recent_errors(_pool_name) do
    # Would need to implement error tracking
    []
  end
  
  defp calculate_latency_percentiles(_pool_name) do
    # Would need histogram data
    %{p50: 0, p95: 0, p99: 0}
  end
  
  defp get_pool_config(pool_name) do
    Application.get_env(:autonomous_opponent_core, :connection_pools, [])
    |> Keyword.get(pool_name, [])
    |> Enum.into(%{})
  end
  
  defp reset_circuit_breaker(pool_name) do
    # Would need to implement circuit breaker reset
    {:ok, :reset}
  end
  
  defp drain_pool(pool_name) do
    EventBus.publish(:pool_draining, %{
      pool: pool_name,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, :draining}
  end
  
  defp stream_loop(callback, events) do
    receive do
      {:event, event_name, data} ->
        if event_name in events do
          callback.({event_name, data})
        end
        stream_loop(callback, events)
        
      :stop ->
        Enum.each(events, &EventBus.unsubscribe/1)
        :ok
        
    after
      60_000 ->
        # Keep alive
        stream_loop(callback, events)
    end
  end
end