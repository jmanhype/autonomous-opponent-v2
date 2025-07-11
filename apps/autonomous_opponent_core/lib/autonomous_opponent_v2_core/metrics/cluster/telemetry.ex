defmodule AutonomousOpponentV2Core.Metrics.Cluster.Telemetry do
  @moduledoc """
  📊 TELEMETRY INTEGRATION FOR CLUSTER METRICS
  
  This module provides telemetry measurements and handlers for the
  distributed metrics system. It integrates with Elixir's telemetry
  library to provide standardized observability.
  
  ## Measurements
  
  - Node-level metrics collection
  - Cluster-wide aggregation
  - VSM health monitoring
  - Performance metrics
  
  ## Events Emitted
  
  - `[:metrics, :cluster, :aggregation]` - When aggregation completes
  - `[:metrics, :cluster, :query]` - When a distributed query executes
  - `[:metrics, :cluster, :health]` - VSM health status changes
  """
  
  require Logger
  
  alias AutonomousOpponentV2Core.Core.Metrics
  alias AutonomousOpponentV2Core.Metrics.Cluster.{Aggregator, QueryEngine}
  
  # ========== TELEMETRY MEASUREMENTS ==========
  
  @doc """
  Collects metrics from the local node
  """
  def collect_node_metrics do
    start = System.monotonic_time()
    
    # Get all local metrics
    metrics = Metrics.get_all_metrics(Metrics)
    
    # Calculate collection time
    duration = System.monotonic_time() - start
    
    # Emit telemetry
    :telemetry.execute(
      [:metrics, :node, :collected],
      %{
        count: length(metrics),
        duration: duration
      },
      %{
        node: node()
      }
    )
    
    # Return metrics for aggregation
    metrics
  end
  
  @doc """
  Triggers cluster-wide metrics aggregation
  """
  def aggregate_cluster_metrics do
    start = System.monotonic_time()
    
    # Perform aggregation
    case Aggregator.aggregate_cluster_metrics() do
      {:ok, aggregated} ->
        duration = System.monotonic_time() - start
        
        :telemetry.execute(
          [:metrics, :cluster, :aggregated],
          %{
            metrics_count: length(aggregated),
            duration: duration,
            nodes: length(Node.list()) + 1
          },
          %{
            status: :success
          }
        )
        
      {:error, reason} ->
        :telemetry.execute(
          [:metrics, :cluster, :aggregation_failed],
          %{
            duration: System.monotonic_time() - start
          },
          %{
            reason: reason
          }
        )
    end
  end
  
  @doc """
  Checks VSM subsystem health across the cluster
  """
  def check_vsm_health do
    start = System.monotonic_time()
    
    case Aggregator.vsm_health() do
      {:ok, health} ->
        duration = System.monotonic_time() - start
        
        # Check for critical conditions
        algedonic_balance = health.algedonic_balance
        cluster_viability = health.cluster_viability
        
        # Emit health telemetry
        :telemetry.execute(
          [:metrics, :vsm, :health],
          %{
            s1_operational: health.s1_operational,
            s2_coordination: health.s2_coordination,
            s3_control: health.s3_control,
            s4_intelligence: health.s4_intelligence,
            s5_policy: health.s5_policy,
            algedonic_balance: algedonic_balance,
            cluster_viability: cluster_viability,
            variety_pressure: health.variety_pressure,
            duration: duration
          },
          %{
            status: determine_health_status(health)
          }
        )
        
        # Check for algedonic signals
        check_algedonic_thresholds(algedonic_balance)
        
      {:error, reason} ->
        Logger.error("VSM health check failed: #{inspect(reason)}")
    end
  end
  
  # ========== TELEMETRY HANDLERS ==========
  
  @doc """
  Attaches default telemetry handlers for metrics
  """
  def attach_default_handlers do
    handlers = [
      {
        [:metrics, :cluster, :aggregated],
        &handle_aggregation_complete/4,
        nil
      },
      {
        [:metrics, :vsm, :health],
        &handle_vsm_health/4,
        nil
      },
      {
        [:metrics, :cluster, :query],
        &handle_query_metrics/4,
        nil
      }
    ]
    
    Enum.each(handlers, fn {event, handler, config} ->
      handler_id = "#{__MODULE__}-#{Enum.join(event, "-")}"
      
      :telemetry.attach(
        handler_id,
        event,
        handler,
        config
      )
    end)
  end
  
  @doc """
  Detaches all handlers
  """
  def detach_handlers do
    :telemetry.list_handlers()
    |> Enum.filter(fn %{id: id} -> String.starts_with?(id, "#{__MODULE__}") end)
    |> Enum.each(fn %{id: id} -> :telemetry.detach(id) end)
  end
  
  # ========== HANDLER IMPLEMENTATIONS ==========
  
  defp handle_aggregation_complete(_event, measurements, metadata, _config) do
    # Log aggregation metrics
    Logger.info("""
    Cluster metrics aggregated:
    - Metrics: #{measurements.metrics_count}
    - Nodes: #{measurements.nodes}
    - Duration: #{format_duration(measurements.duration)}
    """)
    
    # Update Prometheus metrics
    Metrics.increment(Metrics, "cluster_aggregations_total")
    Metrics.update_histogram(Metrics, "cluster_aggregation_duration_ms", 
      System.convert_time_unit(measurements.duration, :native, :millisecond)
    )
  end
  
  defp handle_vsm_health(_event, measurements, metadata, _config) do
    # Check for critical conditions
    if measurements.cluster_viability < 50 do
      Logger.error("⚠️ Cluster viability critical: #{measurements.cluster_viability}%")
    end
    
    if abs(measurements.algedonic_balance) > 0.8 do
      Logger.warn("🚨 Algedonic imbalance detected: #{measurements.algedonic_balance}")
    end
    
    # Update health metrics
    Enum.each(measurements, fn {key, value} ->
      Metrics.set_gauge(Metrics, "vsm_health_#{key}", value)
    end)
  end
  
  defp handle_query_metrics(_event, measurements, metadata, _config) do
    # Track query performance
    Metrics.increment(Metrics, "cluster_queries_total", %{
      status: metadata.status
    })
    
    Metrics.update_histogram(Metrics, "cluster_query_duration_ms",
      System.convert_time_unit(measurements.duration, :native, :millisecond)
    )
    
    if measurements.nodes_queried do
      Metrics.update_histogram(Metrics, "cluster_query_nodes", measurements.nodes_queried)
    end
  end
  
  # ========== PRIVATE FUNCTIONS ==========
  
  defp determine_health_status(health) do
    cond do
      health.cluster_viability < 30 -> :critical
      health.cluster_viability < 50 -> :degraded
      health.cluster_viability < 80 -> :warning
      true -> :healthy
    end
  end
  
  defp check_algedonic_thresholds(balance) do
    cond do
      balance < -0.8 ->
        # Extreme pain
        :telemetry.execute(
          [:metrics, :algedonic, :pain],
          %{intensity: abs(balance)},
          %{severity: :extreme}
        )
        
      balance > 0.8 ->
        # Extreme pleasure
        :telemetry.execute(
          [:metrics, :algedonic, :pleasure],
          %{intensity: balance},
          %{severity: :extreme}
        )
        
      true ->
        :ok
    end
  end
  
  defp format_duration(native_time) do
    ms = System.convert_time_unit(native_time, :native, :millisecond)
    
    cond do
      ms < 1 -> "#{System.convert_time_unit(native_time, :native, :microsecond)}μs"
      ms < 1000 -> "#{ms}ms"
      true -> "#{Float.round(ms / 1000, 2)}s"
    end
  end
  
  # ========== SPAN HELPERS ==========
  
  @doc """
  Wraps a function call in a telemetry span
  """
  def span(event, metadata \\ %{}, fun) do
    :telemetry.span(
      [:metrics, :cluster | event],
      metadata,
      fun
    )
  end
  
  @doc """
  Executes a distributed query with telemetry
  """
  def measured_query(metric_name, aggregation, opts) do
    span([:query], %{metric: metric_name, aggregation: aggregation}, fn ->
      result = QueryEngine.query(metric_name, aggregation, opts)
      {result, %{}}
    end)
  end
end