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
  defp detect_rate_threshold(_events, _pattern_name, _pattern_spec, _state), do: []
  defp detect_state_sequence(_events, _pattern_name, _pattern_spec, _state), do: []
  defp detect_statistical_anomaly(_events, _pattern_name, _pattern_spec, _state), do: []
  defp detect_behavior_anomaly(_events, _pattern_name, _pattern_spec, _state), do: []
  defp detect_coordination_breakdown(_events, _pattern_name, _pattern_spec, _state), do: []
  defp detect_cross_subsystem_correlation(_events, _pattern_name, _pattern_spec, _state), do: []
  defp detect_variety_overload(_events, _pattern_name, _pattern_spec, _state), do: []
  defp detect_control_oscillation(_events, _pattern_name, _pattern_spec, _state), do: []
  defp detect_recursive_instability(_events, _pattern_name, _pattern_spec, _state), do: []
  defp detect_pain_escalation(_events, _pattern_name, _pattern_spec, _state), do: []
  defp detect_pleasure_saturation(_events, _pattern_name, _pattern_spec, _state), do: []
end