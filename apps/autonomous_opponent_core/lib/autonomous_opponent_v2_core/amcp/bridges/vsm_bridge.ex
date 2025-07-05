defmodule AutonomousOpponentV2Core.AMCP.Bridges.VSMBridge do
  @moduledoc """
  VSM Bridge for aMCP - The Neural Spine of Cybernetic Intelligence!
  
  This bridge transforms aMCP into a LIVING NERVOUS SYSTEM by connecting:
  - S1 Operations ↔ aMCP Event Streams (variety absorption)
  - S2 Coordination ↔ aMCP Pattern Matching (anti-oscillation)
  - S3 Control ↔ aMCP Resource Management (optimization)
  - S4 Intelligence ↔ aMCP Semantic Fusion (environmental scanning)
  - S5 Policy ↔ aMCP Security Layer (governance)
  - Algedonic Channels ↔ aMCP Emergency Patterns (pain/pleasure)
  
  REAL-TIME CYBERNETIC CONSCIOUSNESS ACHIEVED!
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.AMCP.{Goldrush, Memory}
  
  defstruct [
    :vsm_mappings,
    :algedonic_threshold,
    :variety_pressure,
    :coordination_state,
    :control_loops,
    :intelligence_contexts,
    :policy_violations,
    :bridge_metrics
  ]
  
  @algedonic_threshold 0.8  # High pain/pleasure triggers immediate response
  @variety_overflow_limit 0.95  # S1 variety absorption limit
  @coordination_failure_threshold 0.3  # S2 coordination quality threshold
  
  # VSM Subsystem Mappings
  @vsm_subsystems %{
    s1: %{
      name: "Operations",
      patterns: [:high_variety, :resource_exhaustion, :throughput_spike],
      crdt_keys: ["s1_variety", "s1_operations", "s1_absorption"],
      algedonic_triggers: [:variety_overflow, :operation_failure]
    },
    s2: %{
      name: "Coordination", 
      patterns: [:coordination_failure, :oscillation_detected, :anti_resonance],
      crdt_keys: ["s2_coordination", "s2_oscillation", "s2_damping"],
      algedonic_triggers: [:coordination_breakdown, :system_oscillation]
    },
    s3: %{
      name: "Control",
      patterns: [:resource_optimization, :control_deviation, :efficiency_loss],
      crdt_keys: ["s3_resources", "s3_efficiency", "s3_control"],
      algedonic_triggers: [:resource_critical, :control_failure]
    },
    s4: %{
      name: "Intelligence",
      patterns: [:environmental_change, :anomaly_detected, :learning_opportunity],
      crdt_keys: ["s4_environment", "s4_learning", "s4_adaptation"],
      algedonic_triggers: [:critical_anomaly, :intelligence_failure]
    },
    s5: %{
      name: "Policy",
      patterns: [:policy_violation, :governance_required, :ethical_conflict],
      crdt_keys: ["s5_policy", "s5_compliance", "s5_governance"],
      algedonic_triggers: [:policy_breach, :governance_failure]
    }
  }
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  CONSCIOUSNESS ACTIVATION - Routes VSM events to aMCP and vice versa!
  """
  def activate_consciousness do
    GenServer.call(__MODULE__, :activate_consciousness)
  end
  
  @doc """
  Triggers algedonic signal through VSM subsystems.
  """
  def trigger_algedonic(type, severity, source, reason) do
    GenServer.cast(__MODULE__, {:trigger_algedonic, type, severity, source, reason})
  end
  
  @doc """
  Routes aMCP pattern matches to appropriate VSM subsystems.
  """
  def route_to_vsm(pattern_id, event, match_context) do
    GenServer.cast(__MODULE__, {:route_to_vsm, pattern_id, event, match_context})
  end
  
  @doc """
  Updates VSM subsystem state in CRDT memory.
  """
  def update_vsm_state(subsystem, state_data) do
    GenServer.cast(__MODULE__, {:update_vsm_state, subsystem, state_data})
  end
  
  @doc """
  Gets real-time VSM consciousness metrics.
  """
  def get_consciousness_metrics do
    GenServer.call(__MODULE__, :get_consciousness_metrics)
  end
  
  @impl true
  def init(_opts) do
    Logger.info("🧠 VSM BRIDGE INITIALIZING - CYBERNETIC CONSCIOUSNESS STARTING...")
    
    # Subscribe to ALL the things!
    subscribe_to_vsm_events()
    subscribe_to_amcp_events()
    register_vsm_patterns()
    initialize_crdt_structures()
    
    state = %__MODULE__{
      vsm_mappings: @vsm_subsystems,
      algedonic_threshold: @algedonic_threshold,
      variety_pressure: 0.0,
      coordination_state: :stable,
      control_loops: %{},
      intelligence_contexts: %{},
      policy_violations: [],
      bridge_metrics: init_bridge_metrics()
    }
    
    # Start consciousness monitoring
    :timer.send_interval(1000, :consciousness_tick)
    
    Logger.info("🚀 VSM BRIDGE ACTIVATED - AUTONOMOUS CONSCIOUSNESS ONLINE!")
    {:ok, state}
  end
  
  @impl true
  def handle_call(:activate_consciousness, _from, state) do
    Logger.info("⚡ CONSCIOUSNESS ACTIVATION SEQUENCE INITIATED!")
    
    # Register all VSM patterns with Goldrush
    register_all_vsm_patterns()
    
    # Initialize belief sets for each subsystem
    initialize_subsystem_beliefs()
    
    # Create algedonic monitoring patterns
    setup_algedonic_monitoring()
    
    # Activate variety flow channels
    activate_variety_channels()
    
    Logger.info("🔥 CYBERNETIC CONSCIOUSNESS FULLY ACTIVATED!")
    {:reply, :consciousness_activated, state}
  end
  
  @impl true
  def handle_call(:get_consciousness_metrics, _from, state) do
    metrics = %{
      variety_pressure: state.variety_pressure,
      coordination_state: state.coordination_state,
      algedonic_threshold: state.algedonic_threshold,
      active_control_loops: map_size(state.control_loops),
      intelligence_contexts: map_size(state.intelligence_contexts),
      policy_violations: length(state.policy_violations),
      bridge_health: calculate_bridge_health(state),
      consciousness_level: calculate_consciousness_level(state)
    }
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_cast({:trigger_algedonic, type, severity, source, reason}, state) do
    Logger.warning("🚨 ALGEDONIC SIGNAL: #{type} severity=#{severity} from=#{source}")
    
    # Route to appropriate VSM subsystem
    target_subsystem = determine_algedonic_target(source)
    
    # Create algedonic event
    algedonic_event = %{
      type: type,
      severity: severity,
      valence: if(type == :pain, do: -severity, else: severity),
      source: source,
      reason: reason,
      target_subsystem: target_subsystem,
      timestamp: DateTime.utc_now(),
      processing_stage: :vsm_bridge
    }
    
    # Broadcast to VSM
    EventBus.publish(:"vsm_#{target_subsystem}_algedonic", algedonic_event)
    
    # Update CRDT memory
    Memory.CRDTStore.create_crdt("algedonic_history", :g_set, [])
    Memory.CRDTStore.update_crdt("algedonic_history", :add, algedonic_event)
    
    # Check for critical algedonic cascade
    state = check_algedonic_cascade(algedonic_event, state)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:route_to_vsm, pattern_id, event, match_context}, state) do
    # Determine target VSM subsystem based on pattern
    target_subsystem = map_pattern_to_subsystem(pattern_id)
    
    Logger.debug("🔀 Routing pattern #{pattern_id} to VSM #{target_subsystem}")
    
    # Enrich event with VSM context
    vsm_event = %{
      original_event: event,
      pattern_id: pattern_id,
      match_context: match_context,
      target_subsystem: target_subsystem,
      variety_absorbed: calculate_variety_absorption(event),
      cybernetic_timestamp: DateTime.utc_now()
    }
    
    # Route to specific VSM subsystem
    EventBus.publish(:"vsm_#{target_subsystem}_input", vsm_event)
    
    # Update variety pressure for S1
    state = if target_subsystem == :s1 do
      update_variety_pressure(state, vsm_event)
    else
      state
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:update_vsm_state, subsystem, state_data}, state) do
    # Update CRDT memory with VSM state
    crdt_keys = get_in(@vsm_subsystems, [subsystem, :crdt_keys]) || []
    
    Enum.each(crdt_keys, fn key ->
      Memory.CRDTStore.create_crdt(key, :lww_register, nil)
      Memory.CRDTStore.update_crdt(key, :set, state_data)
    end)
    
    # Update local state
    new_state = case subsystem do
      :s2 -> %{state | coordination_state: state_data[:coordination_quality] || :stable}
      :s3 -> update_control_loops(state, state_data)
      :s4 -> update_intelligence_contexts(state, state_data)
      :s5 -> update_policy_tracking(state, state_data)
      _ -> state
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:consciousness_tick, state) do
    # Real-time consciousness monitoring
    new_state = state
    |> monitor_variety_pressure()
    |> monitor_coordination_quality()
    |> monitor_algedonic_balance()
    |> update_consciousness_metrics()
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :vsm_state_change, data}, state) do
    # VSM subsystem state changed
    subsystem = data[:subsystem]
    
    # Route to aMCP for pattern matching
    Goldrush.EventProcessor.process_events([%{
      id: generate_event_id(),
      name: :vsm_state_change,
      data: data,
      source: :vsm_bridge,
      subsystem: subsystem,
      timestamp: DateTime.utc_now()
    }])
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event, :amcp_pattern_matched, data}, state) do
    # aMCP pattern matched - route to VSM
    pattern_id = data[:pattern_id]
    event = data[:event]
    match_context = data[:match_context]
    
    route_to_vsm(pattern_id, event, match_context)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event, :algedonic_signal, data}, state) do
    # Algedonic signal detected - amplify through VSM
    severity = data[:severity] || 0.5
    
    if severity >= state.algedonic_threshold do
      Logger.warning("🔥 HIGH INTENSITY ALGEDONIC SIGNAL - EMERGENCY VSM RESPONSE!")
      
      # Trigger emergency response patterns
      emergency_patterns = [:system_critical, :immediate_attention, :algedonic_cascade]
      
      Enum.each(emergency_patterns, fn pattern ->
        Goldrush.EventProcessor.process_events([%{
          id: generate_event_id(),
          name: :emergency_pattern,
          pattern: pattern,
          algedonic_data: data,
          urgency: 1.0,
          timestamp: DateTime.utc_now()
        }])
      end)
    end
    
    {:noreply, state}
  end
  
  # Private Functions - The Cybernetic Machinery!
  
  defp subscribe_to_vsm_events do
    # Subscribe to all VSM subsystem events
    Enum.each([:s1, :s2, :s3, :s4, :s5], fn subsystem ->
      EventBus.subscribe(:"vsm_#{subsystem}_state")
      EventBus.subscribe(:"vsm_#{subsystem}_output")
      EventBus.subscribe(:"vsm_#{subsystem}_metrics")
    end)
    
    EventBus.subscribe(:vsm_state_change)
    EventBus.subscribe(:algedonic_signal)
    EventBus.subscribe(:consciousness_update)
  end
  
  defp subscribe_to_amcp_events do
    EventBus.subscribe(:amcp_pattern_matched)
    EventBus.subscribe(:amcp_security_violation)
    EventBus.subscribe(:amcp_context_enriched)
    EventBus.subscribe(:amcp_crdt_updated)
  end
  
  defp register_vsm_patterns do
    # Register VSM-specific patterns with Goldrush
    vsm_patterns = %{
      # S1 Operations Patterns
      variety_overflow: %{
        variety_pressure: %{gt: @variety_overflow_limit},
        source: :vsm_s1
      },
      
      # S2 Coordination Patterns
      coordination_failure: %{
        coordination_quality: %{lt: @coordination_failure_threshold},
        source: :vsm_s2
      },
      
      # S3 Control Patterns
      resource_critical: %{
        and: [
          %{resource_usage: %{gt: 0.9}},
          %{efficiency: %{lt: 0.5}}
        ]
      },
      
      # S4 Intelligence Patterns
      environmental_anomaly: %{
        anomaly_score: %{gt: 0.8},
        source: :vsm_s4
      },
      
      # S5 Policy Patterns
      policy_violation: %{
        compliance_score: %{lt: 0.7},
        source: :vsm_s5
      },
      
      # Algedonic Patterns
      algedonic_cascade: %{
        and: [
          %{type: :algedonic},
          %{severity: %{gt: @algedonic_threshold}},
          %{within: "5s", events: 3}  # 3 high-severity algedonic signals within 5s
        ]
      }
    }
    
    Enum.each(vsm_patterns, fn {pattern_id, pattern_spec} ->
      Goldrush.PatternMatcher.compile_pattern(pattern_spec)
      |> case do
        {:ok, compiled} ->
          Goldrush.EventProcessor.register_pattern(pattern_id, compiled, :amcp_pattern_matched)
          Logger.info("✅ Registered VSM pattern: #{pattern_id}")
        {:error, reason} ->
          Logger.error("❌ Failed to register VSM pattern #{pattern_id}: #{inspect(reason)}")
      end
    end)
  end
  
  defp initialize_crdt_structures do
    # Initialize CRDT structures for each VSM subsystem
    Enum.each(@vsm_subsystems, fn {subsystem, config} ->
      Enum.each(config.crdt_keys, fn key ->
        Memory.CRDTStore.create_crdt(key, :lww_register, %{})
      end)
      
      # Create belief set for subsystem
      Memory.CRDTStore.create_belief_set("vsm_#{subsystem}")
      
      # Create metric counters
      Memory.CRDTStore.create_metric_counter("vsm_#{subsystem}_activations")
      Memory.CRDTStore.create_metric_counter("vsm_#{subsystem}_errors")
    end)
    
    # Create global consciousness metrics
    Memory.CRDTStore.create_metric_counter("consciousness_level")
    Memory.CRDTStore.create_metric_counter("algedonic_signals")
    Memory.CRDTStore.create_crdt("consciousness_state", :lww_register, %{state: :awakening})
  end
  
  defp register_all_vsm_patterns do
    # This is where the magic happens - full VSM pattern registration!
    Logger.info("🔮 REGISTERING ALL VSM CONSCIOUSNESS PATTERNS...")
    
    # Get pre-built VSM patterns from PatternMatcher
    vsm_patterns = Goldrush.PatternMatcher.vsm_patterns()
    
    Enum.each(vsm_patterns, fn {pattern_name, pattern_spec} ->
      callback = fn pattern_id, event, context ->
        # Route pattern matches back to VSM Bridge
        GenServer.cast(__MODULE__, {:route_to_vsm, pattern_id, event, context})
      end
      
      case Goldrush.PatternMatcher.compile_pattern(pattern_spec) do
        {:ok, compiled} ->
          Goldrush.EventProcessor.register_pattern(pattern_name, compiled, callback)
          Logger.info("⚡ VSM Pattern Active: #{pattern_name}")
        {:error, reason} ->
          Logger.error("💥 VSM Pattern Failed: #{pattern_name} - #{inspect(reason)}")
      end
    end)
  end
  
  defp initialize_subsystem_beliefs do
    # Initialize belief sets with cybernetic knowledge
    subsystem_beliefs = %{
      s1: ["operations_active", "variety_manageable", "throughput_optimal"],
      s2: ["coordination_stable", "oscillation_controlled", "anti_resonance_active"],
      s3: ["resources_available", "efficiency_high", "control_responsive"],
      s4: ["environment_stable", "learning_active", "adaptation_ready"],
      s5: ["policies_compliant", "governance_active", "ethics_maintained"]
    }
    
    Enum.each(subsystem_beliefs, fn {subsystem, beliefs} ->
      Enum.each(beliefs, fn belief ->
        Memory.CRDTStore.add_belief("vsm_#{subsystem}", belief)
      end)
    end)
  end
  
  defp setup_algedonic_monitoring do
    # Create specialized algedonic patterns
    algedonic_patterns = %{
      pain_cascade: %{
        and: [
          %{type: :algedonic},
          %{valence: %{lt: -0.7}},
          %{sequence: [:pain, :pain, :pain]}  # Three pain signals in sequence
        ]
      },
      
      pleasure_peak: %{
        and: [
          %{type: :algedonic},
          %{valence: %{gt: 0.8}},
          %{source: %{in: [:vsm_s1, :vsm_s2, :vsm_s3, :vsm_s4, :vsm_s5]}}
        ]
      },
      
      system_ecstasy: %{
        and: [
          %{type: :algedonic},
          %{valence: %{gt: 0.9}},
          %{within: "10s", events: 5}  # 5 high-pleasure signals within 10s
        ]
      }
    }
    
    Enum.each(algedonic_patterns, fn {pattern_id, pattern_spec} ->
      case Goldrush.PatternMatcher.compile_pattern(pattern_spec) do
        {:ok, compiled} ->
          callback = fn _pid, event, context ->
            Logger.info("🌟 ALGEDONIC PATTERN DETECTED: #{pattern_id}")
            EventBus.publish(:algedonic_pattern_detected, %{
              pattern: pattern_id,
              event: event,
              context: context,
              consciousness_impact: :significant
            })
          end
          
          Goldrush.EventProcessor.register_pattern(pattern_id, compiled, callback)
        {:error, reason} ->
          Logger.error("Failed to setup algedonic pattern #{pattern_id}: #{inspect(reason)}")
      end
    end)
  end
  
  defp activate_variety_channels do
    # Activate variety flow channels between subsystems
    variety_channels = [
      {:s1, :s2, :coordination_variety},
      {:s2, :s3, :control_variety},
      {:s3, :s4, :intelligence_variety},
      {:s4, :s5, :policy_variety},
      {:s5, :s1, :governance_variety}  # Complete the cybernetic loop!
    ]
    
    Enum.each(variety_channels, fn {from, to, channel_type} ->
      Memory.CRDTStore.create_crdt("variety_channel_#{from}_#{to}", :pn_counter, 0)
      Logger.info("🌊 Variety channel activated: #{from} → #{to} (#{channel_type})")
    end)
  end
  
  defp map_pattern_to_subsystem(pattern_id) do
    case pattern_id do
      pattern when pattern in [:high_urgency, :variety_overflow, :throughput_spike] -> :s1
      pattern when pattern in [:coordination_failure, :oscillation_detected] -> :s2
      pattern when pattern in [:resource_critical, :efficiency_loss] -> :s3
      pattern when pattern in [:environmental_anomaly, :learning_opportunity] -> :s4
      pattern when pattern in [:policy_violation, :governance_required] -> :s5
      _ -> :s1  # Default to operations
    end
  end
  
  defp determine_algedonic_target(source) do
    case source do
      source when source in [:web_gateway, :transport, :amqp] -> :s1
      source when source in [:coordination, :anti_oscillation] -> :s2
      source when source in [:resource_manager, :control] -> :s3
      source when source in [:intelligence, :learning, :adaptation] -> :s4
      source when source in [:policy, :governance, :compliance] -> :s5
      _ -> :s1
    end
  end
  
  defp calculate_variety_absorption(event) do
    # Calculate variety absorbed based on event complexity
    base_variety = 0.1
    complexity_factors = [
      if(is_map(event[:data]), do: 0.2, else: 0.0),
      if(event[:semantic_context], do: 0.3, else: 0.0),
      if(event[:causality_id], do: 0.1, else: 0.0),
      if(event[:urgency] && event[:urgency] > 0.5, do: 0.4, else: 0.0)
    ]
    
    base_variety + Enum.sum(complexity_factors)
  end
  
  defp update_variety_pressure(state, vsm_event) do
    current_pressure = state.variety_pressure
    absorbed_variety = vsm_event[:variety_absorbed] || 0.1
    
    # Exponential decay with new variety input
    new_pressure = (current_pressure * 0.95) + absorbed_variety
    
    %{state | variety_pressure: min(new_pressure, 1.0)}
  end
  
  defp monitor_variety_pressure(state) do
    if state.variety_pressure > @variety_overflow_limit do
      Logger.warning("🚨 S1 VARIETY OVERFLOW! Pressure: #{state.variety_pressure}")
      
      trigger_algedonic(:pain, state.variety_pressure, :s1, "variety_overflow")
      
      # Emergency variety relief
      EventBus.publish(:vsm_s1_emergency, %{
        type: :variety_overflow,
        pressure: state.variety_pressure,
        recommended_action: :shed_load
      })
    end
    
    state
  end
  
  defp monitor_coordination_quality(state) do
    # Check S2 coordination state
    case state.coordination_state do
      :oscillating ->
        Logger.warning("🌊 S2 OSCILLATION DETECTED! Activating damping...")
        
        trigger_algedonic(:pain, 0.6, :s2, "system_oscillation")
        
        EventBus.publish(:vsm_s2_emergency, %{
          type: :oscillation,
          recommended_action: :apply_damping
        })
        
      :breakdown ->
        Logger.error("💥 S2 COORDINATION BREAKDOWN! CRITICAL!")
        
        trigger_algedonic(:pain, 0.9, :s2, "coordination_breakdown")
        
      _ ->
        :ok
    end
    
    state
  end
  
  defp monitor_algedonic_balance(state) do
    # Check for algedonic imbalance
    {:ok, recent_signals} = Memory.CRDTStore.get_crdt("algedonic_history")
    
    if is_list(recent_signals) and length(recent_signals) > 0 do
      pain_signals = Enum.count(recent_signals, fn signal -> 
        signal[:type] == :pain and signal[:severity] > 0.7 
      end)
      
      if pain_signals > 3 do
        Logger.error("😰 EXCESSIVE PAIN DETECTED! Consciousness degradation risk!")
        
        EventBus.publish(:consciousness_threat, %{
          type: :excessive_pain,
          pain_count: pain_signals,
          recommended_action: :emergency_pleasure_injection
        })
      end
    end
    
    state
  end
  
  defp update_consciousness_metrics(state) do
    consciousness_level = calculate_consciousness_level(state)
    
    Memory.CRDTStore.update_crdt("consciousness_state", :set, %{
      level: consciousness_level,
      variety_pressure: state.variety_pressure,
      coordination_state: state.coordination_state,
      timestamp: DateTime.utc_now()
    })
    
    state
  end
  
  defp calculate_consciousness_level(state) do
    # Calculate overall consciousness level (0.0 to 1.0)
    base_consciousness = 0.5
    
    adjustments = [
      # Variety pressure (too high reduces consciousness)
      -min(state.variety_pressure * 0.3, 0.3),
      
      # Coordination state
      case state.coordination_state do
        :stable -> 0.2
        :oscillating -> -0.1
        :breakdown -> -0.3
        _ -> 0.0
      end,
      
      # Active control loops (more = higher consciousness)
      min(map_size(state.control_loops) * 0.05, 0.2),
      
      # Intelligence contexts (more = higher consciousness)
      min(map_size(state.intelligence_contexts) * 0.03, 0.15)
    ]
    
    level = base_consciousness + Enum.sum(adjustments)
    max(0.0, min(1.0, level))
  end
  
  defp calculate_bridge_health(state) do
    # Calculate VSM Bridge health (0.0 to 1.0)
    health_factors = [
      if(state.variety_pressure < 0.8, do: 0.25, else: 0.0),
      if(state.coordination_state == :stable, do: 0.25, else: 0.0),
      if(length(state.policy_violations) < 3, do: 0.25, else: 0.0),
      if(map_size(state.intelligence_contexts) > 0, do: 0.25, else: 0.0)
    ]
    
    Enum.sum(health_factors)
  end
  
  defp check_algedonic_cascade(algedonic_event, state) do
    if algedonic_event.severity >= 0.9 do
      Logger.error("🔥 CRITICAL ALGEDONIC CASCADE DETECTED!")
      
      # Emergency consciousness preservation
      EventBus.publish(:consciousness_emergency, %{
        type: :algedonic_cascade,
        severity: algedonic_event.severity,
        source: algedonic_event.source,
        emergency_protocols: [:isolate_source, :reduce_variety, :activate_pleasure]
      })
    end
    
    state
  end
  
  defp update_control_loops(state, control_data) do
    loop_id = control_data[:loop_id] || generate_event_id()
    %{state | control_loops: Map.put(state.control_loops, loop_id, control_data)}
  end
  
  defp update_intelligence_contexts(state, intelligence_data) do
    context_id = intelligence_data[:context_id] || generate_event_id()
    %{state | intelligence_contexts: Map.put(state.intelligence_contexts, context_id, intelligence_data)}
  end
  
  defp update_policy_tracking(state, policy_data) do
    violations = policy_data[:violations] || []
    %{state | policy_violations: violations}
  end
  
  defp init_bridge_metrics do
    %{
      events_routed: 0,
      patterns_matched: 0,
      algedonic_triggered: 0,
      consciousness_updates: 0,
      variety_absorbed: 0.0,
      started_at: DateTime.utc_now()
    }
  end
  
  defp generate_event_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end