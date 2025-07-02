defmodule AutonomousOpponent.Core.Metrics do
  @moduledoc """
  Comprehensive metrics collection system for VSM subsystem monitoring and cybernetic feedback loops.
  
  Provides real-time telemetry collection, Prometheus format export, and persistent storage
  for critical system metrics including VSM subsystems S1-S5, variety measurements, 
  algedonic signals, and cybernetic loop performance.

  ## Features
  
  - Real-time metric collection via :telemetry
  - Prometheus-compatible metric export
  - ETS-based storage with periodic persistence
  - VSM-specific metrics (variety, algedonic signals, loop latency)
  - Automatic alerting based on configurable thresholds
  - Integration with CircuitBreaker and RateLimiter

  ## Wisdom Preservation

  ### Why Metrics Exist
  The metrics system is the VSM's "sensory nervous system" - it allows the organism to
  feel its own state. Beer understood that management requires measurement, but not just
  any measurement - the RIGHT measurements. We measure variety, not just volume. We track
  algedonic signals, not just errors. This isn't monitoring; it's proprioception.

  ### Design Decisions & Rationale

  1. **ETS with Periodic Persistence**: ETS gives us speed (metrics must never slow the
     system), while periodic persistence ensures we don't lose history. The 30-second
     persistence interval balances data safety with I/O efficiency.

  2. **Telemetry Integration**: We use Erlang's :telemetry because it's the ecosystem
     standard. This allows other BEAM applications to consume our metrics without
     coupling. Loose coupling = high variety management.

  3. **Prometheus Format**: While not perfect, Prometheus has become the de facto standard
     for metrics. Its dimensional model maps well to VSM concepts - labels become channels
     for variety analysis.

  4. **VSM-Specific Metrics**: Traditional metrics (CPU, memory) tell us about the machine.
     VSM metrics (variety, algedonic signals, loop latency) tell us about the organism.
     We care more about adaptive capacity than raw performance.

  5. **Sliding Windows**: All aggregations use sliding windows (default 60s). This gives
     us real-time insight without infinite memory growth. The organism remembers the
     recent past, not ancient history.
  """
  use GenServer
  require Logger

  alias AutonomousOpponent.EventBus

  @persistence_interval 30_000  # 30 seconds
  @window_size 60_000          # 60 second sliding window
  @ets_table_name :autonomous_metrics
  @persistence_table :autonomous_metrics_persistence

  # Metric types for Prometheus compatibility
  @type metric_type :: :counter | :gauge | :histogram | :summary
  @type metric_name :: atom()
  @type labels :: map()
  @type metric_value :: number()

  # VSM-specific metric categories
  @vsm_subsystems [:s1, :s2, :s3, :s3_star, :s4, :s5]
  @algedonic_types [:pain, :pleasure, :neutral]

  # Client API

  @doc """
  Starts the metrics system.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a counter metric (monotonically increasing value).
  
  ## Examples
      
      Metrics.counter(:requests_total, 1, %{method: "GET", status: 200})
      Metrics.counter(:vsm_messages_total, 1, %{subsystem: :s1, direction: :input})
  """
  def counter(name, value \\ 1, labels \\ %{}) when is_number(value) and value >= 0 do
    GenServer.cast(__MODULE__, {:counter, name, value, labels})
  end

  @doc """
  Records a gauge metric (point-in-time value).
  
  ## Examples
      
      Metrics.gauge(:connection_pool_size, 45, %{pool: "database"})
      Metrics.gauge(:vsm_variety_ratio, 0.75, %{subsystem: :s3})
  """
  def gauge(name, value, labels \\ %{}) when is_number(value) do
    GenServer.cast(__MODULE__, {:gauge, name, value, labels})
  end

  @doc """
  Records a histogram metric (samples for distribution analysis).
  
  ## Examples
      
      Metrics.histogram(:request_duration_ms, 125, %{endpoint: "/api/health"})
      Metrics.histogram(:cybernetic_loop_latency_ms, 50, %{loop: "s1_to_s2"})
  """
  def histogram(name, value, labels \\ %{}) when is_number(value) do
    GenServer.cast(__MODULE__, {:histogram, name, value, labels})
  end

  @doc """
  Records a VSM-specific metric.
  
  ## Examples
      
      Metrics.vsm_metric(:variety_absorbed, 0.85, :s3)
      Metrics.vsm_metric(:algedonic_signal, 1, :s5, %{type: :pain, severity: :high})
  """
  def vsm_metric(metric_type, value, subsystem, extra_labels \\ %{}) 
      when subsystem in @vsm_subsystems do
    labels = Map.merge(extra_labels, %{subsystem: subsystem})
    
    case metric_type do
      :variety_absorbed -> gauge(:"vsm_variety_absorbed_ratio", value, labels)
      :variety_generated -> gauge(:"vsm_variety_generated_ratio", value, labels)
      :algedonic_signal -> histogram(:"vsm_algedonic_signals", value, labels)
      :loop_latency -> histogram(:"vsm_loop_latency_ms", value, labels)
      _ -> Logger.warn("Unknown VSM metric type: #{metric_type}")
    end
  end

  @doc """
  Records an algedonic signal (pain/pleasure).
  
  ## Examples
      
      Metrics.algedonic(:pain, :high, %{source: :circuit_breaker, component: "api"})
      Metrics.algedonic(:pleasure, :medium, %{source: :rate_limiter, reason: "recovered"})
  """
  def algedonic(type, severity, metadata \\ %{}) when type in @algedonic_types do
    severity_value = case severity do
      :low -> 0.3
      :medium -> 0.6
      :high -> 1.0
      value when is_number(value) -> value
    end

    labels = Map.merge(metadata, %{type: type, severity: severity})
    histogram(:algedonic_signals, severity_value, labels)
    
    # Publish to event bus for S5 immediate response
    EventBus.publish(:"algedonic_#{type}", Map.merge(metadata, %{
      severity: severity,
      value: severity_value,
      timestamp: System.system_time(:millisecond)
    }))
  end

  @doc """
  Retrieves current metrics in Prometheus format.
  
  ## Examples
      
      Metrics.export(:prometheus)
      # Returns string in Prometheus exposition format
  """
  def export(format \\ :prometheus) do
    GenServer.call(__MODULE__, {:export, format})
  end

  @doc """
  Retrieves specific metric values.
  
  ## Examples
      
      Metrics.get(:requests_total)
      Metrics.get(:vsm_variety_absorbed_ratio, %{subsystem: :s3})
  """
  def get(name, labels \\ %{}) do
    GenServer.call(__MODULE__, {:get, name, labels})
  end

  @doc """
  Sets alert thresholds for automatic notifications.
  
  ## Examples
      
      Metrics.set_threshold(:vsm_variety_absorbed_ratio, :min, 0.5)
      Metrics.set_threshold(:algedonic_signals, :max, 0.8, %{type: :pain})
  """
  def set_threshold(metric_name, threshold_type, value, labels \\ %{}) do
    GenServer.call(__MODULE__, {:set_threshold, metric_name, threshold_type, value, labels})
  end

  @doc """
  Returns dashboard data for real-time visualization.
  """
  def dashboard_data do
    GenServer.call(__MODULE__, :dashboard_data)
  end

  # Server Callbacks

  defstruct [
    :ets_table,
    :persistence_table,
    :thresholds,
    :last_persistence,
    :start_time
  ]

  @impl true
  def init(_opts) do
    # Create ETS tables
    ets_table = :ets.new(@ets_table_name, [
      :named_table,
      :public,
      :set,
      {:write_concurrency, true},
      {:read_concurrency, true}
    ])

    persistence_table = :ets.new(@persistence_table, [
      :named_table,
      :public,
      :set
    ])

    # Load persisted metrics if they exist
    load_persisted_metrics()

    # Initialize core metrics
    initialize_core_metrics()

    # Subscribe to system events
    EventBus.subscribe(:circuit_breaker_state_change)
    EventBus.subscribe(:rate_limit_exceeded)
    EventBus.subscribe(:vsm_message)

    # Schedule periodic persistence
    Process.send_after(self(), :persist, @persistence_interval)

    # Attach telemetry handlers
    attach_telemetry_handlers()

    state = %__MODULE__{
      ets_table: ets_table,
      persistence_table: persistence_table,
      thresholds: %{},
      last_persistence: System.system_time(:millisecond),
      start_time: System.system_time(:millisecond)
    }

    # Publish initialization event
    EventBus.publish(:metrics_system_initialized, %{
      tables: [ets_table, persistence_table],
      start_time: state.start_time
    })

    {:ok, state}
  end

  @impl true
  def handle_cast({:counter, name, value, labels}, state) do
    key = {name, :counter, labels}
    timestamp = System.system_time(:millisecond)
    
    # Update or initialize counter
    :ets.update_counter(
      @ets_table_name,
      key,
      {2, value},
      {key, 0, timestamp}
    )

    # Check thresholds
    check_threshold(name, :counter, labels, value, state)

    # Emit telemetry event
    :telemetry.execute(
      [:autonomous_opponent, :metrics, name],
      %{value: value},
      Map.merge(labels, %{type: :counter})
    )

    {:noreply, state}
  end

  def handle_cast({:gauge, name, value, labels}, state) do
    key = {name, :gauge, labels}
    timestamp = System.system_time(:millisecond)
    
    # Store gauge value with timestamp
    :ets.insert(@ets_table_name, {key, value, timestamp})

    # Check thresholds
    check_threshold(name, :gauge, labels, value, state)

    # Emit telemetry event
    :telemetry.execute(
      [:autonomous_opponent, :metrics, name],
      %{value: value},
      Map.merge(labels, %{type: :gauge})
    )

    {:noreply, state}
  end

  def handle_cast({:histogram, name, value, labels}, state) do
    key = {name, :histogram, labels}
    timestamp = System.system_time(:millisecond)
    
    # Get existing samples or initialize
    samples = case :ets.lookup(@ets_table_name, key) do
      [{^key, existing_samples, _}] -> existing_samples
      [] -> []
    end

    # Add new sample with sliding window
    cutoff_time = timestamp - @window_size
    new_samples = [{timestamp, value} | samples]
                  |> Enum.filter(fn {ts, _} -> ts > cutoff_time end)
                  |> Enum.take(1000)  # Limit samples to prevent memory issues

    :ets.insert(@ets_table_name, {key, new_samples, timestamp})

    # Calculate statistics for threshold checking
    values = Enum.map(new_samples, &elem(&1, 1))
    avg = if values != [], do: Enum.sum(values) / length(values), else: 0
    
    check_threshold(name, :histogram, labels, avg, state)

    # Emit telemetry event
    :telemetry.execute(
      [:autonomous_opponent, :metrics, name],
      %{value: value, count: length(values), avg: avg},
      Map.merge(labels, %{type: :histogram})
    )

    {:noreply, state}
  end

  @impl true
  def handle_call({:export, :prometheus}, _from, state) do
    lines = :ets.foldl(
      fn {key, value, timestamp}, acc ->
        case format_prometheus_line(key, value, timestamp) do
          nil -> acc
          line -> [line | acc]
        end
      end,
      [],
      @ets_table_name
    )

    output = lines
             |> Enum.reverse()
             |> Enum.join("\n")

    {:reply, output, state}
  end

  def handle_call({:get, name, labels}, _from, state) do
    # Try each metric type
    result = Enum.find_value([:counter, :gauge, :histogram], fn type ->
      key = {name, type, labels}
      case :ets.lookup(@ets_table_name, key) do
        [{^key, value, _timestamp}] -> {type, value}
        [] -> nil
      end
    end)

    {:reply, result, state}
  end

  def handle_call({:set_threshold, name, threshold_type, value, labels}, _from, state) do
    threshold_key = {name, labels}
    new_thresholds = Map.put(state.thresholds, threshold_key, {threshold_type, value})
    
    {:reply, :ok, %{state | thresholds: new_thresholds}}
  end

  def handle_call(:dashboard_data, _from, state) do
    data = %{
      uptime_ms: System.system_time(:millisecond) - state.start_time,
      metrics_count: :ets.info(@ets_table_name, :size),
      vsm_health: calculate_vsm_health(),
      algedonic_balance: calculate_algedonic_balance(),
      recent_alerts: get_recent_alerts(),
      subsystem_status: get_subsystem_status()
    }

    {:reply, data, state}
  end

  @impl true
  def handle_info(:persist, state) do
    persist_metrics(state)
    Process.send_after(self(), :persist, @persistence_interval)
    {:noreply, %{state | last_persistence: System.system_time(:millisecond)}}
  end

  def handle_info({:event, :circuit_breaker_state_change, data}, state) do
    # Track circuit breaker state changes
    labels = %{
      circuit_breaker: data.name,
      from_state: data.from,
      to_state: data.to
    }
    counter(:circuit_breaker_transitions_total, 1, labels)
    
    # Track current state as gauge
    state_value = case data.to do
      :open -> 2
      :half_open -> 1  
      :closed -> 0
    end
    gauge(:circuit_breaker_state, state_value, %{name: data.name})

    {:noreply, state}
  end

  def handle_info({:event, :rate_limit_exceeded, data}, state) do
    # Track rate limit violations
    labels = %{
      limiter: data.name,
      reason: data.reason || "unknown"
    }
    counter(:rate_limit_violations_total, 1, labels)
    
    # Generate algedonic pain signal for S5
    algedonic(:pain, :medium, %{
      source: :rate_limiter,
      limiter: data.name
    })

    {:noreply, state}
  end

  def handle_info({:event, :vsm_message, data}, state) do
    # Track VSM message flow
    labels = %{
      from: data.from,
      to: data.to,
      message_type: data.type || "unknown"
    }
    counter(:vsm_messages_total, 1, labels)
    
    # Track message latency if available
    if data[:latency_ms] do
      histogram(:vsm_message_latency_ms, data.latency_ms, labels)
    end

    {:noreply, state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  # Private Functions

  defp initialize_core_metrics do
    # Initialize VSM subsystem metrics
    for subsystem <- @vsm_subsystems do
      gauge(:vsm_variety_absorbed_ratio, 0.0, %{subsystem: subsystem})
      gauge(:vsm_variety_generated_ratio, 0.0, %{subsystem: subsystem})
      gauge(:vsm_health_score, 1.0, %{subsystem: subsystem})
    end

    # Initialize algedonic balance
    gauge(:algedonic_balance, 0.0, %{})
    
    # System metrics
    counter(:metrics_recorded_total, 0, %{})
    gauge(:metrics_persistence_lag_ms, 0, %{})
  end

  defp attach_telemetry_handlers do
    # Attach handler for Phoenix metrics
    :telemetry.attach_many(
      "autonomous-opponent-phoenix-metrics",
      [
        [:phoenix, :endpoint, :stop],
        [:phoenix, :router_dispatch, :stop],
        [:phoenix, :live_view, :mount, :stop]
      ],
      &handle_phoenix_telemetry/4,
      nil
    )

    # Attach handler for Ecto metrics
    :telemetry.attach_many(
      "autonomous-opponent-ecto-metrics",
      [
        [:ecto, :query]
      ],
      &handle_ecto_telemetry/4,
      nil
    )
  end

  defp handle_phoenix_telemetry([:phoenix, :endpoint, :stop], measurements, metadata, _config) do
    labels = %{
      method: metadata.conn.method,
      path: metadata.conn.request_path,
      status: metadata.conn.status
    }
    
    histogram(:http_request_duration_ms, measurements.duration / 1_000_000, labels)
    counter(:http_requests_total, 1, labels)
  end

  defp handle_phoenix_telemetry([:phoenix, :router_dispatch, :stop], measurements, metadata, _config) do
    labels = %{
      route: metadata.route,
      plug: inspect(metadata.plug)
    }
    
    histogram(:phoenix_router_dispatch_duration_ms, measurements.duration / 1_000_000, labels)
  end

  defp handle_phoenix_telemetry([:phoenix, :live_view, :mount, :stop], measurements, metadata, _config) do
    labels = %{
      view: inspect(metadata.socket.view)
    }
    
    histogram(:phoenix_live_view_mount_duration_ms, measurements.duration / 1_000_000, labels)
  end

  defp handle_ecto_telemetry([:ecto, :query], measurements, metadata, _config) do
    labels = %{
      source: metadata.source || "unknown",
      repo: inspect(metadata.repo)
    }
    
    histogram(:database_query_duration_ms, measurements.query_time / 1_000_000, labels)
    histogram(:database_queue_duration_ms, measurements.queue_time / 1_000_000, labels)
  end

  defp format_prometheus_line({{name, type, labels}, value, _timestamp}, value, _timestamp) 
       when type == :counter do
    labels_str = format_prometheus_labels(labels)
    "# TYPE #{name} counter\n#{name}#{labels_str} #{value}"
  end

  defp format_prometheus_line({{name, type, labels}, value, _timestamp}, value, _timestamp) 
       when type == :gauge do
    labels_str = format_prometheus_labels(labels)
    "# TYPE #{name} gauge\n#{name}#{labels_str} #{value}"
  end

  defp format_prometheus_line({{name, type, labels}, samples, _timestamp}, samples, _timestamp) 
       when type == :histogram and is_list(samples) do
    values = Enum.map(samples, &elem(&1, 1))
    
    if values == [] do
      nil
    else
      count = length(values)
      sum = Enum.sum(values)
      labels_str = format_prometheus_labels(labels)
      
      buckets = calculate_histogram_buckets(values)
      bucket_lines = Enum.map(buckets, fn {le, count} ->
        "#{name}_bucket#{labels_str |> String.replace("}", ~s(,le="#{le}"}))} #{count}"
      end)
      
      """
      # TYPE #{name} histogram
      #{Enum.join(bucket_lines, "\n")}
      #{name}_sum#{labels_str} #{sum}
      #{name}_count#{labels_str} #{count}
      """ |> String.trim()
    end
  end

  defp format_prometheus_line(_, _, _), do: nil

  defp format_prometheus_labels(labels) when labels == %{}, do: ""
  defp format_prometheus_labels(labels) do
    labels_str = labels
                 |> Enum.map(fn {k, v} -> ~s(#{k}="#{v}") end)
                 |> Enum.join(",")
    
    "{#{labels_str}}"
  end

  defp calculate_histogram_buckets(values) do
    # Standard prometheus buckets
    buckets = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, "+Inf"]
    
    Enum.map(buckets, fn bucket ->
      le_value = if bucket == "+Inf", do: :infinity, else: bucket
      count = Enum.count(values, fn v -> 
        if bucket == "+Inf", do: true, else: v <= bucket
      end)
      
      {bucket, count}
    end)
  end

  defp check_threshold(metric_name, _type, labels, value, state) do
    threshold_key = {metric_name, labels}
    
    case Map.get(state.thresholds, threshold_key) do
      {:min, threshold} when value < threshold ->
        fire_alert(metric_name, labels, value, {:below_min, threshold})
        
      {:max, threshold} when value > threshold ->
        fire_alert(metric_name, labels, value, {:above_max, threshold})
        
      _ ->
        :ok
    end
  end

  defp fire_alert(metric_name, labels, value, {violation_type, threshold}) do
    EventBus.publish(:metric_threshold_violated, %{
      metric: metric_name,
      labels: labels,
      value: value,
      threshold: threshold,
      violation_type: violation_type,
      timestamp: System.system_time(:millisecond)
    })

    # Generate algedonic pain for threshold violations
    severity = case violation_type do
      {:below_min, _} -> :medium
      {:above_max, _} -> :high
    end

    algedonic(:pain, severity, %{
      source: :metrics,
      metric: metric_name,
      violation: violation_type
    })
  end

  defp persist_metrics(state) do
    # Copy current metrics to persistence table
    metrics_snapshot = :ets.tab2list(@ets_table_name)
    
    :ets.insert(@persistence_table, {:snapshot, metrics_snapshot})
    :ets.insert(@persistence_table, {:last_persist, System.system_time(:millisecond)})

    # Update persistence lag metric
    lag = System.system_time(:millisecond) - state.last_persistence
    gauge(:metrics_persistence_lag_ms, lag, %{})

    Logger.debug("Persisted #{length(metrics_snapshot)} metrics")
  end

  defp load_persisted_metrics do
    case :ets.lookup(@persistence_table, :snapshot) do
      [{:snapshot, metrics}] ->
        Enum.each(metrics, fn metric ->
          :ets.insert(@ets_table_name, metric)
        end)
        Logger.info("Loaded #{length(metrics)} persisted metrics")
        
      [] ->
        Logger.debug("No persisted metrics found")
    end
  end

  defp calculate_vsm_health do
    # Calculate overall VSM health based on variety absorption ratios
    healths = for subsystem <- @vsm_subsystems do
      case get(:vsm_variety_absorbed_ratio, %{subsystem: subsystem}) do
        {:gauge, ratio} -> ratio
        _ -> 0.5  # Default to neutral if no data
      end
    end

    if healths == [] do
      0.5
    else
      Enum.sum(healths) / length(healths)
    end
  end

  defp calculate_algedonic_balance do
    # Calculate balance between pain and pleasure signals
    pain_count = case get(:algedonic_signals, %{type: :pain}) do
      {:histogram, samples} -> length(samples)
      _ -> 0
    end

    pleasure_count = case get(:algedonic_signals, %{type: :pleasure}) do
      {:histogram, samples} -> length(samples)  
      _ -> 0
    end

    total = pain_count + pleasure_count
    if total == 0 do
      0.0  # Neutral
    else
      (pleasure_count - pain_count) / total  # Range: -1 (all pain) to 1 (all pleasure)
    end
  end

  defp get_recent_alerts do
    # This would fetch from event bus history in a real implementation
    # For now, return empty list
    []
  end

  defp get_subsystem_status do
    # Get current status of each VSM subsystem
    Map.new(@vsm_subsystems, fn subsystem ->
      variety_absorbed = case get(:vsm_variety_absorbed_ratio, %{subsystem: subsystem}) do
        {:gauge, value} -> value
        _ -> 0.0
      end

      health = case get(:vsm_health_score, %{subsystem: subsystem}) do
        {:gauge, value} -> value  
        _ -> 1.0
      end

      {subsystem, %{
        variety_absorbed: variety_absorbed,
        health_score: health,
        status: determine_status(variety_absorbed, health)
      }}
    end)
  end

  defp determine_status(variety_absorbed, health) do
    cond do
      health < 0.3 -> :critical
      health < 0.6 -> :warning
      variety_absorbed < 0.4 -> :underutilized
      variety_absorbed > 0.9 -> :overloaded
      true -> :healthy
    end
  end
end