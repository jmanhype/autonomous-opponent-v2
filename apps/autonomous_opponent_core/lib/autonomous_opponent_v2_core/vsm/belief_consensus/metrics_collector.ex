defmodule AutonomousOpponentV2Core.VSM.BeliefConsensus.MetricsCollector do
  @moduledoc """
  Collects and analyzes metrics for the belief consensus system.
  
  Implements cybernetic monitoring principles:
  - Tracks variety absorption at each level
  - Monitors consensus convergence velocity
  - Detects oscillation patterns
  - Measures algedonic trigger frequency
  - Calculates system coherence
  
  These metrics feed back into the VSM control loops for
  adaptive belief management.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Core.Metrics
  
  @collection_interval 5_000  # 5 seconds
  @history_window 300        # Keep 5 minutes of history
  
  defstruct [
    :metrics_by_level,
    :system_metrics,
    :history,
    :thresholds,
    :alerts_active
  ]
  
  # Metric thresholds for algedonic triggers
  @thresholds %{
    divergence_pain: 0.8,         # High belief divergence
    oscillation_pain: 5,          # Too many oscillations
    variety_overflow: 0.9,        # Channel capacity exceeded
    coherence_critical: 0.5,      # Low system coherence
    convergence_stall: 30_000     # 30s without convergence
  }
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get current metrics for a specific VSM level.
  """
  def get_level_metrics(level) do
    GenServer.call(__MODULE__, {:get_level_metrics, level})
  end
  
  @doc """
  Get system-wide belief consensus metrics.
  """
  def get_system_metrics do
    GenServer.call(__MODULE__, :get_system_metrics)
  end
  
  @doc """
  Get historical metrics for trend analysis.
  """
  def get_historical_metrics(duration_ms \\ 60_000) do
    GenServer.call(__MODULE__, {:get_historical, duration_ms})
  end
  
  # Server Implementation
  
  @impl true
  def init(_opts) do
    # Subscribe to belief consensus events
    EventBus.subscribe(:belief_consensus_metrics)
    EventBus.subscribe(:belief_proposed)
    EventBus.subscribe(:consensus_achieved)
    EventBus.subscribe(:belief_oscillation)
    EventBus.subscribe(:variety_attenuation)
    EventBus.subscribe(:algedonic_belief_trigger)
    
    # Start collection timer
    schedule_collection()
    
    state = %__MODULE__{
      metrics_by_level: init_level_metrics(),
      system_metrics: init_system_metrics(),
      history: CircularBuffer.new(@history_window),
      thresholds: @thresholds,
      alerts_active: MapSet.new()
    }
    
    Logger.info("📊 Belief Consensus Metrics Collector started")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_level_metrics, level}, _from, state) do
    metrics = Map.get(state.metrics_by_level, level, %{})
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_call(:get_system_metrics, _from, state) do
    {:reply, state.system_metrics, state}
  end
  
  @impl true
  def handle_call({:get_historical, duration_ms}, _from, state) do
    cutoff = System.system_time(:millisecond) - duration_ms
    
    historical = state.history
    |> CircularBuffer.to_list()
    |> Enum.filter(fn entry -> entry.timestamp >= cutoff end)
    
    {:reply, historical, state}
  end
  
  @impl true
  def handle_info(:collect_metrics, state) do
    # Collect metrics from all belief consensus processes
    new_metrics = collect_all_metrics()
    
    # Calculate system-wide metrics
    system_metrics = calculate_system_metrics(new_metrics)
    
    # Check thresholds and trigger algedonics if needed
    new_state = check_metric_thresholds(system_metrics, state)
    
    # Update history
    history_entry = %{
      timestamp: System.system_time(:millisecond),
      level_metrics: new_metrics,
      system_metrics: system_metrics
    }
    
    new_history = CircularBuffer.push(new_state.history, history_entry)
    
    # Publish metrics for other subsystems
    publish_metrics(system_metrics)
    
    # Update Prometheus/Telemetry metrics
    update_telemetry_metrics(system_metrics)
    
    # Schedule next collection
    schedule_collection()
    
    {:noreply, %{new_state | 
      metrics_by_level: new_metrics,
      system_metrics: system_metrics,
      history: new_history
    }}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, event}, state) do
    handle_info({:event, event.type, event.data}, state)
  end
  
  @impl true
  def handle_info({:event, :belief_consensus_metrics, data}, state) do
    # Update level-specific metrics
    level = data.level
    metrics = data.metrics
    
    new_level_metrics = Map.update(
      state.metrics_by_level,
      level,
      metrics,
      fn existing -> Map.merge(existing, metrics) end
    )
    
    {:noreply, %{state | metrics_by_level: new_level_metrics}}
  end
  
  @impl true
  def handle_info({:event, event_type, data}, state) do
    # Track belief system events
    new_state = case event_type do
      :belief_proposed -> 
        increment_counter(state, :beliefs_proposed)
        
      :consensus_achieved ->
        update_convergence_time(state, data)
        
      :belief_oscillation ->
        increment_counter(state, :oscillations_detected)
        
      :variety_attenuation ->
        increment_counter(state, :variety_attenuations)
        
      :algedonic_belief_trigger ->
        increment_counter(state, :algedonic_triggers)
        
      _ ->
        state
    end
    
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp init_level_metrics do
    [:s1, :s2, :s3, :s4, :s5]
    |> Enum.map(fn level -> {level, init_metrics_map()} end)
    |> Map.new()
  end
  
  defp init_system_metrics do
    %{
      total_beliefs: 0,
      consensus_beliefs: 0,
      belief_divergence: 0.0,
      convergence_velocity: 0.0,
      oscillation_rate: 0.0,
      variety_utilization: 0.0,
      coherence_score: 1.0,
      algedonic_frequency: 0.0,
      last_convergence: nil,
      convergence_times: []
    }
  end
  
  defp init_metrics_map do
    %{
      belief_count: 0,
      consensus_size: 0,
      variety_ratio: 0.0,
      oscillation_count: 0,
      algedonic_triggers: 0,
      consensus_quality: 0.0
    }
  end
  
  defp collect_all_metrics do
    [:s1, :s2, :s3, :s4, :s5]
    |> Enum.map(fn level ->
      case AutonomousOpponentV2Core.VSM.BeliefConsensus.get_metrics(level) do
        metrics when is_map(metrics) -> {level, metrics}
        _ -> {level, init_metrics_map()}
      end
    end)
    |> Map.new()
  end
  
  defp calculate_system_metrics(level_metrics) do
    # Aggregate metrics across all levels
    total_beliefs = sum_metric(level_metrics, :belief_count)
    consensus_beliefs = sum_metric(level_metrics, :consensus_size)
    
    # Calculate system-wide indicators
    %{
      total_beliefs: total_beliefs,
      consensus_beliefs: consensus_beliefs,
      belief_divergence: calculate_divergence(level_metrics),
      convergence_velocity: calculate_velocity(level_metrics),
      oscillation_rate: calculate_oscillation_rate(level_metrics),
      variety_utilization: calculate_variety_utilization(level_metrics),
      coherence_score: calculate_coherence(level_metrics),
      algedonic_frequency: calculate_algedonic_frequency(level_metrics)
    }
  end
  
  defp sum_metric(level_metrics, metric_name) do
    level_metrics
    |> Map.values()
    |> Enum.map(&Map.get(&1, metric_name, 0))
    |> Enum.sum()
  end
  
  defp calculate_divergence(level_metrics) do
    # Measure how much beliefs differ across levels
    belief_counts = level_metrics
    |> Map.values()
    |> Enum.map(&Map.get(&1, :belief_count, 0))
    
    consensus_counts = level_metrics
    |> Map.values()
    |> Enum.map(&Map.get(&1, :consensus_size, 0))
    
    if Enum.sum(belief_counts) == 0 do
      0.0
    else
      # Higher divergence = more beliefs not in consensus
      total_beliefs = Enum.sum(belief_counts)
      total_consensus = Enum.sum(consensus_counts)
      
      1.0 - (total_consensus / total_beliefs)
    end
  end
  
  defp calculate_velocity(_level_metrics) do
    # Would track convergence speed over time
    # For now, return a placeholder
    0.5
  end
  
  defp calculate_oscillation_rate(level_metrics) do
    # Sum oscillations across all levels
    total_oscillations = sum_metric(level_metrics, :oscillation_count)
    total_beliefs = sum_metric(level_metrics, :belief_count)
    
    if total_beliefs == 0 do
      0.0
    else
      total_oscillations / total_beliefs
    end
  end
  
  defp calculate_variety_utilization(level_metrics) do
    # Average variety ratio across all levels
    ratios = level_metrics
    |> Map.values()
    |> Enum.map(&Map.get(&1, :variety_ratio, 0.0))
    
    if Enum.empty?(ratios) do
      0.0
    else
      Enum.sum(ratios) / length(ratios)
    end
  end
  
  defp calculate_coherence(level_metrics) do
    # Average consensus quality across all levels
    qualities = level_metrics
    |> Map.values()
    |> Enum.map(&Map.get(&1, :consensus_quality, 0.0))
    
    if Enum.empty?(qualities) do
      1.0
    else
      Enum.sum(qualities) / length(qualities)
    end
  end
  
  defp calculate_algedonic_frequency(level_metrics) do
    # Total algedonic triggers per minute
    total_triggers = sum_metric(level_metrics, :algedonic_triggers)
    
    # Convert to per-minute rate
    total_triggers / 5.0  # Since we collect every 5 seconds
  end
  
  defp check_metric_thresholds(metrics, state) do
    # Check each metric against its threshold
    alerts = []
    
    # High divergence
    if metrics.belief_divergence > @thresholds.divergence_pain do
      alerts = [:high_divergence | alerts]
    end
    
    # Excessive oscillations
    if metrics.oscillation_rate > @thresholds.oscillation_pain do
      alerts = [:excessive_oscillations | alerts]
    end
    
    # Variety overflow
    if metrics.variety_utilization > @thresholds.variety_overflow do
      alerts = [:variety_overflow | alerts]
    end
    
    # Low coherence
    if metrics.coherence_score < @thresholds.coherence_critical do
      alerts = [:low_coherence | alerts]
    end
    
    # Process new alerts
    new_alerts = MapSet.new(alerts)
    alerts_to_trigger = MapSet.difference(new_alerts, state.alerts_active)
    
    # Trigger algedonic signals for new alerts
    Enum.each(alerts_to_trigger, &trigger_algedonic_alert/1)
    
    %{state | alerts_active: new_alerts}
  end
  
  defp trigger_algedonic_alert(alert_type) do
    severity = case alert_type do
      :high_divergence -> 0.85
      :excessive_oscillations -> 0.90
      :variety_overflow -> 0.95
      :low_coherence -> 0.88
    end
    
    Algedonic.report_pain(:belief_consensus_metrics, alert_type, severity)
    
    Logger.warning("🚨 Belief consensus alert: #{alert_type} (severity: #{severity})")
  end
  
  defp publish_metrics(metrics) do
    EventBus.publish(:belief_system_metrics, %{
      metrics: metrics,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp update_telemetry_metrics(metrics) do
    # Emit telemetry events for Prometheus export
    :telemetry.execute(
      [:belief_consensus, :metrics],
      %{
        total_beliefs: metrics.total_beliefs,
        consensus_beliefs: metrics.consensus_beliefs,
        belief_divergence: metrics.belief_divergence,
        convergence_velocity: metrics.convergence_velocity,
        oscillation_rate: metrics.oscillation_rate,
        variety_utilization: metrics.variety_utilization,
        coherence_score: metrics.coherence_score,
        algedonic_frequency: metrics.algedonic_frequency
      },
      %{system: :belief_consensus}
    )
  end
  
  defp increment_counter(state, counter_name) do
    update_in(state.system_metrics[counter_name], fn
      nil -> 1
      count -> count + 1
    end)
  end
  
  defp update_convergence_time(state, data) do
    convergence_time = Map.get(data, :convergence_time_ms, 0)
    
    update_in(state.system_metrics.convergence_times, fn times ->
      # Keep last 10 convergence times
      [convergence_time | Enum.take(times || [], 9)]
    end)
  end
  
  defp schedule_collection do
    Process.send_after(self(), :collect_metrics, @collection_interval)
  end
end

# Simple circular buffer implementation
defmodule CircularBuffer do
  defstruct [:max_size, :buffer]
  
  def new(max_size) do
    %__MODULE__{max_size: max_size, buffer: []}
  end
  
  def push(%__MODULE__{max_size: max, buffer: buffer} = cb, item) do
    new_buffer = [item | buffer] |> Enum.take(max)
    %{cb | buffer: new_buffer}
  end
  
  def to_list(%__MODULE__{buffer: buffer}), do: Enum.reverse(buffer)
end