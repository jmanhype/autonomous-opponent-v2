defmodule AutonomousOpponentV2Core.VSM.Channels.TemporalVarietyChannel do
  @moduledoc """
  Temporal Variety Channel implementing Beer's variety engineering principles for time-based patterns.
  
  This channel manages temporal variety through:
  - Temporal attenuation: Reducing variety overload through pattern grouping
  - Temporal amplification: Enhancing important temporal signals
  - Variety memory: Learning from historical patterns for future attenuation
  - Recursive temporal scaling: Operating at appropriate time scales for each VSM subsystem
  
  Implements Ashby's Law of Requisite Variety through temporal pattern management.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.AMCP.Temporal.EventStore
  alias AutonomousOpponentV2Core.AMCP.Temporal.PatternDetector
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  alias AutonomousOpponentV2Core.Core.Metrics
  alias AutonomousOpponentV2Core.EventBus
  
  # VSM Temporal Scales - Beer's recursive principle applied to time
  @vsm_temporal_scales %{
    s1: %{
      operational_window: 100,      # 100ms - operational response
      pattern_window: 1_000,       # 1s - operational patterns
      learning_window: 60_000,     # 1min - operational learning
      variety_capacity: 1000,      # Events per window
      attenuation_threshold: 0.8   # When to start variety reduction
    },
    s2: %{
      coordination_window: 1_000,   # 1s - coordination cycles  
      pattern_window: 60_000,      # 1min - coordination patterns
      learning_window: 3_600_000,  # 1hour - coordination learning
      variety_capacity: 500,
      attenuation_threshold: 0.7
    },
    s3: %{
      control_window: 5_000,       # 5s - control decisions
      pattern_window: 300_000,     # 5min - control patterns  
      learning_window: 86_400_000, # 1day - control learning
      variety_capacity: 200,
      attenuation_threshold: 0.6
    },
    s4: %{
      intelligence_window: 60_000,  # 1min - intelligence analysis
      pattern_window: 3_600_000,   # 1hour - intelligence patterns
      learning_window: 604_800_000, # 1week - intelligence learning
      variety_capacity: 100,
      attenuation_threshold: 0.5
    },
    s5: %{
      policy_window: 3_600_000,    # 1hour - policy evaluation
      pattern_window: 86_400_000,  # 1day - policy patterns
      learning_window: 2_592_000_000, # 1month - policy learning
      variety_capacity: 50,
      attenuation_threshold: 0.4
    }
  }
  
  @temporal_variety_patterns %{
    # Variety overload patterns
    variety_flood: %{
      type: :variety_overload,
      threshold_multiplier: 2.0,
      duration_ms: 5_000,
      attenuation_response: :aggressive
    },
    
    # Temporal oscillation patterns  
    variety_oscillation: %{
      type: :temporal_oscillation,
      frequency_threshold: 3,  # cycles per minute
      amplitude_threshold: 0.5,
      stability_threat: :high
    },
    
    # Variety starvation patterns
    variety_drought: %{
      type: :variety_starvation,
      minimum_variety: 0.1,
      duration_ms: 30_000,
      amplification_response: :boost
    },
    
    # Cross-subsystem variety interference
    variety_interference: %{
      type: :cross_subsystem_interference,
      correlation_threshold: 0.8,
      interference_level: :critical
    }
  }
  
  defstruct [
    :subsystem,
    :temporal_buffers,
    :variety_memory,
    :attenuation_rules,
    :amplification_rules,
    :learning_state,
    :pattern_cache,
    :variety_flow_history
  ]
  
  # Client API
  
  def start_link(opts) do
    subsystem = Keyword.fetch!(opts, :subsystem)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(subsystem))
  end
  
  @doc """
  Process temporal variety through the channel.
  """
  def process_variety(subsystem, variety_data) do
    GenServer.cast(via_tuple(subsystem), {:process_variety, variety_data})
  end
  
  @doc """
  Get current temporal variety state.
  """
  def get_variety_state(subsystem) do
    GenServer.call(via_tuple(subsystem), :get_variety_state)
  end
  
  @doc """
  Update attenuation rules for temporal variety management.
  """
  def update_attenuation_rules(subsystem, rules) do
    GenServer.call(via_tuple(subsystem), {:update_attenuation_rules, rules})
  end
  
  @doc """
  Update amplification rules for temporal variety enhancement.
  """
  def update_amplification_rules(subsystem, rules) do
    GenServer.call(via_tuple(subsystem), {:update_amplification_rules, rules})
  end
  
  @doc """
  Force variety learning update.
  """
  def update_variety_learning(subsystem) do
    GenServer.cast(via_tuple(subsystem), :update_variety_learning)
  end
  
  # GenServer Callbacks
  
  def init(opts) do
    subsystem = Keyword.fetch!(opts, :subsystem)
    scale_config = Map.get(@vsm_temporal_scales, subsystem, @vsm_temporal_scales.s1)
    
    # Initialize ETS table for temporal buffers
    buffer_table = :ets.new(:"temporal_variety_#{subsystem}", [
      :ordered_set, :private, {:write_concurrency, true}
    ])
    
    # Initialize pattern cache
    pattern_cache = :ets.new(:"variety_patterns_#{subsystem}", [
      :set, :private
    ])
    
    state = %__MODULE__{
      subsystem: subsystem,
      temporal_buffers: %{
        operational: create_temporal_buffer(buffer_table, get_operational_window(subsystem, scale_config)),
        pattern: create_temporal_buffer(buffer_table, scale_config.pattern_window),
        learning: create_temporal_buffer(buffer_table, scale_config.learning_window)
      },
      variety_memory: initialize_variety_memory(subsystem),
      attenuation_rules: initialize_attenuation_rules(scale_config),
      amplification_rules: initialize_amplification_rules(scale_config),
      learning_state: initialize_learning_state(),
      pattern_cache: pattern_cache,
      variety_flow_history: :queue.new()
    }
    
    # Subscribe to relevant events for this subsystem
    EventBus.subscribe(:"vsm_#{subsystem}_event")
    EventBus.subscribe(:temporal_pattern_detected)
    EventBus.subscribe(:variety_pressure_change)
    
    # Register temporal patterns for this subsystem
    register_subsystem_patterns(subsystem)
    
    Logger.info("Temporal Variety Channel initialized for #{subsystem}")
    {:ok, state}
  end
  
  def handle_cast({:process_variety, variety_data}, state) do
    # Apply Beer's variety engineering principles
    processed_state = variety_data
    |> assess_variety_pressure(state)
    |> apply_temporal_attenuation(state)
    |> apply_temporal_amplification(state)
    |> update_variety_memory(state)
    |> detect_variety_patterns(state)
    
    # Update temporal buffers
    new_state = update_temporal_buffers(processed_state, variety_data, state)
    
    # Emit variety flow metrics
    emit_variety_metrics(new_state)
    
    {:noreply, new_state}
  end
  
  def handle_cast(:update_variety_learning, state) do
    new_state = perform_variety_learning(state)
    {:noreply, new_state}
  end
  
  def handle_call(:get_variety_state, _from, state) do
    variety_state = %{
      subsystem: state.subsystem,
      current_variety_pressure: calculate_current_variety_pressure(state),
      attenuation_active: attenuation_active?(state),
      amplification_active: amplification_active?(state),
      learning_progress: state.learning_state.progress,
      temporal_windows: get_temporal_window_status(state),
      variety_flow_rate: calculate_variety_flow_rate(state)
    }
    
    {:reply, variety_state, state}
  end
  
  def handle_call({:update_attenuation_rules, rules}, _from, state) do
    new_attenuation_rules = Map.merge(state.attenuation_rules, rules)
    new_state = %{state | attenuation_rules: new_attenuation_rules}
    
    Logger.info("Updated attenuation rules for #{state.subsystem}: #{inspect(rules)}")
    {:reply, :ok, new_state}
  end
  
  def handle_call({:update_amplification_rules, rules}, _from, state) do
    new_amplification_rules = Map.merge(state.amplification_rules, rules)
    new_state = %{state | amplification_rules: new_amplification_rules}
    
    Logger.info("Updated amplification rules for #{state.subsystem}: #{inspect(rules)}")
    {:reply, :ok, new_state}
  end
  
  def handle_info({:event_bus_hlc, event}, state) do
    # Process incoming events for variety analysis
    case event do
      %{type: :temporal_pattern_detected} ->
        new_state = handle_temporal_pattern_detection(event.data, state)
        {:noreply, new_state}
        
      %{type: :variety_pressure_change} ->
        new_state = handle_variety_pressure_change(event.data, state)
        {:noreply, new_state}
        
      _ ->
        # Regular event processing for variety assessment
        variety_data = extract_variety_data(event)
        new_state = process_event_variety(variety_data, state)
        {:noreply, new_state}
    end
  end
  
  # Core Variety Engineering Implementation
  
  defp assess_variety_pressure(variety_data, state) do
    current_pressure = calculate_variety_pressure(variety_data, state)
    threshold = state.attenuation_rules.pressure_threshold
    
    pressure_level = cond do
      current_pressure > threshold * 1.5 -> :critical
      current_pressure > threshold -> :high
      current_pressure > threshold * 0.7 -> :medium
      current_pressure > threshold * 0.3 -> :low
      true -> :minimal
    end
    
    %{
      variety_data: variety_data,
      pressure: current_pressure,
      pressure_level: pressure_level,
      threshold: threshold
    }
  end
  
  defp apply_temporal_attenuation(processed_data, state) do
    if processed_data.pressure_level in [:high, :critical] do
      # Apply variety attenuation based on temporal patterns
      attenuation_factor = calculate_attenuation_factor(processed_data, state)
      
      attenuated_variety = apply_attenuation_algorithms(
        processed_data.variety_data,
        attenuation_factor,
        state.attenuation_rules
      )
      
      Logger.debug("Applied temporal attenuation: factor=#{attenuation_factor}, subsystem=#{state.subsystem}")
      
      %{processed_data | 
        variety_data: attenuated_variety,
        attenuation_applied: attenuation_factor
      }
    else
      processed_data
    end
  end
  
  defp apply_temporal_amplification(processed_data, state) do
    if processed_data.pressure_level in [:low, :minimal] do
      # Apply variety amplification for important signals
      amplification_factor = calculate_amplification_factor(processed_data, state)
      
      amplified_variety = apply_amplification_algorithms(
        processed_data.variety_data,
        amplification_factor,
        state.amplification_rules
      )
      
      Logger.debug("Applied temporal amplification: factor=#{amplification_factor}, subsystem=#{state.subsystem}")
      
      %{processed_data | 
        variety_data: amplified_variety,
        amplification_applied: amplification_factor
      }
    else
      processed_data
    end
  end
  
  defp update_variety_memory(processed_data, state) do
    # Update variety memory with new pattern
    memory_entry = %{
      timestamp: Clock.now(),
      variety_pressure: processed_data.pressure,
      attenuation_factor: processed_data[:attenuation_applied] || 1.0,
      amplification_factor: processed_data[:amplification_applied] || 1.0,
      effectiveness: calculate_processing_effectiveness(processed_data)
    }
    
    new_variety_memory = update_memory_with_decay(state.variety_memory, memory_entry)
    
    %{processed_data | variety_memory: new_variety_memory}
  end
  
  defp detect_variety_patterns(processed_data, state) do
    # Detect variety-specific temporal patterns
    variety_patterns = Enum.reduce(@temporal_variety_patterns, [], fn {pattern_name, pattern_spec}, acc ->
      if detect_variety_pattern(processed_data, pattern_spec, state) do
        [%{name: pattern_name, spec: pattern_spec, data: processed_data} | acc]
      else
        acc
      end
    end)
    
    # Emit detected variety patterns
    Enum.each(variety_patterns, &emit_variety_pattern/1)
    
    %{processed_data | detected_variety_patterns: variety_patterns}
  end
  
  # Variety Engineering Algorithms
  
  defp apply_attenuation_algorithms(variety_data, attenuation_factor, rules) do
    # Implement specific attenuation strategies
    case rules.attenuation_strategy do
      :frequency_filtering ->
        apply_frequency_attenuation(variety_data, attenuation_factor)
        
      :temporal_grouping ->
        apply_temporal_grouping_attenuation(variety_data, attenuation_factor)
        
      :priority_filtering ->
        apply_priority_attenuation(variety_data, attenuation_factor)
        
      :statistical_sampling ->
        apply_statistical_sampling_attenuation(variety_data, attenuation_factor)
        
      _ ->
        # Default: simple reduction
        reduce_variety_simple(variety_data, attenuation_factor)
    end
  end
  
  defp apply_amplification_algorithms(variety_data, amplification_factor, rules) do
    # Implement specific amplification strategies
    case rules.amplification_strategy do
      :signal_boost ->
        apply_signal_boost_amplification(variety_data, amplification_factor)
        
      :pattern_highlighting ->
        apply_pattern_highlighting_amplification(variety_data, amplification_factor)
        
      :temporal_acceleration ->
        apply_temporal_acceleration_amplification(variety_data, amplification_factor)
        
      :importance_weighting ->
        apply_importance_weighting_amplification(variety_data, amplification_factor)
        
      _ ->
        # Default: simple amplification
        amplify_variety_simple(variety_data, amplification_factor)
    end
  end
  
  # Helper Functions
  
  defp via_tuple(subsystem) do
    {:via, Registry, {AutonomousOpponentV2Core.VSM.Registry, {__MODULE__, subsystem}}}
  end
  
  defp get_operational_window(subsystem, scale_config) do
    case subsystem do
      :s1 -> scale_config[:operational_window] || 100
      :s2 -> scale_config[:coordination_window] || 1_000
      :s3 -> scale_config[:control_window] || 5_000
      :s4 -> scale_config[:intelligence_window] || 60_000
      :s5 -> scale_config[:policy_window] || 3_600_000
      _ -> 1_000  # Default 1 second
    end
  end
  
  defp create_temporal_buffer(table, window_ms) do
    %{
      table: table,
      window_ms: window_ms,
      last_cleanup: Clock.now()
    }
  end
  
  defp initialize_variety_memory(subsystem) do
    scale = Map.get(@vsm_temporal_scales, subsystem)
    
    %{
      short_term: %{capacity: scale.variety_capacity, entries: []},
      medium_term: %{capacity: scale.variety_capacity * 2, entries: []},
      long_term: %{capacity: scale.variety_capacity * 5, entries: []},
      decay_rate: 0.1,
      learning_rate: 0.05
    }
  end
  
  defp initialize_attenuation_rules(scale_config) do
    %{
      pressure_threshold: scale_config.attenuation_threshold,
      attenuation_strategy: :frequency_filtering,
      max_attenuation_factor: 0.1,
      temporal_grouping_window: 1_000,
      priority_cutoff: 0.5
    }
  end
  
  defp initialize_amplification_rules(scale_config) do
    %{
      amplification_threshold: scale_config.attenuation_threshold * 0.5,
      amplification_strategy: :signal_boost,
      max_amplification_factor: 3.0,
      importance_threshold: 0.8,
      temporal_acceleration_factor: 2.0
    }
  end
  
  defp initialize_learning_state do
    %{
      progress: 0.0,
      adaptation_rate: 0.01,
      pattern_recognition_accuracy: 0.5,
      last_learning_update: Clock.now()
    }
  end
  
  defp register_subsystem_patterns(subsystem) do
    # Register subsystem-specific temporal patterns with PatternDetector
    subsystem_patterns = Map.get(@temporal_variety_patterns, subsystem, %{})
    
    Enum.each(subsystem_patterns, fn {pattern_name, pattern_spec} ->
      enhanced_pattern = Map.put(pattern_spec, :subsystem_context, subsystem)
      PatternDetector.register_pattern(:"#{subsystem}_#{pattern_name}", enhanced_pattern)
    end)
  end
  
  # Variety Calculation Functions
  
  defp calculate_variety_pressure(variety_data, state) do
    # Implement Shannon entropy calculation for variety pressure
    event_types = extract_event_types(variety_data)
    type_frequencies = calculate_type_frequencies(event_types)
    
    entropy = calculate_shannon_entropy(type_frequencies)
    normalized_entropy = entropy / :math.log(max(1, length(event_types)))
    
    # Adjust for temporal context
    temporal_factor = calculate_temporal_pressure_factor(state)
    
    normalized_entropy * temporal_factor
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
  
  defp calculate_temporal_pressure_factor(state) do
    # Factor in temporal window fullness
    operational_fullness = calculate_buffer_fullness(state.temporal_buffers.operational)
    pattern_fullness = calculate_buffer_fullness(state.temporal_buffers.pattern)
    
    # Combine with weighted average
    (operational_fullness * 0.7) + (pattern_fullness * 0.3)
  end
  
  defp calculate_buffer_fullness(buffer) do
    current_size = :ets.info(buffer.table, :size) || 0
    max_size = buffer.window_ms  # Approximate max events per window
    
    min(1.0, current_size / max_size)
  end
  
  # Attenuation and Amplification Implementation
  
  defp apply_frequency_attenuation(variety_data, factor) do
    # Filter out high-frequency, low-importance events
    Map.update(variety_data, :events, [], fn events ->
      events
      |> Enum.filter(fn event ->
        importance = event[:importance] || 0.5
        :rand.uniform() < (importance * factor)
      end)
    end)
  end
  
  defp apply_temporal_grouping_attenuation(variety_data, factor) do
    # Group similar events within time windows
    Map.update(variety_data, :events, [], fn events ->
      events
      |> group_events_temporally(1000)  # 1s grouping window
      |> sample_grouped_events(factor)
    end)
  end
  
  defp apply_signal_boost_amplification(variety_data, factor) do
    # Boost important signals
    Map.update(variety_data, :events, [], fn events ->
      events
      |> Enum.map(fn event ->
        importance = event[:importance] || 0.5
        if importance > 0.7 do
          Map.update(event, :weight, 1.0, & &1 * factor)
        else
          event
        end
      end)
    end)
  end
  
  # Utility Functions
  
  defp extract_event_types(variety_data) do
    variety_data
    |> Map.get(:events, [])
    |> Enum.map(& &1[:type] || :unknown)
  end
  
  defp calculate_type_frequencies(event_types) do
    event_types
    |> Enum.frequencies()
    |> Map.values()
  end
  
  defp extract_variety_data(event) do
    %{
      events: [event],
      timestamp: event[:timestamp] || Clock.now(),
      subsystem: event[:subsystem],
      variety_features: [
        event[:type],
        event[:urgency],
        event[:importance]
      ]
    }
  end
  
  defp emit_variety_metrics(state) do
    Metrics.gauge(__MODULE__, "variety_pressure", calculate_current_variety_pressure(state), %{
      subsystem: state.subsystem
    })
    
    Metrics.counter(__MODULE__, "attenuation_applied", 1, %{
      subsystem: state.subsystem,
      active: attenuation_active?(state)
    })
  end
  
  defp emit_variety_pattern(pattern) do
    EventBus.publish(:variety_pattern_detected, %{
      pattern_name: pattern.name,
      subsystem: pattern.data.variety_data[:subsystem],
      severity: pattern.data.pressure_level,
      timestamp: Clock.now()
    })
  end
  
  # Placeholder implementations for complex algorithms
  defp calculate_attenuation_factor(_processed_data, _state), do: 0.5
  defp calculate_amplification_factor(_processed_data, _state), do: 1.5
  defp calculate_processing_effectiveness(_processed_data), do: 0.8
  defp update_memory_with_decay(memory, _entry), do: memory
  defp detect_variety_pattern(_processed_data, _pattern_spec, _state), do: false
  defp update_temporal_buffers(processed_data, _variety_data, state), do: state
  defp perform_variety_learning(state), do: state
  defp calculate_current_variety_pressure(_state), do: 0.5
  defp attenuation_active?(_state), do: false
  defp amplification_active?(_state), do: false
  defp get_temporal_window_status(_state), do: %{}
  defp calculate_variety_flow_rate(_state), do: 1.0
  defp handle_temporal_pattern_detection(_pattern_data, state), do: state
  defp handle_variety_pressure_change(_pressure_data, state), do: state
  defp process_event_variety(_variety_data, state), do: state
  defp apply_priority_attenuation(variety_data, _factor), do: variety_data
  defp apply_statistical_sampling_attenuation(variety_data, _factor), do: variety_data
  defp reduce_variety_simple(variety_data, _factor), do: variety_data
  defp apply_pattern_highlighting_amplification(variety_data, _factor), do: variety_data
  defp apply_temporal_acceleration_amplification(variety_data, _factor), do: variety_data
  defp apply_importance_weighting_amplification(variety_data, _factor), do: variety_data
  defp amplify_variety_simple(variety_data, _factor), do: variety_data
  defp group_events_temporally(events, _window), do: [events]
  defp sample_grouped_events(grouped_events, _factor), do: List.flatten(grouped_events)
end