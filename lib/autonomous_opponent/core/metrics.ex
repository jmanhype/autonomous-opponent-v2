defmodule AutonomousOpponent.Core.Metrics do
  @moduledoc """
  Comprehensive metrics collection system for VSM subsystem monitoring and cybernetic feedback loops.
  
  Provides:
  - Telemetry integration for event-driven metrics
  - Prometheus format exporters for industry-standard monitoring
  - VSM-specific metrics for S1-S5 subsystems
  - Variety flow and algedonic signal tracking
  - Real-time dashboards and alerting
  - ETS-based storage with periodic persistence
  
  ## Wisdom Preservation
  
  ### Why Metrics Matter in VSM
  Beer's VSM requires continuous feedback loops. Without metrics, the system is blind.
  Metrics are the nervous system - they carry signals about system health, variety flow,
  and algedonic pain/pleasure throughout the organism. This module makes the invisible visible.
  
  ### Design Decisions & Rationale
  
  1. **Telemetry as Event Bus**: :telemetry provides a standard, performant way to emit
     metrics without coupling producers to consumers. It's the nervous system's synapses.
  
  2. **Prometheus Format**: Industry standard that works with Grafana, AlertManager, etc.
     Don't reinvent wheels - use tools ops teams already know.
  
  3. **ETS for Speed**: Metrics must be FAST. ETS provides sub-microsecond reads/writes
     with concurrent access. GenServer state would bottleneck under load.
  
  4. **Periodic Persistence**: ETS is in-memory, so we periodically dump to disk. Balance
     between durability (every write) and performance (never write). Default: 60s.
  
  5. **VSM-Specific Metrics**: Generic metrics miss the point. We track variety flow,
     algedonic signals, and cybernetic loop performance - the vital signs of a VSM.
  """
  use GenServer
  require Logger
  
  alias AutonomousOpponent.EventBus
  
  # Metric types
  @type metric_type :: :counter | :gauge | :histogram | :summary
  @type subsystem :: :s1 | :s2 | :s3 | :s4 | :s5
  
  # Client API
  
  @doc """
  Starts the metrics system with the given options.
  
  Options:
    - name: The registered name for the metrics system
    - persist_interval_ms: How often to persist to disk (default: 60_000)
    - persist_path: Where to save metrics (default: "priv/metrics")
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Record a counter metric (always increments)
  """
  def counter(name, metric_name, value \\ 1, tags \\ %{}) do
    GenServer.cast(name, {:record, :counter, metric_name, value, tags})
  end
  
  @doc """
  Record a gauge metric (can go up or down)
  """
  def gauge(name, metric_name, value, tags \\ %{}) do
    GenServer.cast(name, {:record, :gauge, metric_name, value, tags})
  end
  
  @doc """
  Record a histogram metric (for distributions)
  """
  def histogram(name, metric_name, value, tags \\ %{}) do
    GenServer.cast(name, {:record, :histogram, metric_name, value, tags})
  end
  
  @doc """
  Record a summary metric (for percentiles)
  """
  def summary(name, metric_name, value, tags \\ %{}) do
    GenServer.cast(name, {:record, :summary, metric_name, value, tags})
  end
  
  @doc """
  Record VSM subsystem metrics
  """
  def vsm_metric(name, subsystem, metric_name, value, type \\ :gauge)
      when subsystem in [:s1, :s2, :s3, :s4, :s5] do
    tags = %{subsystem: subsystem}
    GenServer.cast(name, {:record, type, "vsm.#{metric_name}", value, tags})
  end
  
  @doc """
  Record variety flow metrics
  """
  def variety_flow(name, subsystem, absorbed, generated) do
    tags = %{subsystem: subsystem}
    GenServer.cast(name, {:variety_flow, absorbed, generated, tags})
  end
  
  @doc """
  Record algedonic signal
  """
  def algedonic_signal(name, type, intensity, source)
      when type in [:pain, :pleasure] do
    tags = %{type: type, source: source}
    GenServer.cast(name, {:algedonic, type, intensity, tags})
  end
  
  @doc """
  Get metrics in Prometheus format
  """
  def prometheus_format(name) do
    GenServer.call(name, :prometheus_format)
  end
  
  @doc """
  Get all metrics
  """
  def get_all_metrics(name) do
    GenServer.call(name, :get_all_metrics)
  end
  
  @doc """
  Get VSM dashboard data
  """
  def get_vsm_dashboard(name) do
    GenServer.call(name, :get_vsm_dashboard)
  end
  
  @doc """
  Check alert conditions and return triggered alerts
  """
  def check_alerts(name) do
    GenServer.call(name, :check_alerts)
  end
  
  @doc """
  Manually persist metrics to disk
  """
  def persist(name) do
    GenServer.call(name, :persist)
  end
  
  # Server implementation
  
  defstruct [
    :name,
    :metrics_table,
    :alerts_table,
    :persist_interval_ms,
    :persist_path,
    :persist_timer,
    :telemetry_handlers
  ]
  
  @impl true
  def init(opts) do
    # Create ETS tables
    metrics_table = :"#{opts[:name]}_metrics"
    alerts_table = :"#{opts[:name]}_alerts"
    
    :ets.new(metrics_table, [:named_table, :public, :set, {:write_concurrency, true}])
    :ets.new(alerts_table, [:named_table, :public, :set, {:write_concurrency, true}])
    
    # Initialize default alerts
    init_default_alerts(alerts_table)
    
    # Setup telemetry handlers
    handlers = setup_telemetry_handlers(opts[:name])
    
    state = %__MODULE__{
      name: opts[:name] || __MODULE__,
      metrics_table: metrics_table,
      alerts_table: alerts_table,
      persist_interval_ms: opts[:persist_interval_ms] || 60_000,
      persist_path: opts[:persist_path] || "priv/metrics",
      telemetry_handlers: handlers
    }
    
    # Start persistence timer
    timer_ref = Process.send_after(self(), :persist, state.persist_interval_ms)
    state = %{state | persist_timer: timer_ref}
    
    # Subscribe to EventBus events
    EventBus.subscribe(:algedonic_pain)
    EventBus.subscribe(:algedonic_pleasure)
    EventBus.subscribe(:circuit_breaker_opened)
    EventBus.subscribe(:circuit_breaker_closed)
    EventBus.subscribe(:rate_limit_allowed)
    EventBus.subscribe(:rate_limited)
    
    # Restore persisted metrics if available
    restore_metrics(state)
    
    # Publish initialization event
    EventBus.publish(:metrics_initialized, %{
      name: state.name,
      tables: %{
        metrics: state.metrics_table,
        alerts: state.alerts_table
      }
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:record, type, metric_name, value, tags}, state) do
    # Generate unique key with tags
    key = build_metric_key(metric_name, tags)
    
    # Update metric based on type
    case type do
      :counter ->
        :ets.update_counter(state.metrics_table, key, {2, value}, {key, 0})
        
      :gauge ->
        :ets.insert(state.metrics_table, {key, value})
        
      :histogram ->
        update_histogram(state.metrics_table, key, value)
        
      :summary ->
        update_summary(state.metrics_table, key, value)
    end
    
    # Emit telemetry event
    :telemetry.execute(
      [:autonomous_opponent, :metrics, type],
      %{value: value},
      Map.put(tags, :metric_name, metric_name)
    )
    
    {:noreply, state}
  end
  
  def handle_cast({:variety_flow, absorbed, generated, tags}, state) do
    # Record variety metrics
    base_tags = Map.put(tags, :flow, :absorbed)
    key_absorbed = build_metric_key("vsm.variety_absorbed", base_tags)
    :ets.insert(state.metrics_table, {key_absorbed, absorbed})
    
    base_tags = Map.put(tags, :flow, :generated)
    key_generated = build_metric_key("vsm.variety_generated", base_tags)
    :ets.insert(state.metrics_table, {key_generated, generated})
    
    # Calculate variety attenuation (Ashby's Law)
    attenuation = if absorbed > 0, do: generated / absorbed, else: 0
    base_tags = Map.put(tags, :flow, :attenuation)
    key_attenuation = build_metric_key("vsm.variety_attenuation", base_tags)
    :ets.insert(state.metrics_table, {key_attenuation, attenuation})
    
    {:noreply, state}
  end
  
  def handle_cast({:algedonic, type, intensity, tags}, state) do
    # Record algedonic signal
    key = build_metric_key("vsm.algedonic.#{type}", tags)
    :ets.insert(state.metrics_table, {key, intensity})
    
    # Update cumulative algedonic balance
    update_algedonic_balance(state.metrics_table, type, intensity)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_call(:prometheus_format, _from, state) do
    # Convert all metrics to Prometheus text format
    metrics = :ets.tab2list(state.metrics_table)
    
    prometheus_text = 
      metrics
      |> Enum.map(&format_prometheus_metric/1)
      |> Enum.join("\n")
    
    {:reply, prometheus_text, state}
  end
  
  def handle_call(:get_all_metrics, _from, state) do
    metrics = :ets.tab2list(state.metrics_table)
    {:reply, metrics, state}
  end
  
  def handle_call(:get_vsm_dashboard, _from, state) do
    # Build VSM dashboard data
    dashboard = %{
      subsystems: build_subsystem_metrics(state.metrics_table),
      variety_flow: build_variety_flow_metrics(state.metrics_table),
      algedonic_balance: get_algedonic_balance(state.metrics_table),
      cybernetic_loops: build_loop_metrics(state.metrics_table),
      system_health: calculate_system_health(state.metrics_table)
    }
    
    {:reply, dashboard, state}
  end
  
  def handle_call(:check_alerts, _from, state) do
    # Check all alert conditions
    alerts = :ets.tab2list(state.alerts_table)
    metrics = :ets.tab2list(state.metrics_table)
    
    triggered_alerts = 
      alerts
      |> Enum.map(fn {alert_name, config} ->
        check_alert_condition(alert_name, config, metrics)
      end)
      |> Enum.filter(& &1)
    
    {:reply, triggered_alerts, state}
  end
  
  def handle_call(:persist, _from, state) do
    persist_metrics(state)
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_info(:persist, state) do
    persist_metrics(state)
    
    # Schedule next persistence
    timer_ref = Process.send_after(self(), :persist, state.persist_interval_ms)
    {:noreply, %{state | persist_timer: timer_ref}}
  end
  
  def handle_info({:event, event_name, data}, state) do
    # Handle EventBus events
    case event_name do
      :algedonic_pain ->
        algedonic_signal(state.name, :pain, data.severity, data.source)
        
      :algedonic_pleasure ->
        algedonic_signal(state.name, :pleasure, data.intensity, data.source)
        
      :circuit_breaker_opened ->
        counter(state.name, "circuit_breaker.opened", 1, %{name: data.name})
        
      :circuit_breaker_closed ->
        counter(state.name, "circuit_breaker.closed", 1, %{name: data.name})
        
      :rate_limit_allowed ->
        counter(state.name, "rate_limiter.allowed", 1, %{name: data.name})
        
      :rate_limited ->
        counter(state.name, "rate_limiter.limited", 1, %{name: data.name})
        
      _ ->
        :ok
    end
    
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Cancel persistence timer
    if state.persist_timer do
      Process.cancel_timer(state.persist_timer)
    end
    
    # Remove telemetry handlers
    Enum.each(state.telemetry_handlers, fn handler_id ->
      :telemetry.detach(handler_id)
    end)
    
    # Final persistence
    persist_metrics(state)
    
    :ok
  end
  
  # Private functions
  
  defp build_metric_key(name, tags) when map_size(tags) == 0 do
    name
  end
  
  defp build_metric_key(name, tags) do
    tag_string = 
      tags
      |> Enum.sort()
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join(",")
    
    "#{name}{#{tag_string}}"
  end
  
  defp update_histogram(table, key, value) do
    case :ets.lookup(table, key) do
      [] ->
        # Initialize histogram
        :ets.insert(table, {key, %{
          count: 1,
          sum: value,
          min: value,
          max: value,
          buckets: update_buckets(%{}, value)
        }})
        
      [{^key, hist}] ->
        # Update histogram
        updated = %{
          count: hist.count + 1,
          sum: hist.sum + value,
          min: min(hist.min, value),
          max: max(hist.max, value),
          buckets: update_buckets(hist.buckets, value)
        }
        :ets.insert(table, {key, updated})
    end
  end
  
  defp update_buckets(buckets, value) do
    # Standard Prometheus buckets
    bucket_limits = [0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1, 2.5, 5, 7.5, 10]
    
    Enum.reduce(bucket_limits, buckets, fn limit, acc ->
      if value <= limit do
        Map.update(acc, limit, 1, &(&1 + 1))
      else
        acc
      end
    end)
  end
  
  defp update_summary(table, key, value) do
    case :ets.lookup(table, key) do
      [] ->
        # Initialize summary
        :ets.insert(table, {key, %{
          count: 1,
          sum: value,
          values: [value]
        }})
        
      [{^key, summary}] ->
        # Keep last 1000 values for percentile calculation
        values = [value | summary.values] |> Enum.take(1000)
        updated = %{
          count: summary.count + 1,
          sum: summary.sum + value,
          values: values
        }
        :ets.insert(table, {key, updated})
    end
  end
  
  defp format_prometheus_metric({key, value}) when is_number(value) do
    "#{key} #{value}"
  end
  
  defp format_prometheus_metric({key, %{count: count, sum: sum, min: min, max: max, buckets: buckets}}) do
    # Format histogram
    base_name = String.replace(key, ~r/\{.*\}/, "")
    
    bucket_lines = 
      buckets
      |> Enum.sort()
      |> Enum.map(fn {limit, count} ->
        "#{base_name}_bucket{le=\"#{limit}\"} #{count}"
      end)
      |> Enum.join("\n")
    
    """
    #{bucket_lines}
    #{base_name}_bucket{le=\"+Inf\"} #{count}
    #{base_name}_count #{count}
    #{base_name}_sum #{sum}
    """
  end
  
  defp format_prometheus_metric({key, %{count: count, sum: sum, values: values}}) do
    # Format summary with percentiles
    sorted = Enum.sort(values)
    p50 = percentile(sorted, 0.5)
    p90 = percentile(sorted, 0.9)
    p99 = percentile(sorted, 0.99)
    
    base_name = String.replace(key, ~r/\{.*\}/, "")
    
    """
    #{base_name}{quantile=\"0.5\"} #{p50}
    #{base_name}{quantile=\"0.9\"} #{p90}
    #{base_name}{quantile=\"0.99\"} #{p99}
    #{base_name}_count #{count}
    #{base_name}_sum #{sum}
    """
  end
  
  defp format_prometheus_metric(_), do: ""
  
  defp percentile([], _), do: 0
  defp percentile(sorted_list, p) do
    k = round(p * length(sorted_list))
    Enum.at(sorted_list, max(k - 1, 0))
  end
  
  defp update_algedonic_balance(table, type, intensity) do
    key = "vsm.algedonic.balance"
    
    change = case type do
      :pain -> -intensity
      :pleasure -> intensity
    end
    
    :ets.update_counter(table, key, {2, change}, {key, 0})
  end
  
  defp get_algedonic_balance(table) do
    case :ets.lookup(table, "vsm.algedonic.balance") do
      [] -> 0
      [{_, balance}] -> balance
    end
  end
  
  defp build_subsystem_metrics(table) do
    # Extract metrics for each VSM subsystem
    [:s1, :s2, :s3, :s4, :s5]
    |> Enum.map(fn subsystem ->
      metrics = :ets.match_object(table, {{:_, %{subsystem: subsystem}}, :_})
      
      {subsystem, %{
        metrics_count: length(metrics),
        health_score: calculate_subsystem_health(metrics)
      }}
    end)
    |> Map.new()
  end
  
  defp calculate_subsystem_health(metrics) do
    # Simple health score based on metric values
    # In production, this would be more sophisticated
    if length(metrics) > 0, do: 100, else: 0
  end
  
  defp build_variety_flow_metrics(table) do
    # Get variety flow metrics
    absorbed = :ets.match_object(table, {"vsm.variety_absorbed" <> :_, :_})
    generated = :ets.match_object(table, {"vsm.variety_generated" <> :_, :_})
    attenuation = :ets.match_object(table, {"vsm.variety_attenuation" <> :_, :_})
    
    %{
      total_absorbed: sum_metric_values(absorbed),
      total_generated: sum_metric_values(generated),
      avg_attenuation: avg_metric_values(attenuation)
    }
  end
  
  defp sum_metric_values(metrics) do
    metrics
    |> Enum.map(fn {_, value} -> value end)
    |> Enum.sum()
  end
  
  defp avg_metric_values([]), do: 0
  defp avg_metric_values(metrics) do
    values = Enum.map(metrics, fn {_, value} -> value end)
    Enum.sum(values) / length(values)
  end
  
  defp build_loop_metrics(table) do
    # Placeholder for cybernetic loop metrics
    %{
      feedback_loops_active: 5,
      avg_loop_latency_ms: 25,
      control_effectiveness: 0.85
    }
  end
  
  defp calculate_system_health(table) do
    # Overall system health based on multiple factors
    algedonic = get_algedonic_balance(table)
    
    # Simple health calculation
    cond do
      algedonic > 10 -> :excellent
      algedonic > 0 -> :good
      algedonic > -10 -> :fair
      true -> :poor
    end
  end
  
  defp setup_telemetry_handlers(name) do
    # WISDOM: Telemetry integration
    # We attach handlers for various system events to automatically collect metrics.
    # This creates a passive monitoring system that doesn't interfere with operations.
    
    handlers = [
      # VSM subsystem events
      {
        "#{name}.vsm.s1",
        [:autonomous_opponent, :vsm, :s1, :operation],
        &handle_vsm_telemetry/4,
        %{metrics: name, subsystem: :s1}
      },
      {
        "#{name}.vsm.s2",
        [:autonomous_opponent, :vsm, :s2, :coordination],
        &handle_vsm_telemetry/4,
        %{metrics: name, subsystem: :s2}
      },
      {
        "#{name}.vsm.s3",
        [:autonomous_opponent, :vsm, :s3, :control],
        &handle_vsm_telemetry/4,
        %{metrics: name, subsystem: :s3}
      },
      {
        "#{name}.vsm.s4",
        [:autonomous_opponent, :vsm, :s4, :intelligence],
        &handle_vsm_telemetry/4,
        %{metrics: name, subsystem: :s4}
      },
      {
        "#{name}.vsm.s5",
        [:autonomous_opponent, :vsm, :s5, :policy],
        &handle_vsm_telemetry/4,
        %{metrics: name, subsystem: :s5}
      }
    ]
    
    # Attach all handlers
    Enum.each(handlers, fn {handler_id, event, function, config} ->
      :telemetry.attach(handler_id, event, function, config)
    end)
    
    # Return handler IDs for cleanup
    Enum.map(handlers, fn {handler_id, _, _, _} -> handler_id end)
  end
  
  defp handle_vsm_telemetry(_event_name, measurements, metadata, config) do
    # Record VSM subsystem metrics from telemetry events
    metrics_name = config.metrics
    subsystem = config.subsystem
    
    # Record operation duration if available
    if duration = measurements[:duration] do
      histogram(metrics_name, "vsm.operation_duration", duration, %{subsystem: subsystem})
    end
    
    # Record success/failure
    if metadata[:result] do
      case metadata[:result] do
        :ok -> counter(metrics_name, "vsm.operations.success", 1, %{subsystem: subsystem})
        :error -> counter(metrics_name, "vsm.operations.failure", 1, %{subsystem: subsystem})
      end
    end
  end
  
  defp init_default_alerts(table) do
    # WISDOM: Default alerts
    # These alerts represent the vital signs of a healthy VSM system.
    # They're not arbitrary thresholds but cybernetic boundaries.
    
    default_alerts = [
      # Algedonic balance alerts
      {:algedonic_severe_pain, %{
        metric: "vsm.algedonic.balance",
        condition: :less_than,
        threshold: -50,
        severity: :critical,
        message: "System experiencing severe pain - immediate intervention required"
      }},
      
      # Variety attenuation alerts
      {:variety_explosion, %{
        metric: "vsm.variety_attenuation",
        condition: :greater_than,
        threshold: 2.0,
        severity: :warning,
        message: "Variety generation exceeding absorption - system may destabilize"
      }},
      
      # Circuit breaker alerts
      {:circuit_breakers_open, %{
        metric: "circuit_breaker.opened",
        condition: :greater_than,
        threshold: 3,
        severity: :error,
        message: "Multiple circuit breakers open - cascading failure risk"
      }},
      
      # Rate limiting alerts
      {:high_rate_limiting, %{
        metric: "rate_limiter.limited",
        condition: :greater_than,
        threshold: 100,
        severity: :warning,
        message: "High rate limiting detected - possible overload"
      }}
    ]
    
    Enum.each(default_alerts, fn {name, config} ->
      :ets.insert(table, {name, config})
    end)
  end
  
  defp check_alert_condition(alert_name, config, metrics) do
    # Find the metric value
    metric_key = config.metric
    
    value = 
      metrics
      |> Enum.find(fn {key, _} -> String.starts_with?(key, metric_key) end)
      |> case do
        nil -> nil
        {_, v} when is_number(v) -> v
        {_, %{count: count}} -> count
        _ -> nil
      end
    
    if value && triggered?(value, config.condition, config.threshold) do
      %{
        alert: alert_name,
        severity: config.severity,
        message: config.message,
        value: value,
        threshold: config.threshold,
        timestamp: System.monotonic_time(:millisecond)
      }
    else
      nil
    end
  end
  
  defp triggered?(value, :greater_than, threshold), do: value > threshold
  defp triggered?(value, :less_than, threshold), do: value < threshold
  defp triggered?(value, :equal_to, threshold), do: value == threshold
  
  defp persist_metrics(state) do
    # Ensure persist directory exists
    File.mkdir_p!(state.persist_path)
    
    # Build persistence file path with timestamp
    timestamp = System.os_time(:second)
    file_path = Path.join(state.persist_path, "metrics_#{timestamp}.ets")
    
    # Dump tables to disk
    :ets.tab2file(state.metrics_table, String.to_charlist(file_path))
    
    # Keep only last 10 persistence files
    cleanup_old_persistence_files(state.persist_path)
    
    Logger.debug("Persisted metrics to #{file_path}")
  end
  
  defp restore_metrics(state) do
    # Find most recent persistence file
    case list_persistence_files(state.persist_path) do
      [] ->
        Logger.debug("No persisted metrics found")
        
      files ->
        latest = List.last(files)
        file_path = Path.join(state.persist_path, latest)
        
        case :ets.file2tab(String.to_charlist(file_path)) do
          {:ok, temp_table} ->
            # Copy data from temp table to our table
            :ets.tab2list(temp_table)
            |> Enum.each(fn entry ->
              :ets.insert(state.metrics_table, entry)
            end)
            
            :ets.delete(temp_table)
            Logger.info("Restored metrics from #{file_path}")
            
          {:error, reason} ->
            Logger.error("Failed to restore metrics: #{inspect(reason)}")
        end
    end
  end
  
  defp list_persistence_files(path) do
    case File.ls(path) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.starts_with?(&1, "metrics_"))
        |> Enum.sort()
        
      _ ->
        []
    end
  end
  
  defp cleanup_old_persistence_files(path) do
    files = list_persistence_files(path)
    
    if length(files) > 10 do
      # Delete oldest files
      files
      |> Enum.take(length(files) - 10)
      |> Enum.each(fn file ->
        File.rm(Path.join(path, file))
      end)
    end
  end
end