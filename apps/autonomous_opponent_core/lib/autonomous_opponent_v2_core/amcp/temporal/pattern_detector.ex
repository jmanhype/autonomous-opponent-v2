defmodule AutonomousOpponentV2Core.AMCP.Temporal.PatternDetector do
  @moduledoc """
  Advanced temporal pattern detection engine for VSM-aware systems.
  
  Implements sophisticated temporal pattern detection using:
  - Sliding window algorithms
  - Statistical pattern analysis
  - Causal relationship detection
  - VSM variety engineering principles
  - Real-time algedonic signal generation
  
  Patterns Supported:
  - "X events in Y time" (rate patterns)
  - Event sequences with timing constraints
  - Burst detection and anomaly patterns
  - Cross-subsystem correlation patterns
  - Emergent behavior patterns
  """
  
  use GenStage
  require Logger
  
  alias AutonomousOpponentV2Core.AMCP.Temporal.EventStore
  alias AutonomousOpponentV2Core.AMCP.Goldrush.PatternMatcher
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.Core.Metrics
  alias AutonomousOpponentV2Core.EventBus
  
  @vsm_temporal_scales %{
    s1: %{window: 1_000, slide: 100, threshold_multiplier: 1.0},      # 1s window, 100ms slide
    s2: %{window: 10_000, slide: 1_000, threshold_multiplier: 0.8},   # 10s window, 1s slide  
    s3: %{window: 60_000, slide: 5_000, threshold_multiplier: 0.6},   # 1min window, 5s slide
    s4: %{window: 300_000, slide: 30_000, threshold_multiplier: 0.4}, # 5min window, 30s slide
    s5: %{window: 1_800_000, slide: 180_000, threshold_multiplier: 0.2} # 30min window, 3min slide
  }
  
  @default_patterns %{
    rate_burst: %{
      type: :rate_burst,
      threshold: 10,
      window_ms: 5_000,
      cooldown_ms: 30_000
    },
    error_cascade: %{
      type: :error_cascade,
      min_events: 3,
      max_gap_ms: 2_000,
      subsystems: [:s1, :s2, :s3]
    },
    algedonic_storm: %{
      type: :algedonic_storm,
      pain_threshold: 0.8,
      duration_ms: 10_000,
      intensity_escalation: 1.5
    },
    coordination_breakdown: %{
      type: :coordination_breakdown,
      s2_failure_rate: 0.7,
      s1_overload_correlation: true,
      window_ms: 60_000
    },
    consciousness_instability: %{
      type: :consciousness_instability,
      state_changes: 5,
      window_ms: 120_000,
      entropy_threshold: 0.9
    }
  }
  
  defstruct [
    :patterns,
    :active_windows,
    :detection_stats,
    :vsm_subsystem_scales,
    :algedonic_thresholds,
    :pattern_cache
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Register a new temporal pattern for detection.
  """
  def register_pattern(pattern_name, pattern_spec) do
    GenStage.call(__MODULE__, {:register_pattern, pattern_name, pattern_spec})
  end
  
  @doc """
  Remove a pattern from detection.
  """
  def unregister_pattern(pattern_name) do
    GenStage.call(__MODULE__, {:unregister_pattern, pattern_name})
  end
  
  @doc """
  Get current detection statistics.
  """
  def get_detection_stats do
    GenStage.call(__MODULE__, :get_detection_stats)
  end
  
  @doc """
  Manually trigger pattern detection on a set of events.
  """
  def detect_patterns(events) do
    GenStage.call(__MODULE__, {:detect_patterns, events})
  end
  
  @doc """
  Update VSM subsystem temporal scales dynamically.
  """
  def update_vsm_scales(subsystem, scale_config) do
    GenStage.call(__MODULE__, {:update_vsm_scales, subsystem, scale_config})
  end
  
  # GenStage Callbacks
  
  def init(opts) do
    # Initialize pattern detection state
    state = %__MODULE__{
      patterns: Map.merge(@default_patterns, opts[:custom_patterns] || %{}),
      active_windows: %{},
      detection_stats: initialize_stats(),
      vsm_subsystem_scales: @vsm_temporal_scales,
      algedonic_thresholds: opts[:algedonic_thresholds] || default_algedonic_thresholds(),
      pattern_cache: :ets.new(:pattern_detection_cache, [:set, :private])
    }
    
    # Subscribe to EventBus for real-time pattern detection
    EventBus.subscribe(:vsm_all_events)
    EventBus.subscribe(:system_event)
    EventBus.subscribe(:algedonic_signal)
    
    Logger.info("Temporal Pattern Detector initialized with #{map_size(state.patterns)} patterns")
    
    {:producer_consumer, state, opts}
  end
  
  def handle_call({:register_pattern, pattern_name, pattern_spec}, _from, state) do
    validated_pattern = validate_pattern_spec(pattern_spec)
    new_patterns = Map.put(state.patterns, pattern_name, validated_pattern)
    
    Logger.info("Registered temporal pattern: #{pattern_name}")
    {:reply, :ok, [], %{state | patterns: new_patterns}}
  end
  
  def handle_call({:unregister_pattern, pattern_name}, _from, state) do
    new_patterns = Map.delete(state.patterns, pattern_name)
    {:reply, :ok, [], %{state | patterns: new_patterns}}
  end
  
  def handle_call(:get_detection_stats, _from, state) do
    {:reply, state.detection_stats, [], state}
  end
  
  def handle_call({:detect_patterns, events}, _from, state) do
    {detected_patterns, new_state} = perform_pattern_detection(events, state)
    {:reply, detected_patterns, [], new_state}
  end
  
  def handle_call({:update_vsm_scales, subsystem, scale_config}, _from, state) do
    new_scales = Map.put(state.vsm_subsystem_scales, subsystem, scale_config)
    {:reply, :ok, [], %{state | vsm_subsystem_scales: new_scales}}
  end
  
  def handle_events(events, _from, state) do
    # Process incoming events through pattern detection pipeline
    {detected_patterns, new_state} = perform_pattern_detection(events, state)
    
    # Emit detected patterns as new events
    pattern_events = Enum.map(detected_patterns, &create_pattern_event/1)
    
    {:noreply, pattern_events, new_state}
  end
  
  def handle_info({:event_bus_hlc, event}, state) do
    # Real-time single event processing
    {detected_patterns, new_state} = perform_pattern_detection([event], state)
    
    # Emit patterns immediately for real-time response
    Enum.each(detected_patterns, &emit_pattern_detection/1)
    
    {:noreply, [], new_state}
  end
  
  def handle_info(:update_detection_windows, state) do
    # Update sliding windows and trigger periodic detection
    new_state = update_sliding_windows(state)
    {:noreply, [], new_state}
  end
  
  # Core Pattern Detection Logic
  
  defp perform_pattern_detection(events, state) do
    start_time = System.monotonic_time(:microsecond)
    
    detected_patterns = []
    
    # 1. Rate-based pattern detection
    rate_patterns = detect_rate_patterns(events, state)
    detected_patterns = detected_patterns ++ rate_patterns
    
    # 2. Sequence pattern detection
    sequence_patterns = detect_sequence_patterns(events, state)
    detected_patterns = detected_patterns ++ sequence_patterns
    
    # 3. Statistical anomaly detection
    anomaly_patterns = detect_anomaly_patterns(events, state)
    detected_patterns = detected_patterns ++ anomaly_patterns
    
    # 4. Cross-subsystem correlation detection
    correlation_patterns = detect_correlation_patterns(events, state)
    detected_patterns = detected_patterns ++ correlation_patterns
    
    # 5. VSM-specific pattern detection
    vsm_patterns = detect_vsm_patterns(events, state)
    detected_patterns = detected_patterns ++ vsm_patterns
    
    # 6. Algedonic pattern detection
    algedonic_patterns = detect_algedonic_patterns(events, state)
    detected_patterns = detected_patterns ++ algedonic_patterns
    
    # Update detection statistics
    processing_time = System.monotonic_time(:microsecond) - start_time
    new_stats = update_detection_stats(state.detection_stats, detected_patterns, processing_time)
    
    # Record metrics
    Metrics.counter(__MODULE__, "patterns.detected", length(detected_patterns))
    Metrics.histogram(__MODULE__, "detection.processing_time_us", processing_time)
    
    {detected_patterns, %{state | detection_stats: new_stats}}
  end
  
  defp detect_rate_patterns(events, state) do
    Enum.flat_map(state.patterns, fn {pattern_name, pattern_spec} ->
      case pattern_spec.type do
        :rate_burst -> detect_rate_burst(events, pattern_name, pattern_spec, state)
        :rate_threshold -> detect_rate_threshold(events, pattern_name, pattern_spec, state)
        _ -> []
      end
    end)
  end
  
  defp detect_rate_burst(events, pattern_name, pattern_spec, state) do
    window_ms = pattern_spec.window_ms
    threshold = pattern_spec.threshold
    
    case Clock.now() do
      {:ok, current_time} ->
        window_start = current_time.physical - window_ms
        
        # Get events in window
        window_events = EventStore.get_events_in_window(
          %{physical: window_start, logical: 0, node_id: ""},
          current_time,
          []
        )
        
        event_count = length(window_events)
        
        if event_count >= threshold do
          rate = event_count / (window_ms / 1000)
          
          [%{
            pattern_name: pattern_name,
            pattern_type: :rate_burst,
            event_count: event_count,
            rate_per_second: rate,
            window_ms: window_ms,
            threshold: threshold,
            severity: calculate_burst_severity(event_count, threshold),
            timestamp: current_time,
            vsm_impact: assess_vsm_impact(window_events, state)
          }]
        else
          []
        end
        
      {:error, _} -> []
    end
  end
  
  defp detect_sequence_patterns(events, state) do
    Enum.flat_map(state.patterns, fn {pattern_name, pattern_spec} ->
      case pattern_spec.type do
        :error_cascade -> detect_error_cascade(events, pattern_name, pattern_spec, state)
        :state_transition_sequence -> detect_state_sequence(events, pattern_name, pattern_spec, state)
        _ -> []
      end
    end)
  end
  
  defp detect_error_cascade(events, pattern_name, pattern_spec, state) do
    min_events = pattern_spec.min_events
    max_gap_ms = pattern_spec.max_gap_ms
    target_subsystems = pattern_spec.subsystems
    
    # Filter events to target subsystems
    subsystem_events = Enum.filter(events, fn event ->
      event[:subsystem] in target_subsystems and 
      (event[:type] == :error or event[:urgency] && event[:urgency] > 0.7)
    end)
    
    # Look for cascading pattern
    if length(subsystem_events) >= min_events do
      ordered_events = Clock.order_events(subsystem_events)
      
      case find_cascade_sequence(ordered_events, max_gap_ms) do
        nil -> []
        cascade_info ->
          [%{
            pattern_name: pattern_name,
            pattern_type: :error_cascade,
            cascade_events: cascade_info.events,
            cascade_duration: cascade_info.duration,
            affected_subsystems: cascade_info.subsystems,
            severity: calculate_cascade_severity(cascade_info),
            timestamp: Clock.now(),
            algedonic_pain: cascade_info.pain_level
          }]
      end
    else
      []
    end
  end
  
  defp detect_anomaly_patterns(events, state) do
    Enum.flat_map(state.patterns, fn {pattern_name, pattern_spec} ->
      case pattern_spec.type do
        :statistical_anomaly -> detect_statistical_anomaly(events, pattern_name, pattern_spec, state)
        :behavior_anomaly -> detect_behavior_anomaly(events, pattern_name, pattern_spec, state)
        _ -> []
      end
    end)
  end
  
  defp detect_correlation_patterns(events, state) do
    Enum.flat_map(state.patterns, fn {pattern_name, pattern_spec} ->
      case pattern_spec.type do
        :coordination_breakdown -> detect_coordination_breakdown(events, pattern_name, pattern_spec, state)
        :cross_subsystem_correlation -> detect_cross_subsystem_correlation(events, pattern_name, pattern_spec, state)
        _ -> []
      end
    end)
  end
  
  defp detect_vsm_patterns(events, state) do
    Enum.flat_map(state.patterns, fn {pattern_name, pattern_spec} ->
      case pattern_spec.type do
        :variety_overload -> detect_variety_overload(events, pattern_name, pattern_spec, state)
        :control_loop_oscillation -> detect_control_oscillation(events, pattern_name, pattern_spec, state)
        :recursive_instability -> detect_recursive_instability(events, pattern_name, pattern_spec, state)
        _ -> []
      end
    end)
  end
  
  defp detect_algedonic_patterns(events, state) do
    Enum.flat_map(state.patterns, fn {pattern_name, pattern_spec} ->
      case pattern_spec.type do
        :algedonic_storm -> detect_algedonic_storm(events, pattern_name, pattern_spec, state)
        :pain_escalation -> detect_pain_escalation(events, pattern_name, pattern_spec, state)
        :pleasure_saturation -> detect_pleasure_saturation(events, pattern_name, pattern_spec, state)
        _ -> []
      end
    end)
  end
  
  defp detect_algedonic_storm(events, pattern_name, pattern_spec, state) do
    pain_threshold = pattern_spec.pain_threshold
    duration_ms = pattern_spec.duration_ms
    escalation_factor = pattern_spec.intensity_escalation
    
    # Filter algedonic events
    algedonic_events = Enum.filter(events, fn event ->
      event[:type] == :algedonic and 
      event[:valence] != nil and 
      event[:valence] < -pain_threshold
    end)
    
    if length(algedonic_events) >= 3 do
      case analyze_algedonic_escalation(algedonic_events, duration_ms, escalation_factor) do
        nil -> []
        storm_info ->
          [%{
            pattern_name: pattern_name,
            pattern_type: :algedonic_storm,
            pain_events: storm_info.events,
            peak_pain: storm_info.peak_pain,
            duration: storm_info.duration,
            escalation_rate: storm_info.escalation_rate,
            affected_subsystems: storm_info.subsystems,
            emergency_level: storm_info.emergency_level,
            timestamp: Clock.now()
          }]
      end
    else
      []
    end
  end
  
  # Helper Functions
  
  defp validate_pattern_spec(pattern_spec) do
    # Ensure pattern has required fields
    pattern_spec
    |> Map.put_new(:priority, :normal)
    |> Map.put_new(:cooldown_ms, 10_000)
    |> Map.put_new(:max_detections_per_hour, 100)
  end
  
  defp initialize_stats do
    %{
      total_detections: 0,
      detections_by_type: %{},
      avg_processing_time_us: 0,
      last_detection_time: nil,
      patterns_per_minute: 0
    }
  end
  
  defp default_algedonic_thresholds do
    %{
      pain_emergency: 0.9,
      pain_critical: 0.7,
      pain_warning: 0.5,
      pleasure_saturation: 0.8,
      pleasure_optimal: 0.6
    }
  end
  
  defp update_detection_stats(stats, detected_patterns, processing_time) do
    total_detections = stats.total_detections + length(detected_patterns)
    
    detections_by_type = Enum.reduce(detected_patterns, stats.detections_by_type, fn pattern, acc ->
      pattern_type = pattern.pattern_type
      Map.update(acc, pattern_type, 1, &(&1 + 1))
    end)
    
    # Update average processing time (exponential moving average)
    alpha = 0.1
    new_avg_time = if stats.avg_processing_time_us == 0 do
      processing_time
    else
      stats.avg_processing_time_us * (1 - alpha) + processing_time * alpha
    end
    
    %{stats |
      total_detections: total_detections,
      detections_by_type: detections_by_type,
      avg_processing_time_us: new_avg_time,
      last_detection_time: Clock.now()
    }
  end
  
  defp calculate_burst_severity(event_count, threshold) do
    ratio = event_count / threshold
    cond do
      ratio >= 5.0 -> :critical
      ratio >= 3.0 -> :high
      ratio >= 2.0 -> :medium
      ratio >= 1.5 -> :low
      true -> :minimal
    end
  end
  
  defp assess_vsm_impact(events, state) do
    subsystem_counts = Enum.reduce(events, %{}, fn event, acc ->
      subsystem = event[:subsystem] || :unknown
      Map.update(acc, subsystem, 1, &(&1 + 1))
    end)
    
    variety_pressure = Enum.reduce(subsystem_counts, 0, fn {subsystem, count}, acc ->
      scale = state.vsm_subsystem_scales[subsystem]
      if scale do
        acc + (count * scale.threshold_multiplier)
      else
        acc + count
      end
    end)
    
    %{
      affected_subsystems: Map.keys(subsystem_counts),
      variety_pressure: variety_pressure,
      impact_level: categorize_vsm_impact(variety_pressure)
    }
  end
  
  defp categorize_vsm_impact(pressure) when pressure > 100, do: :severe
  defp categorize_vsm_impact(pressure) when pressure > 50, do: :high
  defp categorize_vsm_impact(pressure) when pressure > 20, do: :medium
  defp categorize_vsm_impact(pressure) when pressure > 5, do: :low
  defp categorize_vsm_impact(_), do: :minimal
  
  defp find_cascade_sequence(ordered_events, max_gap_ms) do
    case detect_temporal_cascade(ordered_events, max_gap_ms) do
      [] -> nil
      cascade_events ->
        first_event = hd(cascade_events)
        last_event = List.last(cascade_events)
        
        duration = last_event.timestamp.physical - first_event.timestamp.physical
        
        affected_subsystems = cascade_events
        |> Enum.map(& &1[:subsystem])
        |> Enum.uniq()
        
        pain_level = Enum.reduce(cascade_events, 0, fn event, acc ->
          pain = event[:pain] || event[:urgency] || 0
          acc + pain
        end) / length(cascade_events)
        
        %{
          events: cascade_events,
          duration: duration,
          subsystems: affected_subsystems,
          pain_level: pain_level
        }
    end
  end
  
  defp detect_temporal_cascade([], _max_gap), do: []
  defp detect_temporal_cascade([_single], _max_gap), do: []
  defp detect_temporal_cascade([first, second | rest], max_gap) do
    gap = second.timestamp.physical - first.timestamp.physical
    
    if gap <= max_gap do
      [first | detect_temporal_cascade([second | rest], max_gap)]
    else
      detect_temporal_cascade([second | rest], max_gap)
    end
  end
  
  defp calculate_cascade_severity(%{duration: duration, subsystems: subsystems, pain_level: pain}) do
    # Multi-factor severity calculation
    duration_factor = min(duration / 30_000, 2.0)  # 30s max factor
    subsystem_factor = min(length(subsystems) / 3.0, 2.0)  # 3 subsystems max factor
    pain_factor = min(pain / 0.8, 2.0)  # 0.8 pain max factor
    
    severity_score = (duration_factor + subsystem_factor + pain_factor) / 3.0
    
    cond do
      severity_score >= 1.8 -> :critical
      severity_score >= 1.4 -> :high
      severity_score >= 1.0 -> :medium
      severity_score >= 0.6 -> :low
      true -> :minimal
    end
  end
  
  defp analyze_algedonic_escalation(algedonic_events, duration_ms, escalation_factor) do
    ordered_events = Clock.order_events(algedonic_events)
    
    if length(ordered_events) < 2 do
      nil
    else
      first_event = hd(ordered_events)
      last_event = List.last(ordered_events)
      
      actual_duration = last_event.timestamp.physical - first_event.timestamp.physical
      
      if actual_duration <= duration_ms do
        pain_values = Enum.map(ordered_events, fn event -> abs(event[:valence] || 0) end)
        peak_pain = Enum.max(pain_values)
        avg_pain = Enum.sum(pain_values) / length(pain_values)
        
        # Calculate escalation rate
        initial_pain = hd(pain_values)
        final_pain = List.last(pain_values)
        escalation_rate = if initial_pain > 0, do: final_pain / initial_pain, else: 1.0
        
        # Determine emergency level
        emergency_level = cond do
          peak_pain >= 0.95 and escalation_rate >= escalation_factor -> :extreme
          peak_pain >= 0.85 -> :critical
          peak_pain >= 0.7 -> :high
          true -> :medium
        end
        
        # Get affected subsystems
        affected_subsystems = ordered_events
        |> Enum.map(& &1[:source])
        |> Enum.uniq()
        
        %{
          events: ordered_events,
          peak_pain: peak_pain,
          duration: actual_duration,
          escalation_rate: escalation_rate,
          subsystems: affected_subsystems,
          emergency_level: emergency_level
        }
      else
        nil
      end
    end
  end
  
  defp create_pattern_event(detected_pattern) do
    case Clock.create_event(:pattern_detector, :temporal_pattern_detected, detected_pattern) do
      {:ok, event} -> event
      {:error, _} ->
        %{
          type: :temporal_pattern_detected,
          data: detected_pattern,
          timestamp: Clock.now()
        }
    end
  end
  
  defp emit_pattern_detection(pattern) do
    # Emit to EventBus for immediate system response
    EventBus.publish(:temporal_pattern_detected, pattern)
    
    # Emit algedonic signals for critical patterns
    if pattern[:emergency_level] in [:critical, :extreme] do
      EventBus.publish(:algedonic_signal, %{
        type: :pain,
        source: :temporal_pattern_detector,
        valence: -0.9,
        urgency: 1.0,
        data: pattern
      })
    end
    
    Logger.info("Detected temporal pattern: #{pattern.pattern_type} - #{pattern.pattern_name}")
  end
  
  defp update_sliding_windows(state) do
    # Update sliding windows for VSM subsystems
    # This would be called periodically to maintain temporal windows
    state
  end
  
  # Additional helper functions for other pattern types would go here...
  defp detect_rate_threshold(events, pattern_name, pattern_spec, state) do
    threshold = pattern_spec[:rate_threshold] || 10
    window_ms = pattern_spec[:window_ms] || 5_000
    event_type = pattern_spec[:event_type]
    
    # Filter events by type if specified
    filtered_events = if event_type do
      Enum.filter(events, fn event -> event[:type] == event_type end)
    else
      events
    end
    
    case Clock.now() do
      {:ok, current_time} ->
        window_start = current_time.physical - window_ms
        
        # Count events within window
        window_events = Enum.filter(filtered_events, fn event ->
          event[:timestamp] && event[:timestamp].physical >= window_start
        end)
        
        event_count = length(window_events)
        rate = (event_count / window_ms) * 1000  # Events per second
        
        if event_count >= threshold do
          [%{
            pattern_name: pattern_name,
            pattern_type: :rate_threshold,
            event_count: event_count,
            rate_per_second: rate,
            window_ms: window_ms,
            threshold: threshold,
            event_type: event_type,
            severity: calculate_rate_severity(rate, threshold),
            timestamp: current_time
          }]
        else
          []
        end
        
      {:error, _} -> []
    end
  end
  
  defp calculate_rate_severity(rate, threshold) do
    ratio = rate / (threshold / 5)  # Assuming threshold is for 5 seconds
    cond do
      ratio >= 3.0 -> :critical
      ratio >= 2.0 -> :high
      ratio >= 1.5 -> :medium
      ratio >= 1.2 -> :low
      true -> :minimal
    end
  end
  defp detect_state_sequence(events, pattern_name, pattern_spec, state) do
    sequence = pattern_spec[:sequence] || []
    max_gap_ms = pattern_spec[:max_gap_ms] || 5_000
    subsystem = pattern_spec[:subsystem]
    
    if length(sequence) < 2 do
      []  # Need at least 2 states for a sequence
    else
      # Filter to state change events
      state_events = events
      |> Enum.filter(fn event -> 
        event[:type] == :state_change and
        (subsystem == nil or event[:subsystem] == subsystem)
      end)
      |> Clock.order_events()
      
      # Look for the sequence
      case find_state_sequence(state_events, sequence, max_gap_ms) do
        nil -> []
        sequence_info ->
          [%{
            pattern_name: pattern_name,
            pattern_type: :state_transition_sequence,
            sequence: sequence,
            matched_events: sequence_info.events,
            duration: sequence_info.duration,
            subsystem: subsystem,
            severity: calculate_sequence_severity(sequence_info),
            timestamp: Clock.now()
          }]
      end
    end
  end
  
  defp find_state_sequence(events, target_sequence, max_gap_ms) do
    find_sequence_recursive(events, target_sequence, max_gap_ms, [])
  end
  
  defp find_sequence_recursive([], _remaining_sequence, _max_gap, _matched), do: nil
  defp find_sequence_recursive(_events, [], _max_gap, matched) do
    # Found complete sequence
    first_event = hd(Enum.reverse(matched))
    last_event = hd(matched)
    %{
      events: Enum.reverse(matched),
      duration: last_event.timestamp.physical - first_event.timestamp.physical
    }
  end
  defp find_sequence_recursive([event | rest], [target_state | remaining], max_gap, matched) do
    if event[:new_state] == target_state do
      # Check gap if we have previous matches
      if matched == [] or check_sequence_gap(event, hd(matched), max_gap) do
        find_sequence_recursive(rest, remaining, max_gap, [event | matched])
      else
        # Gap too large, start over
        find_sequence_recursive(rest, [target_state | remaining], max_gap, [])
      end
    else
      # Try next event
      find_sequence_recursive(rest, [target_state | remaining], max_gap, matched)
    end
  end
  
  defp check_sequence_gap(event1, event2, max_gap_ms) do
    abs(event1.timestamp.physical - event2.timestamp.physical) <= max_gap_ms
  end
  
  defp calculate_sequence_severity(%{duration: duration, events: events}) do
    # Severity based on speed of transitions
    transitions_per_second = length(events) / (duration / 1000)
    cond do
      transitions_per_second > 10 -> :critical
      transitions_per_second > 5 -> :high
      transitions_per_second > 2 -> :medium
      transitions_per_second > 1 -> :low
      true -> :minimal
    end
  end
  defp detect_statistical_anomaly(events, pattern_name, pattern_spec, state) do
    metric_field = pattern_spec[:metric_field] || :value
    anomaly_threshold = pattern_spec[:anomaly_threshold] || 3.0  # Standard deviations
    window_ms = pattern_spec[:window_ms] || 60_000  # 1 minute default
    min_samples = pattern_spec[:min_samples] || 10
    
    # Extract metric values from recent events
    metric_values = events
    |> Enum.filter(fn event -> 
      event[metric_field] != nil and is_number(event[metric_field])
    end)
    |> Enum.map(fn event -> event[metric_field] end)
    
    if length(metric_values) >= min_samples do
      # Calculate statistics
      mean = Enum.sum(metric_values) / length(metric_values)
      variance = calculate_variance(metric_values, mean)
      std_dev = :math.sqrt(variance)
      
      # Find anomalies
      anomalies = events
      |> Enum.filter(fn event ->
        value = event[metric_field]
        value != nil and abs(value - mean) > (anomaly_threshold * std_dev)
      end)
      
      if length(anomalies) > 0 do
        [%{
          pattern_name: pattern_name,
          pattern_type: :statistical_anomaly,
          anomaly_count: length(anomalies),
          anomalous_events: anomalies,
          mean: mean,
          std_dev: std_dev,
          threshold: anomaly_threshold,
          metric_field: metric_field,
          severity: calculate_anomaly_severity(anomalies, mean, std_dev),
          timestamp: Clock.now()
        }]
      else
        []
      end
    else
      []
    end
  end
  
  defp calculate_variance(values, mean) do
    sum_squared_diff = values
    |> Enum.map(fn value -> :math.pow(value - mean, 2) end)
    |> Enum.sum()
    
    sum_squared_diff / length(values)
  end
  
  defp calculate_anomaly_severity(anomalies, mean, std_dev) do
    max_deviation = anomalies
    |> Enum.map(fn event -> abs(event[:value] - mean) / std_dev end)
    |> Enum.max()
    
    cond do
      max_deviation > 5.0 -> :critical
      max_deviation > 4.0 -> :high
      max_deviation > 3.5 -> :medium
      max_deviation > 3.0 -> :low
      true -> :minimal
    end
  end
  defp detect_behavior_anomaly(events, pattern_name, pattern_spec, state) do
    behavior_type = pattern_spec[:behavior_type] || :frequency
    baseline_window_ms = pattern_spec[:baseline_window_ms] || 300_000  # 5 minutes
    anomaly_multiplier = pattern_spec[:anomaly_multiplier] || 2.0
    
    case behavior_type do
      :frequency ->
        detect_frequency_anomaly(events, pattern_name, pattern_spec, anomaly_multiplier)
        
      :pattern_break ->
        detect_pattern_break_anomaly(events, pattern_name, pattern_spec, state)
        
      :timing ->
        detect_timing_anomaly(events, pattern_name, pattern_spec)
        
      _ ->
        []
    end
  end
  
  defp detect_frequency_anomaly(events, pattern_name, pattern_spec, multiplier) do
    event_type = pattern_spec[:event_type]
    
    # Group events by time buckets
    bucket_size_ms = pattern_spec[:bucket_size_ms] || 60_000  # 1 minute buckets
    
    buckets = events
    |> Enum.filter(fn event -> 
      event_type == nil or event[:type] == event_type
    end)
    |> Enum.group_by(fn event ->
      div(event[:timestamp].physical, bucket_size_ms)
    end)
    |> Enum.map(fn {_bucket, bucket_events} -> length(bucket_events) end)
    
    if length(buckets) >= 3 do
      avg_frequency = Enum.sum(buckets) / length(buckets)
      
      anomalous_buckets = Enum.filter(buckets, fn count ->
        count > avg_frequency * multiplier or count < avg_frequency / multiplier
      end)
      
      if length(anomalous_buckets) > 0 do
        [%{
          pattern_name: pattern_name,
          pattern_type: :behavior_anomaly,
          behavior_type: :frequency,
          anomaly_count: length(anomalous_buckets),
          average_frequency: avg_frequency,
          anomaly_multiplier: multiplier,
          severity: calculate_frequency_anomaly_severity(anomalous_buckets, avg_frequency),
          timestamp: Clock.now()
        }]
      else
        []
      end
    else
      []
    end
  end
  
  defp calculate_frequency_anomaly_severity(anomalous_buckets, avg_frequency) do
    max_deviation = anomalous_buckets
    |> Enum.map(fn count -> abs(count - avg_frequency) / avg_frequency end)
    |> Enum.max()
    
    cond do
      max_deviation > 5.0 -> :critical
      max_deviation > 3.0 -> :high
      max_deviation > 2.0 -> :medium
      max_deviation > 1.5 -> :low
      true -> :minimal
    end
  end
  
  defp detect_coordination_breakdown(events, pattern_name, pattern_spec, state) do
    s2_failure_rate = pattern_spec[:s2_failure_rate] || 0.7
    s1_overload_correlation = pattern_spec[:s1_overload_correlation] || true
    window_ms = pattern_spec[:window_ms] || 60_000
    
    # Filter S2 coordination events
    s2_events = Enum.filter(events, fn event ->
      event[:subsystem] == :s2 and event[:type] in [:coordination_failure, :sync_error, :anti_oscillation_failure]
    end)
    
    # Filter S1 overload events  
    s1_events = Enum.filter(events, fn event ->
      event[:subsystem] == :s1 and event[:type] in [:overload, :variety_overflow, :operational_failure]
    end)
    
    if length(s2_events) > 0 do
      # Calculate S2 failure rate
      total_s2_events = Enum.filter(events, fn e -> e[:subsystem] == :s2 end) |> length()
      actual_failure_rate = if total_s2_events > 0, do: length(s2_events) / total_s2_events, else: 0
      
      # Check correlation with S1 overload
      correlation_found = s1_overload_correlation and length(s1_events) > 0
      
      if actual_failure_rate >= s2_failure_rate or correlation_found do
        [%{
          pattern_name: pattern_name,
          pattern_type: :coordination_breakdown,
          s2_failure_rate: actual_failure_rate,
          s2_failures: length(s2_events),
          s1_overloads: length(s1_events),
          correlation: correlation_found,
          affected_subsystems: [:s1, :s2],
          severity: calculate_coordination_breakdown_severity(actual_failure_rate, correlation_found),
          timestamp: Clock.now(),
          algedonic_pain: 0.8  # High pain signal for coordination breakdown
        }]
      else
        []
      end
    else
      []
    end
  end
  
  defp calculate_coordination_breakdown_severity(failure_rate, correlation) do
    base_severity = cond do
      failure_rate >= 0.9 -> :critical
      failure_rate >= 0.7 -> :high
      failure_rate >= 0.5 -> :medium
      true -> :low
    end
    
    # Increase severity if S1 overload correlation found
    if correlation and base_severity != :critical do
      increase_severity(base_severity)
    else
      base_severity
    end
  end
  
  defp increase_severity(:low), do: :medium
  defp increase_severity(:medium), do: :high
  defp increase_severity(:high), do: :critical
  defp increase_severity(severity), do: severity
  defp detect_cross_subsystem_correlation(events, pattern_name, pattern_spec, state) do
    correlation_threshold = pattern_spec[:correlation_threshold] || 0.7
    min_events = pattern_spec[:min_events] || 5
    time_lag_ms = pattern_spec[:time_lag_ms] || 5_000
    subsystems = pattern_spec[:subsystems] || [:s1, :s2, :s3, :s4, :s5]
    
    # Group events by subsystem
    subsystem_events = events
    |> Enum.filter(fn event -> event[:subsystem] in subsystems end)
    |> Enum.group_by(fn event -> event[:subsystem] end)
    
    # Find correlations between subsystem pairs
    correlations = for s1 <- subsystems, s2 <- subsystems, s1 < s2 do
      events1 = Map.get(subsystem_events, s1, [])
      events2 = Map.get(subsystem_events, s2, [])
      
      if length(events1) >= min_events and length(events2) >= min_events do
        correlation = calculate_temporal_correlation(events1, events2, time_lag_ms)
        if abs(correlation) >= correlation_threshold do
          %{
            subsystems: [s1, s2],
            correlation: correlation,
            event_count: {length(events1), length(events2)},
            lag_ms: find_optimal_lag(events1, events2, time_lag_ms)
          }
        end
      end
    end
    |> Enum.reject(&is_nil/1)
    
    if length(correlations) > 0 do
      strongest_correlation = Enum.max_by(correlations, fn c -> abs(c.correlation) end)
      
      [%{
        pattern_name: pattern_name,
        pattern_type: :cross_subsystem_correlation,
        correlations: correlations,
        strongest: strongest_correlation,
        total_correlations: length(correlations),
        severity: calculate_correlation_severity(strongest_correlation.correlation),
        timestamp: Clock.now()
      }]
    else
      []
    end
  end
  
  defp calculate_temporal_correlation(events1, events2, max_lag_ms) do
    # Simplified correlation calculation based on event timing
    times1 = Enum.map(events1, fn e -> e[:timestamp].physical end) |> Enum.sort()
    times2 = Enum.map(events2, fn e -> e[:timestamp].physical end) |> Enum.sort()
    
    # Count co-occurrences within time lag
    co_occurrences = Enum.reduce(times1, 0, fn t1, acc ->
      nearby = Enum.count(times2, fn t2 -> abs(t2 - t1) <= max_lag_ms end)
      acc + nearby
    end)
    
    # Normalize by event counts
    max_possible = min(length(times1), length(times2))
    if max_possible > 0 do
      co_occurrences / max_possible
    else
      0.0
    end
  end
  
  defp find_optimal_lag(events1, events2, max_lag_ms) do
    # Find the most common time difference between correlated events
    times1 = Enum.map(events1, fn e -> e[:timestamp].physical end)
    times2 = Enum.map(events2, fn e -> e[:timestamp].physical end)
    
    lags = for t1 <- times1, t2 <- times2, abs(t2 - t1) <= max_lag_ms do
      t2 - t1
    end
    
    if length(lags) > 0 do
      # Return median lag
      sorted_lags = Enum.sort(lags)
      Enum.at(sorted_lags, div(length(sorted_lags), 2))
    else
      0
    end
  end
  
  defp calculate_correlation_severity(correlation) do
    abs_correlation = abs(correlation)
    cond do
      abs_correlation >= 0.95 -> :critical
      abs_correlation >= 0.85 -> :high
      abs_correlation >= 0.75 -> :medium
      true -> :low
    end
  end
  defp detect_variety_overload(events, pattern_name, pattern_spec, state) do
    variety_threshold = pattern_spec[:variety_threshold] || 0.8
    subsystem = pattern_spec[:subsystem] || :s1
    window_ms = pattern_spec[:window_ms] || 10_000
    min_unique_types = pattern_spec[:min_unique_types] || 10
    
    # Filter events for specific subsystem
    subsystem_events = Enum.filter(events, fn event ->
      event[:subsystem] == subsystem
    end)
    
    if length(subsystem_events) > 0 do
      # Calculate variety metrics
      unique_types = subsystem_events
      |> Enum.map(fn e -> e[:type] end)
      |> Enum.uniq()
      |> length()
      
      # Shannon entropy for variety measurement
      type_frequencies = subsystem_events
      |> Enum.group_by(fn e -> e[:type] end)
      |> Enum.map(fn {_type, events} -> length(events) end)
      
      entropy = calculate_shannon_entropy(type_frequencies)
      max_entropy = :math.log(unique_types)
      normalized_variety = if max_entropy > 0, do: entropy / max_entropy, else: 0
      
      # Check VSM scale capacity
      scale = Map.get(state.vsm_subsystem_scales, subsystem)
      capacity_usage = if scale do
        length(subsystem_events) / scale.variety_capacity
      else
        0
      end
      
      if normalized_variety >= variety_threshold or capacity_usage >= 0.9 do
        [%{
          pattern_name: pattern_name,
          pattern_type: :variety_overload,
          subsystem: subsystem,
          variety_score: normalized_variety,
          unique_event_types: unique_types,
          capacity_usage: capacity_usage,
          event_count: length(subsystem_events),
          severity: calculate_variety_overload_severity(normalized_variety, capacity_usage),
          timestamp: Clock.now(),
          vsm_impact: %{
            affected_subsystems: [subsystem],
            variety_pressure: normalized_variety,
            impact_level: :severe
          }
        }]
      else
        []
      end
    else
      []
    end
  end
  
  defp calculate_variety_overload_severity(variety_score, capacity_usage) do
    combined_score = (variety_score + capacity_usage) / 2
    cond do
      combined_score >= 0.95 -> :critical
      combined_score >= 0.85 -> :high  
      combined_score >= 0.75 -> :medium
      combined_score >= 0.65 -> :low
      true -> :minimal
    end
  end
  defp detect_control_oscillation(events, pattern_name, pattern_spec, state) do
    min_oscillations = pattern_spec[:min_oscillations] || 3
    time_window_ms = pattern_spec[:time_window_ms] || 60_000
    amplitude_threshold = pattern_spec[:amplitude_threshold] || 0.3
    subsystem = pattern_spec[:subsystem] || :s3
    
    # Filter control events
    control_events = events
    |> Enum.filter(fn event ->
      event[:subsystem] == subsystem and
      event[:type] in [:control_adjustment, :resource_allocation, :priority_change]
    end)
    |> Clock.order_events()
    
    if length(control_events) >= min_oscillations * 2 do
      # Detect oscillating control values
      oscillations = detect_value_oscillations(control_events, amplitude_threshold)
      
      if length(oscillations) >= min_oscillations do
        first_event = hd(control_events)
        last_event = List.last(control_events)
        duration = last_event.timestamp.physical - first_event.timestamp.physical
        
        [%{
          pattern_name: pattern_name,
          pattern_type: :control_loop_oscillation,
          subsystem: subsystem,
          oscillation_count: length(oscillations),
          frequency: length(oscillations) / (duration / 1000),  # Hz
          amplitude: calculate_average_amplitude(oscillations),
          control_events: control_events,
          severity: calculate_oscillation_severity(oscillations, duration),
          timestamp: Clock.now(),
          stability_threat: :high
        }]
      else
        []
      end
    else
      []
    end
  end
  
  defp detect_value_oscillations(events, amplitude_threshold) do
    # Extract control values and detect oscillations
    values = Enum.map(events, fn e -> e[:control_value] || e[:value] || 0 end)
    
    if length(values) >= 3 do
      # Find peaks and troughs
      {peaks, troughs} = find_peaks_and_troughs(values)
      
      # Verify oscillations have sufficient amplitude
      oscillations = for {peak_idx, peak_val} <- peaks, 
                        {trough_idx, trough_val} <- troughs,
                        abs(peak_idx - trough_idx) == 1,
                        abs(peak_val - trough_val) >= amplitude_threshold do
        %{peak: peak_val, trough: trough_val, amplitude: abs(peak_val - trough_val)}
      end
      
      oscillations
    else
      []
    end
  end
  
  defp find_peaks_and_troughs(values) do
    indexed_values = Enum.with_index(values)
    
    peaks = Enum.filter(indexed_values, fn {val, idx} ->
      prev = if idx > 0, do: Enum.at(values, idx - 1), else: val
      next = if idx < length(values) - 1, do: Enum.at(values, idx + 1), else: val
      val > prev and val > next
    end)
    
    troughs = Enum.filter(indexed_values, fn {val, idx} ->
      prev = if idx > 0, do: Enum.at(values, idx - 1), else: val  
      next = if idx < length(values) - 1, do: Enum.at(values, idx + 1), else: val
      val < prev and val < next
    end)
    
    {peaks, troughs}
  end
  
  defp calculate_average_amplitude(oscillations) do
    if length(oscillations) > 0 do
      total = Enum.reduce(oscillations, 0, fn osc, acc -> acc + osc.amplitude end)
      total / length(oscillations)
    else
      0
    end
  end
  
  defp calculate_oscillation_severity(oscillations, duration) do
    frequency = length(oscillations) / (duration / 1000)
    avg_amplitude = calculate_average_amplitude(oscillations)
    
    # High frequency + high amplitude = critical
    severity_score = frequency * avg_amplitude
    
    cond do
      severity_score >= 2.0 -> :critical
      severity_score >= 1.0 -> :high
      severity_score >= 0.5 -> :medium
      severity_score >= 0.2 -> :low
      true -> :minimal
    end
  end
  defp detect_recursive_instability(events, pattern_name, pattern_spec, state) do
    recursion_depth = pattern_spec[:recursion_depth] || 3
    feedback_threshold = pattern_spec[:feedback_threshold] || 0.7
    time_window_ms = pattern_spec[:time_window_ms] || 30_000
    
    # Look for self-referential event chains
    recursive_chains = detect_recursive_event_chains(events, recursion_depth)
    
    if length(recursive_chains) > 0 do
      # Analyze feedback loops
      feedback_strength = calculate_feedback_strength(recursive_chains, events)
      
      if feedback_strength >= feedback_threshold do
        affected_subsystems = recursive_chains
        |> Enum.flat_map(fn chain -> Enum.map(chain, fn e -> e[:subsystem] end) end)
        |> Enum.uniq()
        
        [%{
          pattern_name: pattern_name,
          pattern_type: :recursive_instability,
          recursive_chains: recursive_chains,
          feedback_strength: feedback_strength,
          recursion_depth: Enum.map(recursive_chains, &length/1) |> Enum.max(),
          affected_subsystems: affected_subsystems,
          severity: calculate_recursive_instability_severity(feedback_strength, recursive_chains),
          timestamp: Clock.now(),
          emergency_level: :high
        }]
      else
        []
      end
    else
      []
    end
  end
  
  defp detect_recursive_event_chains(events, max_depth) do
    # Group events by causal relationships
    events_by_id = Enum.reduce(events, %{}, fn event, acc ->
      if event[:event_id], do: Map.put(acc, event[:event_id], event), else: acc
    end)
    
    # Find chains where events trigger themselves (directly or indirectly)
    Enum.reduce(events, [], fn event, chains ->
      if event[:caused_by] do
        chain = trace_causal_chain(event, events_by_id, max_depth, [])
        if length(chain) >= 2 and has_recursion?(chain) do
          [chain | chains]
        else
          chains
        end
      else
        chains
      end
    end)
  end
  
  defp trace_causal_chain(event, events_by_id, remaining_depth, chain) do
    if remaining_depth <= 0 or event[:event_id] in Enum.map(chain, & &1[:event_id]) do
      [event | chain]  # Found recursion or hit depth limit
    else
      new_chain = [event | chain]
      
      case event[:caused_by] do
        nil -> new_chain
        cause_id ->
          case Map.get(events_by_id, cause_id) do
            nil -> new_chain
            cause_event -> trace_causal_chain(cause_event, events_by_id, remaining_depth - 1, new_chain)
          end
      end
    end
  end
  
  defp has_recursion?(chain) do
    event_ids = Enum.map(chain, & &1[:event_id])
    length(event_ids) != length(Enum.uniq(event_ids))
  end
  
  defp calculate_feedback_strength(recursive_chains, all_events) do
    # Measure how strongly the recursive events amplify
    chain_strengths = Enum.map(recursive_chains, fn chain ->
      if length(chain) >= 2 do
        # Compare first and last event intensities
        first = hd(Enum.reverse(chain))
        last = hd(chain)
        
        first_intensity = first[:intensity] || first[:value] || 1.0
        last_intensity = last[:intensity] || last[:value] || 1.0
        
        if first_intensity > 0 do
          last_intensity / first_intensity
        else
          1.0
        end
      else
        1.0
      end
    end)
    
    if length(chain_strengths) > 0 do
      Enum.sum(chain_strengths) / length(chain_strengths)
    else
      0.0
    end
  end
  
  defp calculate_recursive_instability_severity(feedback_strength, chains) do
    max_depth = Enum.map(chains, &length/1) |> Enum.max()
    
    severity_score = feedback_strength * :math.sqrt(max_depth)
    
    cond do
      severity_score >= 3.0 -> :critical
      severity_score >= 2.0 -> :high
      severity_score >= 1.5 -> :medium
      severity_score >= 1.0 -> :low
      true -> :minimal
    end
  end
  defp detect_pain_escalation(events, pattern_name, pattern_spec, state) do
    escalation_rate = pattern_spec[:escalation_rate] || 0.1
    min_pain_events = pattern_spec[:min_pain_events] || 3
    time_window_ms = pattern_spec[:time_window_ms] || 10_000
    
    # Filter pain events
    pain_events = events
    |> Enum.filter(fn event ->
      event[:type] == :algedonic and event[:valence] != nil and event[:valence] < 0
    end)
    |> Clock.order_events()
    
    if length(pain_events) >= min_pain_events do
      # Check for escalating pain pattern
      escalation_info = analyze_pain_escalation(pain_events)
      
      if escalation_info.escalation_rate >= escalation_rate do
        [%{
          pattern_name: pattern_name,
          pattern_type: :pain_escalation,
          pain_events: pain_events,
          escalation_rate: escalation_info.escalation_rate,
          peak_pain: escalation_info.peak_pain,
          duration: escalation_info.duration,
          affected_subsystems: extract_affected_subsystems(pain_events),
          severity: calculate_pain_escalation_severity(escalation_info),
          timestamp: Clock.now(),
          emergency_level: if(escalation_info.peak_pain >= 0.9, do: :extreme, else: :high)
        }]
      else
        []
      end
    else
      []
    end
  end
  
  defp analyze_pain_escalation(pain_events) do
    pain_values = Enum.map(pain_events, fn e -> abs(e[:valence]) end)
    
    # Calculate escalation rate using linear regression
    indices = Enum.to_list(0..(length(pain_values) - 1))
    escalation_rate = calculate_linear_trend(indices, pain_values)
    
    first_event = hd(pain_events)
    last_event = List.last(pain_events)
    duration = last_event.timestamp.physical - first_event.timestamp.physical
    
    %{
      escalation_rate: escalation_rate,
      peak_pain: Enum.max(pain_values),
      duration: duration,
      initial_pain: hd(pain_values),
      final_pain: List.last(pain_values)
    }
  end
  
  defp calculate_linear_trend(x_values, y_values) do
    n = length(x_values)
    
    if n < 2 do
      0.0
    else
      sum_x = Enum.sum(x_values)
      sum_y = Enum.sum(y_values)
      sum_xy = Enum.zip(x_values, y_values) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
      sum_x2 = Enum.map(x_values, fn x -> x * x end) |> Enum.sum()
      
      # Calculate slope (escalation rate)
      numerator = (n * sum_xy) - (sum_x * sum_y)
      denominator = (n * sum_x2) - (sum_x * sum_x)
      
      if denominator != 0 do
        numerator / denominator
      else
        0.0
      end
    end
  end
  
  defp extract_affected_subsystems(events) do
    events
    |> Enum.map(fn e -> e[:source] || e[:subsystem] end)
    |> Enum.filter(& &1)
    |> Enum.uniq()
  end
  
  defp calculate_pain_escalation_severity(escalation_info) do
    # Combine peak pain and escalation rate
    severity_score = escalation_info.peak_pain + (escalation_info.escalation_rate * 2)
    
    cond do
      severity_score >= 1.5 -> :critical
      severity_score >= 1.2 -> :high
      severity_score >= 0.9 -> :medium
      severity_score >= 0.6 -> :low
      true -> :minimal
    end
  end
  defp detect_pleasure_saturation(events, pattern_name, pattern_spec, state) do
    saturation_level = pattern_spec[:saturation_level] || 0.8
    min_pleasure_events = pattern_spec[:min_pleasure_events] || 5
    diminishing_returns_threshold = pattern_spec[:diminishing_returns_threshold] || 0.1
    
    # Filter pleasure events
    pleasure_events = events
    |> Enum.filter(fn event ->
      event[:type] == :algedonic and event[:valence] != nil and event[:valence] > 0
    end)
    |> Clock.order_events()
    
    if length(pleasure_events) >= min_pleasure_events do
      # Analyze pleasure saturation
      saturation_info = analyze_pleasure_saturation(pleasure_events)
      
      if saturation_info.saturation_score >= saturation_level do
        [%{
          pattern_name: pattern_name,
          pattern_type: :pleasure_saturation,
          pleasure_events: pleasure_events,
          saturation_score: saturation_info.saturation_score,
          diminishing_returns_rate: saturation_info.diminishing_returns,
          peak_pleasure: saturation_info.peak_pleasure,
          duration: saturation_info.duration,
          learning_opportunities: identify_learning_opportunities(pleasure_events),
          severity: :low,  # Pleasure saturation is not a threat
          timestamp: Clock.now()
        }]
      else
        []
      end
    else
      []
    end
  end
  
  defp analyze_pleasure_saturation(pleasure_events) do
    pleasure_values = Enum.map(pleasure_events, fn e -> e[:valence] end)
    
    # Calculate saturation metrics
    peak_pleasure = Enum.max(pleasure_values)
    avg_pleasure = Enum.sum(pleasure_values) / length(pleasure_values)
    
    # Measure diminishing returns
    returns = calculate_diminishing_returns(pleasure_values)
    
    first_event = hd(pleasure_events)
    last_event = List.last(pleasure_events)
    duration = last_event.timestamp.physical - first_event.timestamp.physical
    
    # Saturation score combines high average with diminishing returns
    saturation_score = avg_pleasure * (1 - returns)
    
    %{
      saturation_score: saturation_score,
      diminishing_returns: returns,
      peak_pleasure: peak_pleasure,
      avg_pleasure: avg_pleasure,
      duration: duration
    }
  end
  
  defp calculate_diminishing_returns(values) do
    if length(values) < 2 do
      0.0
    else
      # Calculate rate of change between consecutive values
      changes = values
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)
      
      # Measure how much the rate of improvement is declining
      if length(changes) >= 2 do
        # Compare early vs late improvements
        early_changes = Enum.take(changes, div(length(changes), 2))
        late_changes = Enum.drop(changes, div(length(changes), 2))
        
        avg_early = if length(early_changes) > 0, do: Enum.sum(early_changes) / length(early_changes), else: 0
        avg_late = if length(late_changes) > 0, do: Enum.sum(late_changes) / length(late_changes), else: 0
        
        if avg_early > 0 do
          max(0, 1 - (avg_late / avg_early))
        else
          0.0
        end
      else
        0.0
      end
    end
  end
  
  defp identify_learning_opportunities(pleasure_events) do
    # Extract patterns that led to pleasure for reinforcement learning
    pleasure_events
    |> Enum.map(fn event ->
      %{
        trigger: event[:trigger] || event[:caused_by],
        context: event[:context],
        subsystem: event[:subsystem],
        valence: event[:valence]
      }
    end)
    |> Enum.uniq_by(fn opp -> {opp.trigger, opp.subsystem} end)
  end
  
  defp calculate_shannon_entropy(frequencies) do
    total = Enum.sum(frequencies)
    
    if total == 0 do
      0
    else
      frequencies
      |> Enum.map(fn freq ->
        p = freq / total
        if p > 0, do: -p * :math.log(p), else: 0
      end)
      |> Enum.sum()
    end
  end
  
  defp detect_pattern_break_anomaly(events, pattern_name, pattern_spec, state) do
    # Detect when an established pattern suddenly stops occurring
    expected_pattern = pattern_spec[:expected_pattern] || :unknown
    min_occurrences = pattern_spec[:min_occurrences] || 5
    break_threshold_ms = pattern_spec[:break_threshold_ms] || 30_000
    
    # Get historical pattern data from state
    pattern_history = Map.get(state.pattern_history, expected_pattern, [])
    
    if length(pattern_history) >= min_occurrences do
      # Calculate average interval between pattern occurrences
      intervals = pattern_history
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> 
        case {a[:timestamp], b[:timestamp]} do
          {%{physical: t1}, %{physical: t2}} -> abs(t2 - t1)
          _ -> 0
        end
      end)
      |> Enum.filter(&(&1 > 0))
      
      if length(intervals) > 0 do
        avg_interval = Enum.sum(intervals) / length(intervals)
        expected_interval = avg_interval * 1.5  # Allow 50% variance
        
        # Check if pattern hasn't occurred recently
        case {Clock.now(), List.first(pattern_history)} do
          {{:ok, current_time}, %{timestamp: last_occurrence}} ->
            time_since_last = current_time.physical - last_occurrence.physical
            
            if time_since_last > max(expected_interval, break_threshold_ms) do
              [%{
                pattern_type: :pattern_break_anomaly,
                pattern_name: pattern_name,
                expected_pattern: expected_pattern,
                average_interval_ms: round(avg_interval),
                time_since_last_ms: time_since_last,
                break_severity: calculate_break_severity(time_since_last, avg_interval),
                historical_occurrences: length(pattern_history),
                timestamp: current_time
              }]
            else
              []
            end
            
          _ -> []
        end
      else
        []
      end
    else
      []
    end
  end
  
  defp calculate_break_severity(time_since_last, avg_interval) do
    ratio = time_since_last / avg_interval
    cond do
      ratio >= 10.0 -> :critical
      ratio >= 5.0 -> :high
      ratio >= 3.0 -> :medium
      ratio >= 2.0 -> :low
      true -> :minimal
    end
  end
  
  defp detect_timing_anomaly(events, pattern_name, pattern_spec) do
    # Detect when event timing deviates from expected patterns
    event_type = pattern_spec[:event_type] || :any
    expected_interval_ms = pattern_spec[:expected_interval_ms] || 1_000
    tolerance_percent = pattern_spec[:tolerance_percent] || 20
    min_events = pattern_spec[:min_events] || 3
    
    # Filter relevant events
    filtered_events = if event_type == :any do
      events
    else
      Enum.filter(events, fn event -> event[:type] == event_type end)
    end
    
    if length(filtered_events) >= min_events do
      # Order events by timestamp
      ordered_events = Clock.order_events(filtered_events)
      
      # Calculate intervals between consecutive events
      timing_anomalies = ordered_events
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] ->
        case {a[:timestamp], b[:timestamp]} do
          {%{physical: t1}, %{physical: t2}} ->
            interval = t2 - t1
            deviation = abs(interval - expected_interval_ms)
            deviation_percent = (deviation / expected_interval_ms) * 100
            
            if deviation_percent > tolerance_percent do
              %{
                pattern_type: :timing_anomaly,
                pattern_name: pattern_name,
                event_type: event_type,
                expected_interval_ms: expected_interval_ms,
                actual_interval_ms: interval,
                deviation_percent: round(deviation_percent),
                anomaly_type: categorize_timing_anomaly(interval, expected_interval_ms),
                events: [a, b],
                timestamp: b[:timestamp]
              }
            else
              nil
            end
            
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      
      timing_anomalies
    else
      []
    end
  end
  
  defp categorize_timing_anomaly(actual, expected) do
    ratio = actual / expected
    cond do
      ratio < 0.5 -> :too_fast
      ratio > 2.0 -> :too_slow
      ratio < 0.8 -> :slightly_fast
      ratio > 1.2 -> :slightly_slow
      true -> :normal
    end
  end
end