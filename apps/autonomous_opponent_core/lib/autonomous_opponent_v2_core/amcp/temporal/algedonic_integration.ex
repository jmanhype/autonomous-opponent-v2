defmodule AutonomousOpponentV2Core.AMCP.Temporal.AlgedonicIntegration do
  @moduledoc """
  Temporal integration with Algedonic (pain/pleasure) channels for VSM emergency response.
  
  Implements Beer's algedonic principle through temporal pattern detection:
  - Temporal pain detection: Degradation, cascade, overload patterns
  - Temporal pleasure detection: Optimization, learning, harmony patterns
  - Emergency bypass: Critical temporal patterns trigger immediate system response
  - Adaptive thresholds: Learn optimal pain/pleasure levels from temporal history
  
  This module bridges temporal pattern detection with algedonic signaling to enable
  rapid system-wide responses to temporal threats and opportunities.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.AMCP.Temporal.EventStore
  alias AutonomousOpponentV2Core.AMCP.Temporal.PatternDetector
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: AlgedonicChannel
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.Core.Metrics
  alias AutonomousOpponentV2Core.EventBus
  
  # Temporal pain patterns - threats to system viability
  @temporal_pain_patterns %{
    cascade_failure: %{
      pain_intensity: 0.95,
      urgency: 1.0,
      trigger_conditions: [:error_cascade, :coordination_breakdown],
      response_time_ms: 100,
      bypass_hierarchy: true
    },
    
    temporal_deadlock: %{
      pain_intensity: 0.90,
      urgency: 0.9,
      trigger_conditions: [:control_loop_oscillation, :recursive_instability],
      response_time_ms: 500,
      bypass_hierarchy: true
    },
    
    variety_overload: %{
      pain_intensity: 0.80,
      urgency: 0.8,
      trigger_conditions: [:variety_flood, :algedonic_storm],
      response_time_ms: 1000,
      bypass_hierarchy: false
    },
    
    performance_degradation: %{
      pain_intensity: 0.70,
      urgency: 0.6,
      trigger_conditions: [:rate_burst, :statistical_anomaly],
      response_time_ms: 2000,
      bypass_hierarchy: false
    },
    
    pattern_instability: %{
      pain_intensity: 0.60,
      urgency: 0.5,
      trigger_conditions: [:consciousness_instability, :behavior_anomaly],
      response_time_ms: 5000,
      bypass_hierarchy: false
    }
  }
  
  # Temporal pleasure patterns - system optimization opportunities
  @temporal_pleasure_patterns %{
    learning_acceleration: %{
      pleasure_intensity: 0.85,
      opportunity_value: 0.9,
      trigger_conditions: [:pattern_learning_success, :adaptation_improvement],
      reinforcement_strength: 0.8
    },
    
    coordination_harmony: %{
      pleasure_intensity: 0.75,
      opportunity_value: 0.8,
      trigger_conditions: [:cross_subsystem_sync, :variety_balance],
      reinforcement_strength: 0.7
    },
    
    optimization_success: %{
      pleasure_intensity: 0.70,
      opportunity_value: 0.7,
      trigger_conditions: [:performance_improvement, :efficiency_gain],
      reinforcement_strength: 0.6
    },
    
    stability_achievement: %{
      pleasure_intensity: 0.65,
      opportunity_value: 0.6,
      trigger_conditions: [:oscillation_dampening, :pattern_stabilization],
      reinforcement_strength: 0.5
    }
  }
  
  # Adaptive thresholds for temporal algedonic responses
  @adaptive_thresholds %{
    pain_escalation_rate: 0.1,      # How quickly pain increases
    pleasure_saturation_level: 0.8, # Maximum pleasure before diminishing returns
    emergency_bypass_threshold: 0.85, # Pain level for emergency bypass
    learning_adaptation_rate: 0.05, # How quickly thresholds adapt
    temporal_decay_rate: 0.02       # How quickly algedonic signals decay
  }
  
  defstruct [
    :pain_patterns,
    :pleasure_patterns,
    :adaptive_thresholds,
    :algedonic_history,
    :pattern_correlation_cache,
    :emergency_response_state,
    :learning_state
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Process a temporal pattern for algedonic response.
  """
  def process_temporal_pattern(pattern) do
    GenServer.cast(__MODULE__, {:process_temporal_pattern, pattern})
  end
  
  @doc """
  Get current algedonic state.
  """
  def get_algedonic_state do
    GenServer.call(__MODULE__, :get_algedonic_state)
  end
  
  @doc """
  Update adaptive thresholds based on learning.
  """
  def update_adaptive_thresholds(threshold_updates) do
    GenServer.call(__MODULE__, {:update_adaptive_thresholds, threshold_updates})
  end
  
  @doc """
  Force emergency algedonic response.
  """
  def trigger_emergency_response(emergency_type, context) do
    GenServer.cast(__MODULE__, {:trigger_emergency_response, emergency_type, context})
  end
  
  @doc """
  Get temporal algedonic statistics.
  """
  def get_temporal_stats do
    GenServer.call(__MODULE__, :get_temporal_stats)
  end
  
  # GenServer Callbacks
  
  def init(opts) do
    # Subscribe to temporal pattern events
    EventBus.subscribe(:temporal_pattern_detected)
    EventBus.subscribe(:variety_pattern_detected)
    EventBus.subscribe(:algedonic_signal)
    
    state = %__MODULE__{
      pain_patterns: @temporal_pain_patterns,
      pleasure_patterns: @temporal_pleasure_patterns,
      adaptive_thresholds: Map.merge(@adaptive_thresholds, opts[:custom_thresholds] || %{}),
      algedonic_history: initialize_algedonic_history(),
      pattern_correlation_cache: :ets.new(:temporal_algedonic_cache, [:set, :private]),
      emergency_response_state: initialize_emergency_state(),
      learning_state: initialize_learning_state()
    }
    
    Logger.info("Temporal Algedonic Integration initialized")
    {:ok, state}
  end
  
  def handle_cast({:process_temporal_pattern, pattern}, state) do
    new_state = process_pattern_for_algedonic_response(pattern, state)
    {:noreply, new_state}
  end
  
  def handle_cast({:trigger_emergency_response, emergency_type, context}, state) do
    new_state = execute_emergency_response(emergency_type, context, state)
    {:noreply, new_state}
  end
  
  def handle_call(:get_algedonic_state, _from, state) do
    algedonic_state = %{
      current_pain_level: calculate_current_pain_level(state),
      current_pleasure_level: calculate_current_pleasure_level(state),
      emergency_active: state.emergency_response_state.active,
      adaptive_thresholds: state.adaptive_thresholds,
      recent_patterns: get_recent_algedonic_patterns(state),
      learning_progress: state.learning_state.adaptation_progress
    }
    
    {:reply, algedonic_state, state}
  end
  
  def handle_call({:update_adaptive_thresholds, threshold_updates}, _from, state) do
    new_thresholds = Map.merge(state.adaptive_thresholds, threshold_updates)
    new_state = %{state | adaptive_thresholds: new_thresholds}
    
    Logger.info("Updated temporal algedonic thresholds: #{inspect(threshold_updates)}")
    {:reply, :ok, new_state}
  end
  
  def handle_call(:get_temporal_stats, _from, state) do
    stats = %{
      total_pain_signals: state.algedonic_history.total_pain_signals,
      total_pleasure_signals: state.algedonic_history.total_pleasure_signals,
      emergency_responses: state.emergency_response_state.total_responses,
      average_response_time: calculate_average_response_time(state),
      pattern_correlation_accuracy: state.learning_state.correlation_accuracy,
      adaptive_learning_rate: state.learning_state.current_learning_rate
    }
    
    {:reply, stats, state}
  end
  
  def handle_info({:event_bus_hlc, event}, state) do
    new_state = case event do
      %{type: :temporal_pattern_detected} ->
        process_pattern_for_algedonic_response(event.data, state)
        
      %{type: :variety_pattern_detected} ->
        process_variety_pattern_for_algedonic_response(event.data, state)
        
      %{type: :algedonic_signal} ->
        process_algedonic_feedback(event.data, state)
        
      _ ->
        state
    end
    
    {:noreply, new_state}
  end
  
  # Core Algedonic Processing
  
  defp process_pattern_for_algedonic_response(pattern, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Determine if pattern triggers pain or pleasure
    {algedonic_type, algedonic_response} = classify_pattern_algedonic_impact(pattern, state)
    
    case algedonic_type do
      :pain ->
        new_state = process_temporal_pain(pattern, algedonic_response, state)
        record_pain_response_time(start_time, new_state)
        
      :pleasure ->
        new_state = process_temporal_pleasure(pattern, algedonic_response, state)
        record_pleasure_response_time(start_time, new_state)
        
      :neutral ->
        # Pattern doesn't trigger significant algedonic response
        state
    end
  end
  
  defp process_temporal_pain(pattern, pain_config, state) do
    pain_intensity = calculate_pain_intensity(pattern, pain_config, state)
    urgency = calculate_pain_urgency(pattern, pain_config, state)
    
    # Create algedonic pain signal
    pain_signal = %{
      type: :pain,
      source: :temporal_pattern_detector,
      intensity: pain_intensity,
      urgency: urgency,
      pattern_type: pattern.pattern_type,
      pattern_name: pattern.pattern_name,
      temporal_context: extract_temporal_context(pattern),
      emergency_bypass: should_bypass_hierarchy?(pain_intensity, urgency, pain_config),
      response_required: true,
      timestamp: Clock.now()
    }
    
    # Emit pain signal
    emit_algedonic_signal(pain_signal)
    
    # Update pain history and learning
    new_state = update_pain_history(pain_signal, pattern, state)
    
    # Trigger emergency response if needed
    if pain_signal.emergency_bypass do
      execute_emergency_pain_response(pain_signal, pattern, new_state)
    else
      new_state
    end
  end
  
  defp process_temporal_pleasure(pattern, pleasure_config, state) do
    pleasure_intensity = calculate_pleasure_intensity(pattern, pleasure_config, state)
    opportunity_value = calculate_opportunity_value(pattern, pleasure_config, state)
    
    # Create algedonic pleasure signal
    pleasure_signal = %{
      type: :pleasure,
      source: :temporal_pattern_detector,
      intensity: pleasure_intensity,
      opportunity_value: opportunity_value,
      pattern_type: pattern.pattern_type,
      pattern_name: pattern.pattern_name,
      temporal_context: extract_temporal_context(pattern),
      reinforcement_strength: pleasure_config.reinforcement_strength,
      learning_opportunity: true,
      timestamp: Clock.now()
    }
    
    # Emit pleasure signal
    emit_algedonic_signal(pleasure_signal)
    
    # Update pleasure history and learning
    new_state = update_pleasure_history(pleasure_signal, pattern, state)
    
    # Reinforce successful patterns
    reinforce_successful_temporal_patterns(pleasure_signal, pattern, new_state)
  end
  
  defp classify_pattern_algedonic_impact(pattern, state) do
    pattern_type = pattern.pattern_type
    pattern_name = pattern.pattern_name
    
    # Check for pain patterns
    pain_match = Enum.find(state.pain_patterns, fn {_name, config} ->
      pattern_type in config.trigger_conditions
    end)
    
    if pain_match do
      {_name, pain_config} = pain_match
      {:pain, pain_config}
    else
      # Check for pleasure patterns
      pleasure_match = Enum.find(state.pleasure_patterns, fn {_name, config} ->
        pattern_type in config.trigger_conditions
      end)
      
      if pleasure_match do
        {_name, pleasure_config} = pleasure_match
        {:pleasure, pleasure_config}
      else
        {:neutral, nil}
      end
    end
  end
  
  defp calculate_pain_intensity(pattern, pain_config, state) do
    base_intensity = pain_config.pain_intensity
    
    # Adjust based on pattern severity
    severity_multiplier = case pattern[:severity] do
      :critical -> 1.2
      :high -> 1.1
      :medium -> 1.0
      :low -> 0.9
      _ -> 1.0
    end
    
    # Adjust based on recent pain history (escalation)
    escalation_factor = calculate_pain_escalation_factor(state)
    
    # Adjust based on adaptive learning
    learning_adjustment = calculate_learning_adjustment(pattern, state, :pain)
    
    final_intensity = base_intensity * severity_multiplier * escalation_factor * learning_adjustment
    
    # Clamp to valid range [0.0, 1.0]
    max(0.0, min(1.0, final_intensity))
  end
  
  defp calculate_pleasure_intensity(pattern, pleasure_config, state) do
    base_intensity = pleasure_config.pleasure_intensity
    
    # Adjust based on pattern effectiveness
    effectiveness_multiplier = case pattern[:effectiveness] do
      :excellent -> 1.2
      :good -> 1.1
      :average -> 1.0
      :poor -> 0.8
      _ -> 1.0
    end
    
    # Adjust based on pleasure saturation
    saturation_factor = calculate_pleasure_saturation_factor(state)
    
    # Adjust based on adaptive learning
    learning_adjustment = calculate_learning_adjustment(pattern, state, :pleasure)
    
    final_intensity = base_intensity * effectiveness_multiplier * saturation_factor * learning_adjustment
    
    # Clamp to valid range [0.0, 1.0]
    max(0.0, min(1.0, final_intensity))
  end
  
  defp should_bypass_hierarchy?(pain_intensity, urgency, pain_config) do
    emergency_threshold = pain_config[:emergency_bypass_threshold] || 0.85
    
    (pain_intensity >= emergency_threshold) or 
    (urgency >= 0.9 and pain_config.bypass_hierarchy)
  end
  
  defp execute_emergency_pain_response(pain_signal, pattern, state) do
    # Emergency algedonic bypass - immediate system-wide response
    emergency_response = %{
      type: :emergency_temporal_pain,
      pain_signal: pain_signal,
      pattern: pattern,
      bypass_channels: [:s1, :s2, :s3, :s4, :s5],
      immediate_actions: determine_emergency_actions(pattern),
      timestamp: Clock.now()
    }
    
    # Emit emergency signal to all VSM subsystems
    EventBus.publish(:emergency_algedonic_bypass, emergency_response)
    
    # Update emergency response state
    new_emergency_state = %{
      state.emergency_response_state |
      active: true,
      last_response: emergency_response,
      total_responses: state.emergency_response_state.total_responses + 1
    }
    
    Logger.critical("EMERGENCY TEMPORAL ALGEDONIC RESPONSE: #{pattern.pattern_type} - #{pain_signal.intensity}")
    
    %{state | emergency_response_state: new_emergency_state}
  end
  
  defp reinforce_successful_temporal_patterns(pleasure_signal, pattern, state) do
    # Positive reinforcement for successful temporal patterns
    reinforcement = %{
      type: :temporal_pattern_reinforcement,
      pattern_type: pattern.pattern_type,
      pattern_name: pattern.pattern_name,
      strength: pleasure_signal.reinforcement_strength,
      learning_value: pleasure_signal.opportunity_value,
      timestamp: Clock.now()
    }
    
    # Store in pattern correlation cache for future learning
    :ets.insert(state.pattern_correlation_cache, {
      {pattern.pattern_type, pattern.pattern_name},
      reinforcement
    })
    
    # Emit reinforcement signal
    EventBus.publish(:temporal_pattern_reinforcement, reinforcement)
    
    Logger.info("Reinforced temporal pattern: #{pattern.pattern_type} - strength: #{reinforcement.strength}")
    
    state
  end
  
  # Helper Functions
  
  defp emit_algedonic_signal(signal) do
    # Emit to main algedonic channel
    EventBus.publish(:algedonic_signal, signal)
    
    # Record metrics
    Metrics.counter(__MODULE__, "algedonic_signals.emitted", 1, %{
      type: signal.type,
      source: signal.source
    })
    
    if signal.type == :pain do
      Metrics.histogram(__MODULE__, "pain_intensity", signal.intensity)
      if signal[:emergency_bypass] do
        Metrics.counter(__MODULE__, "emergency_responses", 1)
      end
    else
      Metrics.histogram(__MODULE__, "pleasure_intensity", signal.intensity)
    end
  end
  
  defp extract_temporal_context(pattern) do
    %{
      pattern_duration: pattern[:duration] || pattern[:window_ms],
      event_count: pattern[:event_count],
      affected_subsystems: pattern[:affected_subsystems] || [],
      temporal_window: pattern[:time_window] || pattern[:window_ms],
      sequence_length: pattern[:sequence_length]
    }
  end
  
  defp determine_emergency_actions(pattern) do
    case pattern.pattern_type do
      :error_cascade ->
        [:isolate_failing_subsystems, :activate_backup_channels, :emergency_rate_limiting]
        
      :algedonic_storm ->
        [:dampen_algedonic_sensitivity, :emergency_shutdown_non_critical, :escalate_to_s5]
        
      :variety_overload ->
        [:aggressive_variety_attenuation, :emergency_load_shedding, :activate_circuit_breakers]
        
      :temporal_deadlock ->
        [:break_control_loops, :reset_temporal_windows, :emergency_pattern_reset]
        
      _ ->
        [:general_emergency_response, :escalate_to_human_operator]
    end
  end
  
  # Initialization Functions
  
  defp initialize_algedonic_history do
    %{
      pain_signals: [],
      pleasure_signals: [],
      total_pain_signals: 0,
      total_pleasure_signals: 0,
      last_pain_time: nil,
      last_pleasure_time: nil,
      pain_escalation_rate: 0.0,
      pleasure_saturation_level: 0.0
    }
  end
  
  defp initialize_emergency_state do
    %{
      active: false,
      last_response: nil,
      total_responses: 0,
      last_response_time: nil
    }
  end
  
  defp initialize_learning_state do
    %{
      adaptation_progress: 0.0,
      correlation_accuracy: 0.5,
      current_learning_rate: 0.05,
      pattern_success_rate: %{},
      threshold_adjustments: %{}
    }
  end
  
  # Calculation Functions (simplified implementations)
  
  defp calculate_pain_urgency(pattern, pain_config, _state) do
    base_urgency = pain_config.urgency
    
    # Adjust based on pattern characteristics
    case pattern[:emergency_level] do
      :extreme -> min(1.0, base_urgency * 1.3)
      :critical -> min(1.0, base_urgency * 1.2)
      :high -> min(1.0, base_urgency * 1.1)
      _ -> base_urgency
    end
  end
  
  defp calculate_opportunity_value(pattern, pleasure_config, _state) do
    base_value = pleasure_config.opportunity_value
    
    # Adjust based on pattern learning potential
    learning_multiplier = case pattern[:learning_potential] do
      :high -> 1.2
      :medium -> 1.0
      :low -> 0.8
      _ -> 1.0
    end
    
    min(1.0, base_value * learning_multiplier)
  end
  
  defp execute_emergency_response(emergency_type, context, state) do
    # Execute emergency algedonic response
    emergency_response = %{
      type: emergency_type,
      context: context,
      timestamp: Clock.now()
    }
    
    # Update emergency state
    new_emergency_state = %{
      state.emergency_response_state |
      active: true,
      last_response: emergency_response,
      total_responses: state.emergency_response_state.total_responses + 1
    }
    
    Logger.critical("EMERGENCY ALGEDONIC RESPONSE: #{emergency_type}")
    
    %{state | emergency_response_state: new_emergency_state}
  end

  # Placeholder implementations for complex calculations
  defp calculate_current_pain_level(_state), do: 0.0
  defp calculate_current_pleasure_level(_state), do: 0.0
  defp get_recent_algedonic_patterns(_state), do: []
  defp calculate_average_response_time(_state), do: 0.0
  defp calculate_pain_escalation_factor(_state), do: 1.0
  defp calculate_pleasure_saturation_factor(_state), do: 1.0
  defp calculate_learning_adjustment(_pattern, _state, _type), do: 1.0
  defp update_pain_history(pain_signal, _pattern, state), do: state
  defp update_pleasure_history(pleasure_signal, _pattern, state), do: state
  defp record_pain_response_time(_start_time, state), do: state
  defp record_pleasure_response_time(_start_time, state), do: state
  defp process_variety_pattern_for_algedonic_response(_pattern_data, state), do: state
  defp process_algedonic_feedback(_feedback_data, state), do: state
end