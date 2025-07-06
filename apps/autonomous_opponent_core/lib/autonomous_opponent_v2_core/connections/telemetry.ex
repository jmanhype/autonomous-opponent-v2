defmodule AutonomousOpponentV2Core.Connections.Telemetry do
  @moduledoc """
  Telemetry integration for connection pools.
  
  Provides metrics and monitoring for:
  - Request counts and durations
  - Pool health and utilization
  - Circuit breaker states
  - Error rates and types
  
  ## Metrics
  
  The following telemetry events are emitted:
  
  - `[:pool_manager, :request, :start]` - Request started
  - `[:pool_manager, :request, :stop]` - Request completed
  - `[:pool_manager, :request, :exception]` - Request failed
  - `[:pool_manager, :circuit, :open]` - Circuit breaker opened
  - `[:pool_manager, :circuit, :half_open]` - Circuit breaker half-open
  - `[:pool_manager, :circuit, :close]` - Circuit breaker closed
  - `[:pool_manager, :health_check]` - Health check completed
  """
  
  require Logger
  
  @doc """
  Attaches telemetry handlers for connection pool metrics.
  """
  def attach_handlers do
    events = [
      [:pool_manager, :request, :start],
      [:pool_manager, :request, :stop],
      [:pool_manager, :request, :exception],
      [:pool_manager, :circuit, :open],
      [:pool_manager, :circuit, :half_open],
      [:pool_manager, :circuit, :close],
      [:pool_manager, :health_check]
    ]
    
    :telemetry.attach_many(
      "pool-manager-handler",
      events,
      &handle_event/4,
      nil
    )
  end
  
  @doc """
  Detaches telemetry handlers.
  """
  def detach_handlers do
    :telemetry.detach("pool-manager-handler")
  end
  
  @doc """
  Gets current metrics for all pools.
  """
  def get_metrics do
    %{
      pools: get_pool_metrics(),
      circuit_breakers: get_circuit_breaker_metrics(),
      health_checks: get_health_check_metrics()
    }
  end
  
  # Event Handlers
  
  defp handle_event([:pool_manager, :request, :start], _measurements, metadata, _config) do
    Logger.debug("Pool request started", pool: metadata.pool, url: metadata.url)
  end
  
  defp handle_event([:pool_manager, :request, :stop], measurements, metadata, _config) do
    Logger.debug("Pool request completed",
      pool: metadata.pool,
      duration_ms: measurements.duration,
      status: metadata.status
    )
    
    # Update metrics
    update_pool_metrics(metadata.pool, :success, measurements.duration)
  end
  
  defp handle_event([:pool_manager, :request, :exception], _measurements, metadata, _config) do
    Logger.error("Pool request failed",
      pool: metadata.pool,
      error: metadata.error,
      kind: metadata.kind
    )
    
    # Update metrics
    update_pool_metrics(metadata.pool, :failure, nil)
  end
  
  defp handle_event([:pool_manager, :circuit, :open], _measurements, metadata, _config) do
    Logger.warning("Circuit breaker opened", pool: metadata.pool)
    update_circuit_breaker_metrics(metadata.pool, :open)
  end
  
  defp handle_event([:pool_manager, :circuit, :half_open], _measurements, metadata, _config) do
    Logger.info("Circuit breaker half-open", pool: metadata.pool)
    update_circuit_breaker_metrics(metadata.pool, :half_open)
  end
  
  defp handle_event([:pool_manager, :circuit, :close], _measurements, metadata, _config) do
    Logger.info("Circuit breaker closed", pool: metadata.pool)
    update_circuit_breaker_metrics(metadata.pool, :closed)
  end
  
  defp handle_event([:pool_manager, :health_check], measurements, metadata, _config) do
    status = if metadata.status == :healthy, do: "healthy", else: "unhealthy"
    
    Logger.debug("Health check completed",
      pool: metadata.pool,
      status: status,
      duration_ms: measurements.duration
    )
    
    update_health_check_metrics(metadata.pool, metadata.status, measurements.duration)
  end
  
  # Metrics Storage (using ETS for simplicity)
  
  defp ensure_metrics_table do
    case :ets.whereis(:pool_metrics) do
      :undefined ->
        :ets.new(:pool_metrics, [:named_table, :public, :set])
      table ->
        table
    end
  end
  
  defp update_pool_metrics(pool, status, duration) do
    ensure_metrics_table()
    
    key = {pool, :requests}
    
    :ets.update_counter(
      :pool_metrics,
      key,
      [
        {2, 1}, # total count
        {3, if(status == :success, do: 1, else: 0)}, # success count
        {4, if(status == :failure, do: 1, else: 0)}, # failure count
        {5, duration || 0} # total duration
      ],
      {key, 0, 0, 0, 0}
    )
  end
  
  defp update_circuit_breaker_metrics(pool, state) do
    ensure_metrics_table()
    
    key = {pool, :circuit_breaker}
    
    :ets.insert(:pool_metrics, {key, state, DateTime.utc_now()})
  end
  
  defp update_health_check_metrics(pool, status, duration) do
    ensure_metrics_table()
    
    key = {pool, :health_check}
    
    :ets.insert(:pool_metrics, {key, status, duration, DateTime.utc_now()})
  end
  
  defp get_pool_metrics do
    ensure_metrics_table()
    
    :ets.select(:pool_metrics, [
      {{{:"$1", :requests}, :"$2", :"$3", :"$4", :"$5"},
       [],
       [{:"$1", %{
         total: :"$2",
         success: :"$3",
         failure: :"$4",
         avg_duration: {:div, :"$5", {:max, :"$2", 1}}
       }}]}
    ])
    |> Map.new()
  end
  
  defp get_circuit_breaker_metrics do
    ensure_metrics_table()
    
    :ets.select(:pool_metrics, [
      {{{:"$1", :circuit_breaker}, :"$2", :"$3"},
       [],
       [{:"$1", %{state: :"$2", last_change: :"$3"}}]}
    ])
    |> Map.new()
  end
  
  defp get_health_check_metrics do
    ensure_metrics_table()
    
    :ets.select(:pool_metrics, [
      {{{:"$1", :health_check}, :"$2", :"$3", :"$4"},
       [],
       [{:"$1", %{status: :"$2", duration: :"$3", last_check: :"$4"}}]}
    ])
    |> Map.new()
  end
  
  @doc """
  Exports metrics in Prometheus format.
  """
  def export_prometheus do
    metrics = get_metrics()
    
    lines = []
    
    # Pool request metrics
    lines = lines ++ [
      "# HELP pool_requests_total Total number of pool requests",
      "# TYPE pool_requests_total counter"
    ]
    
    Enum.each(metrics.pools, fn {pool, data} ->
      lines = lines ++ [
        "pool_requests_total{pool=\"#{pool}\",status=\"success\"} #{data.success}",
        "pool_requests_total{pool=\"#{pool}\",status=\"failure\"} #{data.failure}"
      ]
    end)
    
    # Circuit breaker metrics
    lines = lines ++ [
      "",
      "# HELP circuit_breaker_state Current state of circuit breakers",
      "# TYPE circuit_breaker_state gauge"
    ]
    
    Enum.each(metrics.circuit_breakers, fn {pool, data} ->
      state_value = case data.state do
        :open -> 2
        :half_open -> 1
        :closed -> 0
      end
      
      lines = lines ++ [
        "circuit_breaker_state{pool=\"#{pool}\"} #{state_value}"
      ]
    end)
    
    # Health check metrics
    lines = lines ++ [
      "",
      "# HELP pool_health_check_duration_ms Duration of health checks",
      "# TYPE pool_health_check_duration_ms gauge"
    ]
    
    Enum.each(metrics.health_checks, fn {pool, data} ->
      lines = lines ++ [
        "pool_health_check_duration_ms{pool=\"#{pool}\",status=\"#{data.status}\"} #{data.duration}"
      ]
    end)
    
    Enum.join(lines, "\n")
  end
end