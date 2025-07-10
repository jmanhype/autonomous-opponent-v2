defmodule AutonomousOpponentV2Core.EventBus.Cluster.Telemetry do
  @moduledoc """
  Telemetry Integration for EventBus Cluster
  
  This module provides comprehensive telemetry and monitoring for the distributed
  EventBus cluster, following cybernetic principles to ensure observability
  of variety flows, algedonic signals, and system health.
  
  ## Metrics Tracked
  
  1. **Variety Flow Metrics**:
     - Event throughput per channel (S1-S5)
     - Variety pressure by subsystem
     - Compression ratios and efficiency
     - Throttling rates and patterns
  
  2. **Algedonic Signal Metrics**:
     - Emergency scream latency
     - Pain/pleasure signal rates
     - Confirmation success rates
     - Cross-node propagation time
  
  3. **Cluster Health Metrics**:
     - Node connectivity matrix
     - Partition detection events
     - Recovery time measurements
     - Circuit breaker activations
  
  4. **Performance Metrics**:
     - Event replication latency
     - Memory usage patterns
     - CPU utilization during variety spikes
     - Network bandwidth utilization
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.Telemetry
  
  @telemetry_events [
    # Variety flow events
    [:vsm, :cluster, :variety, :flow],
    [:vsm, :cluster, :variety, :pressure],
    [:vsm, :cluster, :variety, :throttled],
    [:vsm, :cluster, :variety, :compressed],
    
    # Algedonic events
    [:vsm, :cluster, :algedonic, :scream_sent],
    [:vsm, :cluster, :algedonic, :scream_received],
    [:vsm, :cluster, :algedonic, :confirmation],
    [:vsm, :cluster, :algedonic, :broadcast_latency],
    
    # Cluster health events
    [:vsm, :cluster, :node, :connected],
    [:vsm, :cluster, :node, :disconnected],
    [:vsm, :cluster, :partition, :detected],
    [:vsm, :cluster, :partition, :healed],
    [:vsm, :cluster, :circuit_breaker, :opened],
    [:vsm, :cluster, :circuit_breaker, :closed],
    
    # Performance events
    [:vsm, :cluster, :replication, :latency],
    [:vsm, :cluster, :replication, :success],
    [:vsm, :cluster, :replication, :failure],
    [:vsm, :cluster, :memory, :usage],
    [:vsm, :cluster, :cpu, :usage]
  ]
  
  defstruct [
    :node_id,
    :metrics_cache,
    :aggregation_window,
    :collection_interval,
    :retention_period
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Report variety flow event
  """
  def report_variety_flow(channel, event_count, pressure) do
    Telemetry.execute(
      [:vsm, :cluster, :variety, :flow],
      %{events: event_count, pressure: pressure},
      %{channel: channel, node: node()}
    )
  end
  
  @doc """
  Report variety throttling
  """
  def report_throttling(channel, throttled_count) do
    Telemetry.execute(
      [:vsm, :cluster, :variety, :throttled],
      %{count: throttled_count},
      %{channel: channel, node: node()}
    )
  end
  
  @doc """
  Report semantic compression
  """
  def report_compression(channel, original_count, compressed_count) do
    ratio = if original_count > 0, do: compressed_count / original_count, else: 0.0
    
    Telemetry.execute(
      [:vsm, :cluster, :variety, :compressed],
      %{
        original: original_count,
        compressed: compressed_count,
        ratio: ratio
      },
      %{channel: channel, node: node()}
    )
  end
  
  @doc """
  Report algedonic scream latency
  """
  def report_algedonic_latency(signal_type, latency_ms, success_count, failure_count) do
    Telemetry.execute(
      [:vsm, :cluster, :algedonic, :broadcast_latency],
      %{
        latency_ms: latency_ms,
        success_count: success_count,
        failure_count: failure_count
      },
      %{signal_type: signal_type, node: node()}
    )
  end
  
  @doc """
  Report partition detection
  """
  def report_partition_detected(partition_count, strategy, resolution_time) do
    Telemetry.execute(
      [:vsm, :cluster, :partition, :detected],
      %{
        partition_count: partition_count,
        resolution_time_ms: resolution_time
      },
      %{strategy: strategy, node: node()}
    )
  end
  
  @doc """
  Report partition healing
  """
  def report_partition_healed(healing_time_ms) do
    Telemetry.execute(
      [:vsm, :cluster, :partition, :healed],
      %{healing_time_ms: healing_time_ms},
      %{node: node()}
    )
  end
  
  @doc """
  Report node connection event
  """
  def report_node_event(event_type, peer_node, connection_time \\ nil) do
    measurements = if connection_time do
      %{connection_time_ms: connection_time}
    else
      %{}
    end
    
    Telemetry.execute(
      [:vsm, :cluster, :node, event_type],
      measurements,
      %{peer_node: peer_node, node: node()}
    )
  end
  
  @doc """
  Report circuit breaker state change
  """
  def report_circuit_breaker(state, node_target, failure_count \\ 0) do
    event = case state do
      :open -> :opened
      :closed -> :closed
      :half_open -> :opened  # Treat half-open as opened for telemetry
    end
    
    Telemetry.execute(
      [:vsm, :cluster, :circuit_breaker, event],
      %{failure_count: failure_count},
      %{target_node: node_target, node: node()}
    )
  end
  
  @doc """
  Get current telemetry metrics summary
  """
  def get_metrics_summary do
    GenServer.call(__MODULE__, :get_metrics_summary)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      node_id: node(),
      metrics_cache: %{},
      aggregation_window: opts[:aggregation_window] || 60_000,  # 1 minute
      collection_interval: opts[:collection_interval] || 10_000,  # 10 seconds
      retention_period: opts[:retention_period] || 3_600_000  # 1 hour
    }
    
    # Attach telemetry handlers
    attach_telemetry_handlers()
    
    # Schedule periodic collection
    schedule_collection(state.collection_interval)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_metrics_summary, _from, state) do
    summary = generate_metrics_summary(state)
    {:reply, summary, state}
  end
  
  @impl true
  def handle_info(:collect_metrics, state) do
    # Collect system metrics
    new_state = collect_system_metrics(state)
    
    # Schedule next collection
    schedule_collection(state.collection_interval)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:telemetry_event, event_name, measurements, metadata}, state) do
    # Cache telemetry events for aggregation
    new_cache = cache_telemetry_event(event_name, measurements, metadata, state.metrics_cache)
    
    {:noreply, %{state | metrics_cache: new_cache}}
  end
  
  # Private Functions
  
  defp attach_telemetry_handlers do
    # Attach handlers for all cluster telemetry events
    :telemetry.attach_many(
      "cluster-telemetry-handler",
      @telemetry_events,
      &handle_telemetry_event/4,
      self()
    )
  end
  
  defp handle_telemetry_event(event_name, measurements, metadata, telemetry_pid) do
    # Forward events to telemetry GenServer for aggregation
    send(telemetry_pid, {:telemetry_event, event_name, measurements, metadata})
  end
  
  defp schedule_collection(interval) do
    Process.send_after(self(), :collect_metrics, interval)
  end
  
  defp collect_system_metrics(state) do
    # Collect memory and CPU metrics
    memory_usage = :erlang.memory()
    
    Telemetry.execute(
      [:vsm, :cluster, :memory, :usage],
      %{
        total: memory_usage[:total],
        processes: memory_usage[:processes],
        atom: memory_usage[:atom],
        binary: memory_usage[:binary],
        ets: memory_usage[:ets]
      },
      %{node: state.node_id}
    )
    
    # CPU utilization (simplified)
    cpu_usage = get_cpu_usage()
    
    Telemetry.execute(
      [:vsm, :cluster, :cpu, :usage],
      %{utilization: cpu_usage},
      %{node: state.node_id}
    )
    
    state
  end
  
  defp get_cpu_usage do
    # Simplified CPU usage calculation
    # In production, use :cpu_sup or external monitoring
    case :cpu_sup.util() do
      {:ok, usage} -> usage
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  end
  
  defp cache_telemetry_event(event_name, measurements, metadata, cache) do
    now = System.monotonic_time(:millisecond)
    
    event_key = {event_name, metadata[:node] || node()}
    
    Map.update(cache, event_key, [%{
      timestamp: now,
      measurements: measurements,
      metadata: metadata
    }], fn events ->
      # Add new event and keep only recent ones (last hour)
      cutoff = now - 3_600_000  # 1 hour ago
      
      new_events = [%{
        timestamp: now,
        measurements: measurements,
        metadata: metadata
      } | events]
      
      Enum.filter(new_events, &(&1.timestamp > cutoff))
    end)
  end
  
  defp generate_metrics_summary(state) do
    now = System.monotonic_time(:millisecond)
    window_start = now - state.aggregation_window
    
    # Aggregate metrics within the time window
    variety_metrics = aggregate_variety_metrics(state.metrics_cache, window_start)
    algedonic_metrics = aggregate_algedonic_metrics(state.metrics_cache, window_start)
    cluster_metrics = aggregate_cluster_metrics(state.metrics_cache, window_start)
    performance_metrics = aggregate_performance_metrics(state.metrics_cache, window_start)
    
    %{
      node: state.node_id,
      timestamp: DateTime.utc_now(),
      window_ms: state.aggregation_window,
      variety: variety_metrics,
      algedonic: algedonic_metrics,
      cluster: cluster_metrics,
      performance: performance_metrics
    }
  end
  
  defp aggregate_variety_metrics(cache, window_start) do
    variety_events = filter_events_by_time(cache, window_start, [:vsm, :cluster, :variety])
    
    %{
      total_flow: sum_measurements(variety_events[:flow] || [], :events),
      avg_pressure: avg_measurements(variety_events[:flow] || [], :pressure),
      total_throttled: sum_measurements(variety_events[:throttled] || [], :count),
      compression_ratio: avg_measurements(variety_events[:compressed] || [], :ratio),
      channels: aggregate_by_channel(variety_events)
    }
  end
  
  defp aggregate_algedonic_metrics(cache, window_start) do
    algedonic_events = filter_events_by_time(cache, window_start, [:vsm, :cluster, :algedonic])
    
    %{
      screams_sent: count_events(algedonic_events[:scream_sent] || []),
      screams_received: count_events(algedonic_events[:scream_received] || []),
      avg_latency_ms: avg_measurements(algedonic_events[:broadcast_latency] || [], :latency_ms),
      success_rate: calculate_success_rate(algedonic_events[:broadcast_latency] || [])
    }
  end
  
  defp aggregate_cluster_metrics(cache, window_start) do
    cluster_events = filter_events_by_time(cache, window_start, [:vsm, :cluster])
    
    %{
      node_connections: count_events(cluster_events[:node] || []),
      partitions_detected: count_events(cluster_events[:partition] || []),
      circuit_breaks: count_events(cluster_events[:circuit_breaker] || [])
    }
  end
  
  defp aggregate_performance_metrics(cache, window_start) do
    perf_events = filter_events_by_time(cache, window_start, [:vsm, :cluster, :replication])
    memory_events = filter_events_by_time(cache, window_start, [:vsm, :cluster, :memory])
    
    %{
      avg_replication_latency_ms: avg_measurements(perf_events[:replication] || [], :latency_ms),
      replication_success_rate: calculate_success_rate(perf_events[:replication] || []),
      memory_usage_mb: avg_measurements(memory_events[:usage] || [], :total) |> bytes_to_mb()
    }
  end
  
  defp filter_events_by_time(cache, window_start, event_prefix) do
    cache
    |> Enum.filter(fn {{event_name, _node}, events} ->
      starts_with_prefix?(event_name, event_prefix) and
      Enum.any?(events, &(&1.timestamp >= window_start))
    end)
    |> Enum.reduce(%{}, fn {{event_name, _node}, events}, acc ->
      # Extract the last part of the event name (e.g., :flow from [:vsm, :cluster, :variety, :flow])
      event_key = List.last(event_name)
      recent_events = Enum.filter(events, &(&1.timestamp >= window_start))
      
      Map.update(acc, event_key, recent_events, &(&1 ++ recent_events))
    end)
  end
  
  defp starts_with_prefix?(event_name, prefix) do
    event_list = if is_list(event_name), do: event_name, else: [event_name]
    prefix_list = if is_list(prefix), do: prefix, else: [prefix]
    
    Enum.take(event_list, length(prefix_list)) == prefix_list
  end
  
  defp sum_measurements(events, key) do
    events
    |> Enum.map(&get_measurement(&1, key))
    |> Enum.sum()
  end
  
  defp avg_measurements([], _key), do: 0.0
  defp avg_measurements(events, key) do
    measurements = Enum.map(events, &get_measurement(&1, key))
    Enum.sum(measurements) / length(measurements)
  end
  
  defp count_events(events), do: length(events)
  
  defp get_measurement(event, key) do
    Map.get(event.measurements, key, 0)
  end
  
  defp calculate_success_rate([]), do: 0.0
  defp calculate_success_rate(events) do
    total_success = sum_measurements(events, :success_count)
    total_failure = sum_measurements(events, :failure_count)
    total = total_success + total_failure
    
    if total > 0, do: total_success / total, else: 0.0
  end
  
  defp aggregate_by_channel(variety_events) do
    # Group events by channel metadata
    variety_events
    |> Enum.flat_map(fn {_type, events} -> events end)
    |> Enum.group_by(&(&1.metadata[:channel]))
    |> Map.new(fn {channel, events} ->
      {channel, %{
        flow: sum_measurements(events, :events),
        pressure: avg_measurements(events, :pressure),
        throttled: sum_measurements(events, :count)
      }}
    end)
  end
  
  defp bytes_to_mb(bytes) when is_number(bytes) do
    Float.round(bytes / (1024 * 1024), 2)
  end
  defp bytes_to_mb(_), do: 0.0
end