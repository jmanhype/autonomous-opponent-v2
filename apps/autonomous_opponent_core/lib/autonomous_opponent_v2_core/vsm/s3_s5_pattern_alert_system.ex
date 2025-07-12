defmodule AutonomousOpponentV2Core.VSM.S3S5PatternAlertSystem do
  @moduledoc """
  Pattern Alert System for S3/S5 Integration - Issue #92
  
  Bridges S4 Intelligence pattern detection with S3 Control interventions
  and S5 Policy governance. Implements cybernetic control loops for
  pattern-based system adaptation following Beer's VSM principles.
  
  Key Features:
  - Critical pattern alerting (confidence > 0.8, severity: high/critical)
  - Automatic S3 control interventions for operational patterns
  - S5 policy adjustments for strategic patterns
  - Algedonic bypass for emergency patterns
  - Pattern-based resource optimization
  - Cybernetic feedback loops with variety management
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S3.Control, as: S3
  alias AutonomousOpponentV2Core.VSM.S5.Policy, as: S5
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: Algedonic
  
  defstruct [
    :alert_thresholds,
    :pattern_history,
    :active_alerts,
    :intervention_queue,
    :policy_adjustments,
    :metrics,
    :feedback_loops,
    :emergency_mode
  ]
  
  # Alert thresholds
  @critical_confidence 0.9
  @high_confidence 0.8
  @pattern_history_limit 1000
  @intervention_cooldown_ms 5000
  @emergency_pattern_types [:system_failure, :security_breach, :cascade_failure, :algedonic_storm]
  
  # Pattern classification for S3/S5 routing
  @operational_patterns [:resource_exhaustion, :performance_degradation, :coordination_breakdown, 
                        :variety_overload, :oscillation_detected, :bottleneck_identified]
  @strategic_patterns [:paradigm_shift, :environmental_threat, :competitive_pressure,
                      :identity_drift, :value_misalignment, :existential_risk]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def process_pattern_alert(pattern_data) do
    GenServer.cast(__MODULE__, {:pattern_alert, pattern_data})
  end
  
  def get_active_alerts do
    GenServer.call(__MODULE__, :get_active_alerts)
  end
  
  def get_alert_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  def emergency_override(pattern_id, action) do
    GenServer.call(__MODULE__, {:emergency_override, pattern_id, action})
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Subscribe to pattern events from S4 Intelligence
    EventBus.subscribe(:pattern_detected)
    EventBus.subscribe(:pattern_causality_detected)  # From correlation analyzer
    EventBus.subscribe(:algedonic_correlation_detected)
    EventBus.subscribe(:s4_intelligence)
    
    # Subscribe to feedback from S3 and S5
    EventBus.subscribe(:s3_intervention_complete)
    EventBus.subscribe(:s5_policy_updated)
    
    # Initialize periodic cleanup
    Process.send_after(self(), :cleanup_history, 60_000)  # 1 minute
    
    state = %__MODULE__{
      alert_thresholds: init_alert_thresholds(),
      pattern_history: :queue.new(),
      active_alerts: %{},
      intervention_queue: :queue.new(),
      policy_adjustments: [],
      metrics: init_metrics(),
      feedback_loops: init_feedback_loops(),
      emergency_mode: false
    }
    
    Logger.info("🚨 S3/S5 Pattern Alert System initialized - cybernetic control active")
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:pattern_alert, pattern_data}, state) do
    new_state = process_pattern_for_alerts(pattern_data, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    alerts = Map.values(state.active_alerts)
    {:reply, alerts, state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  @impl true
  def handle_call({:emergency_override, pattern_id, action}, _from, state) do
    case execute_emergency_override(pattern_id, action, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  # Event handlers
  
  @impl true
  def handle_info({:event, :pattern_detected, pattern_data}, state) do
    # Process patterns from S4 Intelligence
    new_state = if should_alert_on_pattern?(pattern_data) do
      process_pattern_for_alerts(pattern_data, state)
    else
      # Just track in history
      update_pattern_history(state, pattern_data)
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :pattern_causality_detected, causality_data}, state) do
    # Handle causal chains from correlation analyzer
    new_state = process_causality_chain(causality_data, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :algedonic_correlation_detected, correlation_data}, state) do
    # High-priority algedonic correlations bypass normal processing
    new_state = handle_algedonic_correlation(correlation_data, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :s3_intervention_complete, intervention_result}, state) do
    # Feedback from S3 control actions
    new_state = process_intervention_feedback(intervention_result, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :s5_policy_updated, policy_update}, state) do
    # Feedback from S5 policy changes
    new_state = process_policy_feedback(policy_update, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:cleanup_history, state) do
    # Periodic cleanup of old data
    Process.send_after(self(), :cleanup_history, 60_000)
    
    new_state = cleanup_old_data(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, event}, state) do
    # Handle HLC-formatted events from EventBus
    case event.type do
      :pattern_detected ->
        handle_info({:event, :pattern_detected, event.data}, state)
      :pattern_causality_detected ->
        handle_info({:event, :pattern_causality_detected, event.data}, state)
      :algedonic_correlation_detected ->
        handle_info({:event, :algedonic_correlation_detected, event.data}, state)
      :s3_intervention_complete ->
        handle_info({:event, :s3_intervention_complete, event.data}, state)
      :s5_policy_updated ->
        handle_info({:event, :s5_policy_updated, event.data}, state)
      :s4_intelligence ->
        # S4 intelligence events might contain pattern data
        if event.data[:type] == :pattern_detected && event.data[:data] do
          handle_info({:event, :pattern_detected, event.data[:data]}, state)
        else
          {:noreply, state}
        end
      _ ->
        # Log and ignore other HLC events
        Logger.debug("S3S5PatternAlertSystem ignoring HLC event type: #{event.type}")
        {:noreply, state}
    end
  end
  
  # Private Functions
  
  defp init_alert_thresholds do
    %{
      confidence: %{
        critical: @critical_confidence,
        high: @high_confidence,
        medium: 0.7
      },
      severity: %{
        emergency: [:critical, :algedonic],
        immediate: [:high, :system_risk],
        standard: [:medium, :normal]
      },
      pattern_types: %{
        emergency: @emergency_pattern_types,
        operational: @operational_patterns,
        strategic: @strategic_patterns
      }
    }
  end
  
  defp init_metrics do
    %{
      patterns_processed: 0,
      alerts_generated: 0,
      s3_interventions: 0,
      s5_adjustments: 0,
      emergency_overrides: 0,
      algedonic_bypasses: 0,
      successful_interventions: 0,
      failed_interventions: 0,
      avg_response_time_ms: 0,
      last_alert_timestamp: nil
    }
  end
  
  defp init_feedback_loops do
    %{
      intervention_effectiveness: %{},  # pattern_type -> success_rate
      policy_impact: %{},              # policy_type -> system_improvement
      pattern_mitigation: %{},         # pattern_type -> mitigation_time_ms
      learning_rate: 0.1
    }
  end
  
  defp should_alert_on_pattern?(pattern_data) do
    confidence = pattern_data[:confidence] || 0.0
    severity = pattern_data[:severity] || :normal
    pattern_type = pattern_data[:pattern_type] || :unknown
    
    # Check if pattern meets alert criteria
    confidence >= @high_confidence or
    severity in [:high, :critical] or
    pattern_type in @emergency_pattern_types
  end
  
  defp process_pattern_for_alerts(pattern_data, state) do
    pattern_id = generate_alert_id(pattern_data)
    pattern_type = pattern_data[:pattern_type] || :unknown
    severity = pattern_data[:severity] || :normal
    
    # Create alert record
    alert = %{
      id: pattern_id,
      pattern_data: pattern_data,
      timestamp: DateTime.utc_now(),
      status: :active,
      routing: determine_routing(pattern_type),
      interventions: [],
      policy_adjustments: []
    }
    
    # Add to active alerts
    new_alerts = Map.put(state.active_alerts, pattern_id, alert)
    
    # Update metrics
    new_metrics = update_metrics(state.metrics, :alert_generated)
    
    # Route to appropriate subsystem
    new_state = %{state | 
      active_alerts: new_alerts,
      metrics: new_metrics
    }
    
    case alert.routing do
      :s3_operational ->
        route_to_s3_control(alert, new_state)
        
      :s5_strategic ->
        route_to_s5_policy(alert, new_state)
        
      :both ->
        new_state
        |> route_to_s3_control(alert)
        |> route_to_s5_policy(alert)
        
      :emergency ->
        handle_emergency_pattern(alert, new_state)
    end
  end
  
  defp determine_routing(pattern_type) do
    cond do
      pattern_type in @emergency_pattern_types -> :emergency
      pattern_type in @operational_patterns -> :s3_operational
      pattern_type in @strategic_patterns -> :s5_strategic
      true -> :both  # Unknown patterns go to both for analysis
    end
  end
  
  defp route_to_s3_control(alert, state) do
    # Prepare S3 control intervention
    intervention = %{
      pattern_id: alert.id,
      pattern_type: alert.pattern_data[:pattern_type],
      severity: alert.pattern_data[:severity],
      confidence: alert.pattern_data[:confidence],
      recommended_actions: generate_s3_recommendations(alert.pattern_data),
      timestamp: DateTime.utc_now()
    }
    
    # Send to S3 Control
    EventBus.publish(:s3_pattern_intervention, intervention)
    
    Logger.info("🎯 S3 Control intervention triggered for pattern #{alert.id}")
    
    # Track intervention
    new_queue = :queue.in(intervention, state.intervention_queue)
    new_metrics = update_metrics(state.metrics, :s3_intervention)
    
    %{state | 
      intervention_queue: new_queue,
      metrics: new_metrics
    }
  end
  
  defp route_to_s5_policy(alert, state) do
    # Prepare S5 policy adjustment
    adjustment = %{
      pattern_id: alert.id,
      pattern_type: alert.pattern_data[:pattern_type],
      severity: alert.pattern_data[:severity],
      confidence: alert.pattern_data[:confidence],
      policy_implications: analyze_policy_implications(alert.pattern_data),
      recommended_constraints: generate_policy_constraints(alert.pattern_data),
      timestamp: DateTime.utc_now()
    }
    
    # Send to S5 Policy
    EventBus.publish(:s5_pattern_policy, adjustment)
    
    Logger.info("📋 S5 Policy adjustment initiated for pattern #{alert.id}")
    
    # Track adjustment
    new_adjustments = [adjustment | state.policy_adjustments] |> Enum.take(100)
    new_metrics = update_metrics(state.metrics, :s5_adjustment)
    
    %{state |
      policy_adjustments: new_adjustments,
      metrics: new_metrics
    }
  end
  
  defp handle_emergency_pattern(alert, state) do
    Logger.error("🚨 EMERGENCY PATTERN DETECTED: #{alert.pattern_data[:pattern_type]}")
    
    # Activate emergency mode
    new_state = %{state | emergency_mode: true}
    
    # Algedonic bypass - immediate pain signal
    Algedonic.report_pain(:pattern_alert_system, alert.pattern_data[:pattern_type], 1.0)
    
    # Simultaneous S3 and S5 emergency response
    emergency_intervention = %{
      pattern_id: alert.id,
      pattern_type: alert.pattern_data[:pattern_type],
      emergency: true,
      bypass_normal_channels: true,
      immediate_actions: generate_emergency_actions(alert.pattern_data),
      timestamp: DateTime.utc_now()
    }
    
    # Broadcast emergency to all subsystems
    EventBus.publish(:vsm_emergency_pattern, emergency_intervention)
    
    # Update metrics
    new_metrics = update_metrics(new_state.metrics, :emergency_override)
    
    %{new_state | metrics: new_metrics}
  end
  
  defp process_causality_chain(causality_data, state) do
    # Analyze the causal chain for systemic issues
    root_pattern = causality_data[:root_pattern]
    chain = causality_data[:causality_chain]
    
    if length(chain) > 3 do
      # Complex causal chain indicates systemic issue
      Logger.warning("🔗 Complex causality chain detected: #{length(chain)} patterns")
      
      # Create meta-alert for the entire chain
      meta_alert = %{
        pattern_type: :causality_chain,
        severity: :high,
        confidence: 0.9,
        chain_length: length(chain),
        root_cause: root_pattern,
        chain_patterns: chain,
        metadata: %{source: :correlation_analyzer}
      }
      
      process_pattern_for_alerts(meta_alert, state)
    else
      state
    end
  end
  
  defp handle_algedonic_correlation(correlation_data, state) do
    # High-intensity algedonic correlations get immediate attention
    signal = correlation_data[:signal]
    correlations = correlation_data[:correlations]
    
    if signal[:intensity] > 0.8 do
      Logger.error("🔥 High-intensity algedonic correlation: #{signal[:type]}")
      
      # Create urgent alert
      urgent_alert = %{
        pattern_type: :algedonic_correlation,
        severity: :critical,
        confidence: 1.0,
        signal: signal,
        correlated_patterns: correlations,
        metadata: %{bypass_required: true}
      }
      
      handle_emergency_pattern(
        %{id: generate_alert_id(urgent_alert), pattern_data: urgent_alert},
        state
      )
    else
      state
    end
  end
  
  defp generate_s3_recommendations(pattern_data) do
    # Generate specific S3 control recommendations based on pattern type
    case pattern_data[:pattern_type] do
      :resource_exhaustion ->
        [
          {:reallocate_resources, %{from: :low_priority, to: :critical}},
          {:throttle_operations, %{level: 0.7}},
          {:activate_reserves, %{amount: :auto}}
        ]
        
      :performance_degradation ->
        [
          {:optimize_algorithms, %{target: :hot_paths}},
          {:increase_parallelism, %{factor: 2}},
          {:reduce_quality, %{acceptable_loss: 0.1}}
        ]
        
      :coordination_breakdown ->
        [
          {:reset_coordinators, %{scope: :affected}},
          {:simplify_protocols, %{level: :minimal}},
          {:increase_sync_frequency, %{multiplier: 1.5}}
        ]
        
      :variety_overload ->
        [
          {:increase_variety_absorption, %{channels: :all}},
          {:filter_inputs, %{threshold: :high}},
          {:delegate_decisions, %{to: :s1_units}}
        ]
        
      _ ->
        [{:monitor_closely, %{duration: :adaptive}}]
    end
  end
  
  defp generate_policy_constraints(pattern_data) do
    # Generate S5 policy constraints based on pattern implications
    case pattern_data[:pattern_type] do
      :paradigm_shift ->
        %{
          adaptation_rate: 0.8,
          core_value_flexibility: 0.3,
          innovation_threshold: 0.6
        }
        
      :environmental_threat ->
        %{
          survival_priority: 1.0,
          resource_conservation: 0.9,
          risk_tolerance: 0.2
        }
        
      :identity_drift ->
        %{
          identity_coherence_min: 0.8,
          value_enforcement: :strict,
          drift_correction_rate: 0.5
        }
        
      _ ->
        %{monitoring_level: :enhanced}
    end
  end
  
  defp analyze_policy_implications(pattern_data) do
    # Analyze how this pattern affects system policy
    %{
      identity_impact: assess_identity_impact(pattern_data),
      value_alignment: check_value_alignment(pattern_data),
      strategic_risk: calculate_strategic_risk(pattern_data),
      adaptation_required: determine_adaptation_need(pattern_data)
    }
  end
  
  defp generate_emergency_actions(pattern_data) do
    # Generate immediate emergency actions
    base_actions = [
      {:freeze_non_critical, %{duration: :until_resolved}},
      {:activate_all_reserves, %{}},
      {:broadcast_emergency, %{to: :all_subsystems}},
      {:enable_manual_override, %{}}
    ]
    
    specific_actions = case pattern_data[:pattern_type] do
      :system_failure ->
        [{:initiate_failover, %{}}, {:isolate_failure, %{}}]
        
      :security_breach ->
        [{:lockdown_system, %{}}, {:audit_all_access, %{}}]
        
      :cascade_failure ->
        [{:break_dependencies, %{}}, {:compartmentalize, %{}}]
        
      :algedonic_storm ->
        [{:dampen_signals, %{factor: 0.1}}, {:reset_algedonic, %{}}]
        
      _ ->
        []
    end
    
    base_actions ++ specific_actions
  end
  
  defp process_intervention_feedback(result, state) do
    # Learn from S3 intervention results
    pattern_id = result[:pattern_id]
    success = result[:success]
    
    # Update feedback loops
    new_feedback = update_feedback_learning(
      state.feedback_loops,
      :intervention_effectiveness,
      result
    )
    
    # Update metrics
    metric_type = if success, do: :successful_intervention, else: :failed_intervention
    new_metrics = update_metrics(state.metrics, metric_type)
    
    # Update alert status
    new_alerts = case Map.get(state.active_alerts, pattern_id) do
      nil -> state.active_alerts
      alert ->
        updated_alert = %{alert | 
          status: if(success, do: :resolved, else: :intervention_failed),
          interventions: [result | alert.interventions]
        }
        Map.put(state.active_alerts, pattern_id, updated_alert)
    end
    
    %{state |
      active_alerts: new_alerts,
      feedback_loops: new_feedback,
      metrics: new_metrics
    }
  end
  
  defp process_policy_feedback(update, state) do
    # Learn from S5 policy update results
    pattern_id = update[:pattern_id]
    impact = update[:system_impact]
    
    # Update feedback loops
    new_feedback = update_feedback_learning(
      state.feedback_loops,
      :policy_impact,
      update
    )
    
    # Update alert if it exists
    new_alerts = case Map.get(state.active_alerts, pattern_id) do
      nil -> state.active_alerts
      alert ->
        updated_alert = %{alert |
          policy_adjustments: [update | alert.policy_adjustments]
        }
        Map.put(state.active_alerts, pattern_id, updated_alert)
    end
    
    %{state |
      active_alerts: new_alerts,
      feedback_loops: new_feedback
    }
  end
  
  defp update_pattern_history(state, pattern_data) do
    new_history = :queue.in(pattern_data, state.pattern_history)
    
    # Trim if over limit
    new_history = if :queue.len(new_history) > @pattern_history_limit do
      :queue.drop(new_history)
    else
      new_history
    end
    
    %{state | pattern_history: new_history}
  end
  
  defp cleanup_old_data(state) do
    # Remove resolved alerts older than 1 hour
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)
    
    new_alerts = state.active_alerts
    |> Enum.filter(fn {_id, alert} ->
      alert.status == :active or
      DateTime.compare(alert.timestamp, cutoff) == :gt
    end)
    |> Enum.into(%{})
    
    %{state | active_alerts: new_alerts}
  end
  
  defp update_metrics(metrics, event_type) do
    base_updates = %{
      patterns_processed: metrics.patterns_processed + 1,
      last_alert_timestamp: DateTime.utc_now()
    }
    
    specific_updates = case event_type do
      :alert_generated ->
        %{alerts_generated: metrics.alerts_generated + 1}
        
      :s3_intervention ->
        %{s3_interventions: metrics.s3_interventions + 1}
        
      :s5_adjustment ->
        %{s5_adjustments: metrics.s5_adjustments + 1}
        
      :emergency_override ->
        %{emergency_overrides: metrics.emergency_overrides + 1,
          algedonic_bypasses: metrics.algedonic_bypasses + 1}
        
      :successful_intervention ->
        %{successful_interventions: metrics.successful_interventions + 1}
        
      :failed_intervention ->
        %{failed_interventions: metrics.failed_interventions + 1}
        
      _ ->
        %{}
    end
    
    Map.merge(metrics, Map.merge(base_updates, specific_updates))
  end
  
  defp update_feedback_learning(feedback_loops, loop_type, data) do
    # Simple learning update
    current = Map.get(feedback_loops, loop_type, %{})
    learning_rate = feedback_loops.learning_rate
    
    # Update based on feedback type
    updated = case loop_type do
      :intervention_effectiveness ->
        pattern_type = data[:pattern_type]
        success_rate = if data[:success], do: 1.0, else: 0.0
        current_rate = Map.get(current, pattern_type, 0.5)
        new_rate = current_rate + learning_rate * (success_rate - current_rate)
        Map.put(current, pattern_type, new_rate)
        
      :policy_impact ->
        policy_type = data[:policy_type]
        impact_score = data[:impact_score] || 0.5
        current_score = Map.get(current, policy_type, 0.5)
        new_score = current_score + learning_rate * (impact_score - current_score)
        Map.put(current, policy_type, new_score)
        
      _ ->
        current
    end
    
    Map.put(feedback_loops, loop_type, updated)
  end
  
  defp generate_alert_id(pattern_data) do
    # Generate unique alert ID
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    pattern_type = pattern_data[:pattern_type] || :unknown
    
    "alert_#{pattern_type}_#{timestamp}_#{:rand.uniform(1000)}"
  end
  
  defp execute_emergency_override(pattern_id, action, state) do
    case Map.get(state.active_alerts, pattern_id) do
      nil ->
        {:error, :alert_not_found}
        
      alert ->
        # Execute override action
        Logger.warning("⚡ Emergency override executed for #{pattern_id}: #{action}")
        
        # Update alert
        updated_alert = %{alert | 
          status: :overridden,
          interventions: [{:emergency_override, action, DateTime.utc_now()} | alert.interventions]
        }
        
        new_alerts = Map.put(state.active_alerts, pattern_id, updated_alert)
        new_metrics = update_metrics(state.metrics, :emergency_override)
        
        {:ok, %{state | active_alerts: new_alerts, metrics: new_metrics}}
    end
  end
  
  # Placeholder implementations for complex analysis
  defp assess_identity_impact(_pattern), do: :rand.uniform()
  defp check_value_alignment(_pattern), do: :rand.uniform()
  defp calculate_strategic_risk(_pattern), do: :rand.uniform()
  defp determine_adaptation_need(_pattern), do: :rand.uniform() > 0.5
end