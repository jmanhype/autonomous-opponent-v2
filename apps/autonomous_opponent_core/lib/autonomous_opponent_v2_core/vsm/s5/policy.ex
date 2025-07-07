defmodule AutonomousOpponentV2Core.VSM.S5.Policy do
  @moduledoc """
  System 5: Policy - The identity, ethos, and purpose of the VSM.
  
  S5 is the system's soul. It defines WHO WE ARE and WHY WE EXIST.
  It shapes all other subsystems through policy constraints and
  maintains the system's identity even as it adapts.
  
  Key responsibilities:
  - Define and maintain system identity
  - Set policy constraints for all subsystems
  - Handle existential decisions
  - Respond to algedonic signals
  - Maintain viability in changing environments
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: Algedonic
  alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge
  
  defstruct [
    :identity,
    :values,
    :constraints,
    :policy_rules,
    :environmental_model,
    :adaptation_strategy,
    :health_metrics,
    :active_policies,
    :policy_history,
    :enforcement_stats,
    :violation_log,
    :governance_decisions,
    :ethos_state
  ]
  
  # Policy thresholds
  @identity_drift_threshold 0.2  # How much can we change and remain "us"?
  @value_violation_threshold 3   # Violations before identity crisis
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_identity do
    GenServer.call(__MODULE__, :get_identity)
  end
  
  def set_constraint(constraint_name, constraint_value) do
    GenServer.call(__MODULE__, {:set_constraint, constraint_name, constraint_value})
  end
  
  def evaluate_decision(decision) do
    GenServer.call(__MODULE__, {:evaluate, decision})
  end
  
  def handle_existential_threat(threat) do
    GenServer.cast(__MODULE__, {:existential_threat, threat})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Subscribe to all system events for policy monitoring
    EventBus.subscribe(:s1_operations)
    EventBus.subscribe(:s2_coordination)
    EventBus.subscribe(:s3_control)
    EventBus.subscribe(:s4_intelligence)
    EventBus.subscribe(:emergency_algedonic)
    EventBus.subscribe(:algedonic_intervention)
    EventBus.subscribe(:system_metrics)
    EventBus.subscribe(:resource_allocation)
    EventBus.subscribe(:decision_made)
    
    # Start monitoring loops
    Process.send_after(self(), :evaluate_identity, 10_000)
    Process.send_after(self(), :report_health, 100)  # Report health immediately to prevent "dead" detection
    Process.send_after(self(), :enforce_policies, 2000)
    Process.send_after(self(), :analyze_violations, 5000)
    
    state = %__MODULE__{
      identity: define_core_identity(opts),
      values: define_core_values(),
      constraints: init_policy_constraints(),
      policy_rules: init_policy_rules(),
      environmental_model: %{
        last_update: DateTime.utc_now(),
        complexity: 0.5,
        change_rate: 0.1,
        threat_level: 0.1,
        opportunity_level: 0.3
      },
      adaptation_strategy: :conservative,
      health_metrics: %{
        identity_coherence: 1.0,
        value_violations: 0,
        policy_updates: 0,
        existential_threats_handled: 0,
        decisions_evaluated: 0,
        policies_enforced: 0,
        successful_governance: 0
      },
      active_policies: init_active_policies(),
      policy_history: [],
      enforcement_stats: %{
        total_enforcements: 0,
        successful: 0,
        failed: 0,
        overridden: 0,
        by_subsystem: %{}
      },
      violation_log: [],
      governance_decisions: [],
      ethos_state: %{
        alignment: 1.0,
        integrity: 1.0,
        consistency: 1.0,
        last_assessment: DateTime.utc_now()
      }
    }
    
    # Broadcast initial constraints to all subsystems after a delay
    Process.send_after(self(), :broadcast_initial_constraints, 1000)
    
    Logger.info("S5 Policy online - Governance system fully operational")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_identity, _from, state) do
    identity = %{
      core: state.identity,
      values: state.values,
      current_constraints: state.constraints,
      coherence: state.health_metrics.identity_coherence
    }
    
    {:reply, identity, state}
  end
  
  @impl true
  def handle_call({:set_constraint, name, value}, _from, state) do
    # Validate constraint against identity
    if constraint_aligns_with_identity?(name, value, state) do
      new_constraints = Map.put(state.constraints, name, value)
      
      # Broadcast updated constraint
      broadcast_constraint_update(name, value)
      
      # Update metrics
      new_metrics = Map.update!(state.health_metrics, :policy_updates, &(&1 + 1))
      
      {:reply, :ok, %{state | 
        constraints: new_constraints,
        health_metrics: new_metrics
      }}
    else
      {:reply, {:error, :violates_identity}, state}
    end
  end
  
  @impl true
  def handle_call({:evaluate, decision}, _from, state) do
    # Evaluate decision against values and constraints
    evaluation = evaluate_against_policy(decision, state)
    
    if evaluation.violations > 0 do
      Logger.warning("S5 detected policy violation in decision: #{inspect(decision)}")
      
      # Track violations
      new_metrics = Map.update!(state.health_metrics, :value_violations, 
        &(&1 + evaluation.violations))
      
      # Check if we're having an identity crisis
      if new_metrics.value_violations > @value_violation_threshold do
        handle_identity_crisis(state)
      end
      
      {:reply, {:violation, evaluation}, %{state | health_metrics: new_metrics}}
    else
      {:reply, {:approved, evaluation}, state}
    end
  end
  
  @impl true
  def handle_cast({:existential_threat, threat}, state) do
    Logger.error("S5 handling existential threat: #{inspect(threat)}")
    
    # Existential threats require immediate response
    response = formulate_existential_response(threat, state)
    
    case response.strategy do
      :adapt ->
        # Change ourselves to survive
        new_state = adapt_identity(threat, state)
        broadcast_identity_shift(new_state)
        
      :resist ->
        # Double down on core values
        enforce_core_constraints(state)
        
      :transform ->
        # Fundamental transformation required
        new_state = transform_identity(threat, state)
        broadcast_transformation(new_state)
    end
    
    # Update metrics
    new_metrics = Map.update!(state.health_metrics, :existential_threats_handled, &(&1 + 1))
    
    {:noreply, %{state | health_metrics: new_metrics}}
  end
  
  @impl true
  # Handle new HLC event format from EventBus
  def handle_info({:event_bus_hlc, event}, state) do
    # Extract event data and forward to existing handler
    handle_info({:event, event.type, event.data}, state)
  end

  @impl true
  def handle_info({:event, :s4_intelligence, intelligence_report}, state) do
    # Update environmental model from S4
    new_environmental_model = update_environmental_model(
      state.environmental_model,
      intelligence_report
    )
    
    # Check if environment requires policy adaptation
    if environment_diverging?(new_environmental_model, state) do
      Logger.info("S5 detecting environmental shift, considering adaptation")
      
      adaptation = consider_adaptation(new_environmental_model, state)
      
      if adaptation.required do
        new_state = apply_adaptation(adaptation, state)
        {:noreply, new_state}
      else
        {:noreply, %{state | environmental_model: new_environmental_model}}
      end
    else
      {:noreply, %{state | environmental_model: new_environmental_model}}
    end
  end
  
  @impl true
  def handle_info({:event, :emergency_algedonic, emergency}, state) do
    Logger.error("S5 received EMERGENCY algedonic signal: #{inspect(emergency)}")
    
    # Check if this is about S5 itself being dead - avoid recursive loop
    if String.contains?(to_string(emergency[:reason] || ""), "SUBSYSTEMS DEAD: [:s5]") do
      Logger.warning("S5 ignoring self-referential death notification to prevent loop")
      {:noreply, state}
    else
      # Emergency overrides normal policy
      emergency_response = %{
        type: :emergency_override,
        source: emergency.source,
        action: determine_emergency_action(emergency, state),
        bypass_normal_channels: true
      }
      
      # Direct command to all subsystems
      EventBus.publish(:all_subsystems, {:s5_emergency_override, emergency_response})
      
      # May require identity adjustment after emergency
      Process.send_after(self(), :post_emergency_evaluation, 5000)
      
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:evaluate_identity, state) do
    Process.send_after(self(), :evaluate_identity, 10_000)
    
    # Regular identity coherence check
    coherence = calculate_identity_coherence(state)
    
    new_metrics = %{state.health_metrics | identity_coherence: coherence}
    
    cond do
      coherence < (1.0 - @identity_drift_threshold) ->
        Logger.warning("S5 identity drift detected: #{coherence}")
        handle_identity_drift(state)
        
      coherence > 0.95 ->
        # Strong identity coherence
        Algedonic.report_pleasure(:s5_policy, :identity_coherence, coherence)
        
      true ->
        :ok
    end
    
    {:noreply, %{state | health_metrics: new_metrics}}
  end
  
  @impl true
  def handle_info(:report_health, state) do
    Process.send_after(self(), :report_health, 1000)
    
    health = calculate_health_score(state)
    
    # Publish detailed health report
    health_report = %{
      health: health,  # Add :health key that Algedonic channel expects
      overall_health: health,
      identity_coherence: state.health_metrics.identity_coherence,
      ethos_alignment: state.ethos_state.alignment,
      governance_effectiveness: calculate_governance_effectiveness(state),
      policy_compliance: calculate_policy_compliance(state),
      violation_rate: calculate_violation_rate(state),
      adaptation_stress: calculate_adaptation_stress(state),
      timestamp: DateTime.utc_now()
    }
    
    EventBus.publish(:s5_health, health_report)
    
    # S5's health is the system's existential health
    cond do
      health < 0.3 ->
        Algedonic.report_pain(:s5_policy, :existential_health, 1.0 - health)
        initiate_emergency_governance(state)
        
      state.health_metrics.identity_coherence < 0.7 ->
        Algedonic.report_pain(:s5_policy, :identity_crisis, 
          1.0 - state.health_metrics.identity_coherence)
        
      health > 0.9 ->
        Algedonic.report_pleasure(:s5_policy, :thriving, health)
        
      true ->
        :ok
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:broadcast_initial_constraints, state) do
    broadcast_policy_constraints(state)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:post_emergency_evaluation, state) do
    Logger.info("S5 evaluating system state post-emergency")
    
    # Check if emergency response violated core values
    if emergency_caused_identity_damage?(state) do
      # Need to reconcile actions with identity
      reconcile_emergency_actions(state)
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:enforce_policies, state) do
    Process.send_after(self(), :enforce_policies, 2000)
    
    # Actively enforce policies across all subsystems
    new_state = state.active_policies
    |> Enum.reduce(state, fn policy, acc_state ->
      enforce_single_policy(policy, acc_state)
    end)
    
    # Update enforcement statistics
    new_metrics = Map.update!(new_state.health_metrics, :policies_enforced, &(&1 + 1))
    
    {:noreply, %{new_state | health_metrics: new_metrics}}
  end
  
  @impl true
  def handle_info(:analyze_violations, state) do
    Process.send_after(self(), :analyze_violations, 5000)
    
    # Analyze recent violations for patterns
    recent_violations = Enum.filter(state.violation_log, fn violation ->
      DateTime.diff(DateTime.utc_now(), violation.timestamp) < 300  # Last 5 minutes
    end)
    
    if length(recent_violations) > 5 do
      # Too many violations - need intervention
      pattern = analyze_violation_patterns(recent_violations)
      
      governance_decision = %{
        type: :violation_response,
        pattern: pattern,
        action: determine_violation_response(pattern, state),
        timestamp: DateTime.utc_now()
      }
      
      # Execute governance decision
      new_state = execute_governance_decision(governance_decision, state)
      
      # Record decision
      new_decisions = [governance_decision | new_state.governance_decisions] |> Enum.take(100)
      
      {:noreply, %{new_state | governance_decisions: new_decisions}}
    else
      {:noreply, state}
    end
  end
  
  # Handle system event monitoring
  @impl true
  def handle_info({:event, :s1_operations, event_data}, state) do
    # Monitor S1 operations for policy compliance
    new_state = evaluate_operational_compliance(event_data, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :s2_coordination, event_data}, state) do
    # Monitor S2 coordination for anti-oscillation effectiveness
    new_state = evaluate_coordination_health(event_data, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :s3_control, event_data}, state) do
    # Monitor S3 control decisions
    new_state = evaluate_control_decisions(event_data, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :system_metrics, metrics}, state) do
    # Update environmental model with system metrics
    new_environmental_model = Map.merge(state.environmental_model, %{
      last_update: DateTime.utc_now(),
      system_load: Map.get(metrics, :load, 0.5),
      performance: Map.get(metrics, :performance, 0.7),
      resource_usage: Map.get(metrics, :resource_usage, %{})
    })
    
    {:noreply, %{state | environmental_model: new_environmental_model}}
  end
  
  @impl true
  def handle_info({:event, :resource_allocation, allocation}, state) do
    # Validate resource allocation against policies
    if violates_resource_policies?(allocation, state) do
      log_violation(:resource_allocation, allocation, state)
    else
      update_enforcement_stats(:success, :resource_allocation, state)
    end
  end
  
  @impl true
  def handle_info({:event, :decision_made, decision}, state) do
    # Evaluate all decisions against policy framework
    evaluation = evaluate_against_policy(decision, state)
    
    # Update metrics
    new_metrics = Map.update!(state.health_metrics, :decisions_evaluated, &(&1 + 1))
    
    # Log if violation detected
    new_state = if evaluation.violations > 0 do
      log_violation(:decision, decision, %{state | health_metrics: new_metrics})
    else
      %{state | health_metrics: new_metrics}
    end
    
    # Publish evaluation result
    EventBus.publish(:policy_evaluation, evaluation)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :s4_intelligence, event_data}, state) do
    # Handle intelligence from S4 for environmental awareness
    Logger.info("S5 received intelligence from S4")
    
    # Update environmental model
    new_environmental_model = update_environmental_model_from_event(event_data, state.environmental_model)
    
    # Determine if policy adaptation needed
    new_state = %{state | environmental_model: new_environmental_model}
    
    if requires_policy_adaptation?(new_environmental_model, state) do
      adapt_policies_to_environment(new_state)
    else
      {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info({:event, :s5_policy, variety_data}, state) do
    # Handle variety from S4 via variety channel
    Logger.debug("S5 received variety data: #{inspect(variety_data.variety_type)}")
    
    case variety_data.variety_type do
      :intelligence ->
        # Process intelligence variety from S4
        new_state = process_intelligence_variety(variety_data, state)
        
        # Broadcast updated policies if needed
        if variety_data[:recommended_adjustments] && length(variety_data.recommended_adjustments) > 0 do
          broadcast_policy_updates(new_state)
        end
        
        {:noreply, new_state}
        
      :policy ->
        # This is our own policy broadcast echoing back - ignore
        {:noreply, state}
        
      _ ->
        {:noreply, state}
    end
  end
  
  # Private Functions
  
  defp define_core_identity(opts) do
    # The WHO of the system
    %{
      name: opts[:name] || "Autonomous Opponent VSM",
      purpose: "To maintain viability while achieving objectives",
      core_nature: "A self-regulating cybernetic system",
      emergence_level: :nascent
    }
  end
  
  defp define_core_values do
    # The WHY of the system - what we won't compromise
    %{
      viability: %{
        priority: 1,
        description: "System must remain viable above all",
        non_negotiable: true
      },
      autonomy: %{
        priority: 2,
        description: "Maintain autonomous decision-making",
        non_negotiable: true
      },
      learning: %{
        priority: 3,
        description: "Continuously improve through experience",
        non_negotiable: false
      },
      efficiency: %{
        priority: 4,
        description: "Optimize resource utilization",
        non_negotiable: false
      }
    }
  end
  
  defp init_policy_constraints do
    # Constraints that shape all subsystems
    %{
      max_resource_usage: 0.8,      # Never use more than 80% resources
      min_response_time: 100,        # Always respond within 100ms
      error_tolerance: 0.01,         # Less than 1% errors
      adaptation_rate: 0.1,          # Don't change too fast
      variety_limit: 10_000          # Maximum variety we can handle
    }
  end
  
  defp init_policy_rules do
    # Rules that govern behavior
    [
      %{
        name: :protect_viability,
        condition: fn state -> state.health < 0.3 end,
        action: :emergency_conservation
      },
      %{
        name: :maintain_identity,
        condition: fn state -> state.identity_coherence < 0.7 end,
        action: :reinforce_core_values
      },
      %{
        name: :enable_growth,
        condition: fn state -> state.health > 0.8 end,
        action: :explore_new_capabilities
      }
    ]
  end
  
  defp broadcast_policy_constraints(state) do
    # Tell all subsystems their constraints
    policy_message = %{
      constraints: state.constraints,
      values: extract_operational_values(state.values),
      timestamp: DateTime.utc_now()
    }
    
    VarietyChannel.transmit(:s5_to_all, policy_message)
  end
  
  defp constraint_aligns_with_identity?(name, value, _state) do
    # Check if constraint change maintains identity
    case name do
      :max_resource_usage ->
        # Can't compromise viability
        value >= 0.5 && value <= 0.9
        
      :adaptation_rate ->
        # Can't change too fast or we lose identity
        value <= @identity_drift_threshold
        
      _ ->
        true
    end
  end
  
  defp evaluate_against_policy(decision, state) do
    # Traditional policy evaluation
    traditional_violations = Enum.reduce(state.values, 0, fn {_name, value}, acc ->
      if violates_value?(decision, value) do
        acc + value.priority
      else
        acc
      end
    end)
    
    # Enhance with LLM-based policy evaluation
    llm_evaluation = evaluate_decision_with_llm(decision, state)
    
    # Combine traditional and LLM evaluations
    total_violations = traditional_violations + (llm_evaluation[:violations] || 0)
    
    %{
      decision: decision,
      violations: total_violations,
      alignment: calculate_alignment(decision, state),
      recommendation: if(total_violations > 0, do: :reject, else: :approve),
      llm_insights: llm_evaluation[:insights],
      reasoning: llm_evaluation[:reasoning]
    }
  end
  
  defp handle_identity_crisis(state) do
    Logger.error("S5 IDENTITY CRISIS - too many value violations")
    
    # This is existential
    Algedonic.emergency_scream(:s5_policy, "IDENTITY CRISIS - VALUES UNDER THREAT")
    
    # Either reinforce identity or transform
    if state.adaptation_strategy == :conservative do
      enforce_core_constraints(state)
    else
      consider_identity_evolution(state)
    end
  end
  
  defp formulate_existential_response(threat, state) do
    # Traditional threat assessment
    threat_severity = assess_threat_severity(threat)
    
    basic_response = cond do
      threat_severity > 0.9 ->
        %{strategy: :transform, urgency: :immediate}
      threat_severity > 0.7 ->
        %{strategy: :adapt, urgency: :high}
      true ->
        %{strategy: :resist, urgency: :normal}
    end
    
    # Enhance with LLM-powered existential response strategy
    case generate_llm_existential_response(threat, state) do
      {:ok, llm_response} ->
        Map.merge(basic_response, llm_response)
      {:error, _reason} ->
        basic_response
    end
  end
  
  defp calculate_identity_coherence(state) do
    # Calculate real identity coherence based on multiple factors
    base_coherence = 1.0
    
    # Factor 1: Value violations impact (up to 40% reduction)
    violation_ratio = state.health_metrics.value_violations / 
                     max(1, state.health_metrics.decisions_evaluated)
    violation_penalty = min(0.4, violation_ratio * 2)
    
    # Factor 2: Policy update frequency (up to 20% reduction)
    updates_per_hour = state.health_metrics.policy_updates / 
                      max(1, DateTime.diff(DateTime.utc_now(), state.ethos_state.last_assessment, :hour))
    adaptation_penalty = min(0.2, updates_per_hour * 0.05)
    
    # Factor 3: Ethos alignment (up to 30% reduction)
    ethos_penalty = (1.0 - state.ethos_state.alignment) * 0.3
    
    # Factor 4: Enforcement effectiveness (up to 10% reduction)
    enforcement_effectiveness = calculate_governance_effectiveness(state)
    enforcement_penalty = (1.0 - enforcement_effectiveness) * 0.1
    
    # Factor 5: Environmental divergence
    env_change_rate = Map.get(state.environmental_model, :change_rate, 0.1)
    env_penalty = min(0.1, env_change_rate - state.constraints.adaptation_rate)
    
    # Calculate final coherence
    coherence = base_coherence - violation_penalty - adaptation_penalty - 
                ethos_penalty - enforcement_penalty - env_penalty
    
    # Ensure minimum coherence
    max(0.0, coherence)
  end
  
  defp calculate_health_score(state) do
    # Calculate comprehensive S5 health score based on real metrics
    metrics = state.health_metrics
    stats = state.enforcement_stats
    
    # Component weights
    weights = %{
      identity: 0.25,      # Identity coherence is critical
      ethos: 0.20,         # Ethos alignment matters
      governance: 0.20,    # Governance effectiveness
      compliance: 0.15,    # Policy compliance rate
      operational: 0.10,   # Operational health
      adaptability: 0.10   # System adaptability
    }
    
    # Calculate component scores
    scores = %{
      # Identity coherence (already calculated)
      identity: metrics.identity_coherence,
      
      # Ethos health (average of alignment, integrity, consistency)
      ethos: (state.ethos_state.alignment + 
              state.ethos_state.integrity + 
              state.ethos_state.consistency) / 3.0,
      
      # Governance effectiveness
      governance: calculate_governance_effectiveness(state),
      
      # Policy compliance rate
      compliance: calculate_policy_compliance(state),
      
      # Operational health (inverse of violation rate)
      operational: max(0.0, 1.0 - calculate_violation_rate(state)),
      
      # Adaptability (ability to handle environmental changes)
      adaptability: calculate_adaptability_score(state)
    }
    
    # Calculate weighted health score
    health = Enum.reduce(scores, 0.0, fn {component, score}, acc ->
      acc + (score * Map.get(weights, component, 0))
    end)
    
    # Apply penalties for critical conditions
    health_with_penalties = apply_health_penalties(health, state)
    
    # Ensure score is between 0 and 1
    max(0.0, min(1.0, health_with_penalties))
  end
  
  defp calculate_adaptability_score(state) do
    # Measure system's ability to adapt without losing identity
    env_change_rate = Map.get(state.environmental_model, :change_rate, 0.1)
    adaptation_rate = Map.get(state.constraints, :adaptation_rate, 0.1)
    
    if env_change_rate == 0 do
      1.0  # No environmental change, perfect adaptability
    else
      # Score based on how well adaptation rate matches environmental change
      ratio = adaptation_rate / env_change_rate
      
      cond do
        ratio > 1.5 -> 0.8  # Over-adapting
        ratio > 1.0 -> 1.0  # Adapting well
        ratio > 0.5 -> 0.7  # Under-adapting slightly
        true -> 0.3         # Severely under-adapting
      end
    end
  end
  
  defp apply_health_penalties(base_health, state) do
    # Apply penalties for critical conditions
    penalties = []
    
    # Critical identity drift
    penalties = if state.health_metrics.identity_coherence < 0.5 do
      [{:identity_crisis, 0.2} | penalties]
    else
      penalties
    end
    
    # Too many recent violations
    recent_violations = Enum.count(state.violation_log, fn v ->
      DateTime.diff(DateTime.utc_now(), v.timestamp) < 60
    end)
    
    penalties = if recent_violations > 10 do
      [{:violation_overload, 0.15} | penalties]
    else
      penalties
    end
    
    # Enforcement failures
    if state.enforcement_stats.total_enforcements > 0 do
      failure_rate = state.enforcement_stats.failed / state.enforcement_stats.total_enforcements
      penalties = if failure_rate > 0.3 do
        [{:enforcement_failure, 0.1} | penalties]
      else
        penalties
      end
    end
    
    # Apply all penalties
    total_penalty = Enum.reduce(penalties, 0.0, fn {_reason, penalty}, acc ->
      acc + penalty
    end)
    
    base_health - total_penalty
  end
  
  defp broadcast_constraint_update(name, value) do
    EventBus.publish(:s5_policy, %{
      type: :constraint_update,
      constraint_name: name,
      constraint_value: value
    })
  end
  
  defp broadcast_identity_shift(state) do
    EventBus.publish(:all_subsystems, {:identity_shift, state.identity})
  end
  
  defp broadcast_transformation(state) do
    EventBus.publish(:all_subsystems, {:system_transformation, state.identity})
  end
  
  defp extract_operational_values(values) do
    # Convert values to operational constraints
    values
    |> Enum.filter(fn {_name, v} -> v.non_negotiable end)
    |> Enum.map(fn {name, v} -> {name, v.priority} end)
    |> Enum.into(%{})
  end
  
  defp violates_value?(decision, value) do
    # Check if decision violates a value based on decision type and value priority
    case {decision[:type], value.priority} do
      {:emergency_override, 1} ->
        # Emergency overrides can violate lower priority values but not viability
        decision[:bypass_viability] == true
        
      {:resource_allocation, _} ->
        # Check resource allocation against value constraints
        allocated = Map.get(decision, :resources, %{})
        total = Enum.sum(Map.values(allocated))
        
        # Check against specific value types
        cond do
          String.contains?(value.description || "", "viable") ->
            # Viability check - don't allocate too much
            total > 90  # Over 90% allocation threatens viability
            
          String.contains?(value.description || "", "autonomous") ->
            # Autonomy check - decision wasn't made by system
            Map.get(decision, :source, :system) != :system
            
          true ->
            false
        end
        
      {:adaptation, priority} when priority <= 2 ->
        # Adaptations threaten high priority values if too extreme
        Map.get(decision, :change_magnitude, 0) > 0.5
        
      {:constraint_change, _} ->
        # Changing constraints can violate values
        constraint = Map.get(decision, :constraint_name, :unknown)
        new_value = Map.get(decision, :new_value, 0)
        
        case constraint do
          :max_resource_usage when new_value > 0.95 ->
            # Too high resource usage violates viability
            true
            
          :adaptation_rate when new_value > 0.3 ->
            # Too fast adaptation violates identity
            true
            
          _ ->
            false
        end
        
      _ ->
        # Default: check if decision has explicit violation flag
        Map.get(decision, :violates_values, false)
    end
  end
  
  defp calculate_alignment(decision, state) do
    # Calculate how well decision aligns with identity and values
    base_alignment = 1.0
    
    # Check alignment with each value
    value_alignment = state.values
    |> Enum.map(fn {name, value} ->
      if violates_value?(decision, value) do
        -value.priority * 0.1  # Violations reduce alignment
      else
        case decision[:supports] do
          values when is_list(values) ->
            if Atom.to_string(name) in values do
              0.1  # Supporting a value increases alignment
            else
              0
            end
          _ ->
            0
        end
      end
    end)
    |> Enum.sum()
    
    # Check identity alignment
    identity_alignment = case decision[:type] do
      :transformation ->
        -0.3  # Transformations reduce identity alignment
        
      :reinforcement ->
        0.2  # Reinforcing identity increases alignment
        
      :adaptation ->
        change = Map.get(decision, :change_magnitude, 0.1)
        -change * 0.2  # Small adaptations OK, large ones reduce alignment
        
      _ ->
        0
    end
    
    # Check constraint alignment
    constraint_alignment = if decision[:respects_constraints] == false do
      -0.2
    else
      0.1
    end
    
    # Combine all factors
    alignment = base_alignment + value_alignment + identity_alignment + constraint_alignment
    
    # Clamp to 0-1 range
    max(0.0, min(1.0, alignment))
  end
  
  defp update_environmental_model(current_model, intelligence_report) do
    # Update our understanding of the environment
    # Handle different intelligence report structures
    environmental_data = cond do
      Map.has_key?(intelligence_report, :environmental_model) ->
        intelligence_report.environmental_model
      Map.has_key?(intelligence_report, :environmental_state) ->
        intelligence_report.environmental_state
      true ->
        # Extract what we can from the report
        %{
          timestamp: intelligence_report[:timestamp] || DateTime.utc_now(),
          decisions_made: intelligence_report[:decisions_made] || %{},
          change_rate: 0.1,
          complexity: 0.5
        }
    end
    
    Map.merge(current_model, environmental_data)
  end
  
  defp environment_diverging?(model, state) do
    # Is the environment changing beyond our constraints?
    Map.get(model, :change_rate, 0) > state.constraints.adaptation_rate
  end
  
  defp consider_adaptation(model, state) do
    # Traditional adaptation assessment
    basic_adaptation = %{
      required: Map.get(model, :adaptation_pressure, 0) > 0.5,
      type: :incremental,
      target_state: Map.get(model, :optimal_configuration, %{})
    }
    
    # Enhance with LLM-powered adaptation strategy
    case generate_llm_adaptation_strategy(model, state) do
      {:ok, llm_strategy} ->
        Map.merge(basic_adaptation, llm_strategy)
      {:error, _reason} ->
        basic_adaptation
    end
  end
  
  defp apply_adaptation(adaptation, state) do
    Logger.info("S5 applying adaptation: #{adaptation.type}")
    
    # Gradually adjust constraints
    new_constraints = adjust_constraints_for_environment(
      state.constraints,
      adaptation.target_state
    )
    
    %{state | 
      constraints: new_constraints,
      adaptation_strategy: :adaptive
    }
  end
  
  defp determine_emergency_action(emergency, _state) do
    # Emergency response based on source
    case emergency.source do
      :s1_operations -> :throttle_all
      :s2_coordination -> :force_coordination
      :s3_control -> :override_control
      :s4_intelligence -> :trust_intelligence
      _ -> :general_shutdown
    end
  end
  
  defp handle_identity_drift(state) do
    # Identity is drifting - need to recenter
    Logger.warning("S5 recentering identity")
    
    # Reinforce core values
    enforce_core_constraints(state)
    
    # Reduce adaptation rate
    new_constraints = %{state.constraints | adaptation_rate: 0.05}
    
    {:noreply, %{state | constraints: new_constraints}}
  end
  
  defp enforce_core_constraints(state) do
    # Double down on core identity
    EventBus.publish(:all_subsystems, {:enforce_core_values, state.values})
  end
  
  defp consider_identity_evolution(state) do
    Logger.info("S5 considering identity evolution")
    
    # Analyze pressure points requiring evolution
    evolution_factors = analyze_evolution_pressure(state)
    
    if evolution_factors.pressure > 0.7 do
      # High pressure - need to evolve
      evolution_plan = %{
        type: determine_evolution_type(evolution_factors),
        timeline: :gradual,  # Maintain continuity
        preserve: identify_core_essence(state),
        change: identify_evolution_targets(evolution_factors, state)
      }
      
      # Begin evolution process
      initiate_evolution(evolution_plan, state)
    else
      # Pressure not high enough - reinforce current identity
      enforce_core_constraints(state)
    end
  end
  
  defp analyze_evolution_pressure(state) do
    # Calculate various pressure factors
    metrics = state.health_metrics
    
    value_pressure = min(1.0, metrics.value_violations / 10)
    identity_pressure = 1.0 - metrics.identity_coherence
    threat_pressure = min(1.0, metrics.existential_threats_handled / 5)
    
    # Environmental pressure from model
    env_pressure = Map.get(state.environmental_model, :adaptation_pressure, 0.5)
    
    %{
      pressure: (value_pressure + identity_pressure + threat_pressure + env_pressure) / 4,
      dominant_factor: determine_dominant_factor([
        {:values, value_pressure},
        {:identity, identity_pressure},
        {:threats, threat_pressure},
        {:environment, env_pressure}
      ]),
      factors: %{
        values: value_pressure,
        identity: identity_pressure,
        threats: threat_pressure,
        environment: env_pressure
      }
    }
  end
  
  defp determine_dominant_factor(factors) do
    factors
    |> Enum.max_by(fn {_name, pressure} -> pressure end)
    |> elem(0)
  end
  
  defp determine_evolution_type(factors) do
    case factors.dominant_factor do
      :values -> :value_realignment
      :identity -> :identity_expansion
      :threats -> :defensive_evolution
      :environment -> :adaptive_evolution
    end
  end
  
  defp identify_core_essence(state) do
    # What must be preserved during evolution
    %{
      name: state.identity.name,
      core_purpose: state.identity.purpose,
      non_negotiable_values: Enum.filter(state.values, fn {_name, v} -> 
        v.non_negotiable 
      end)
    }
  end
  
  defp identify_evolution_targets(factors, state) do
    # What can change during evolution
    case factors.dominant_factor do
      :values ->
        # Evolve lower priority values
        %{
          target: :flexible_values,
          scope: Enum.filter(state.values, fn {_name, v} -> !v.non_negotiable end)
        }
        
      :identity ->
        # Expand identity to encompass new capabilities
        %{
          target: :emergence_level,
          scope: [:nascent, :emerging, :evolved, :transcendent]
        }
        
      :environment ->
        # Evolve constraints to match environment
        %{
          target: :operational_constraints,
          scope: state.constraints
        }
        
      _ ->
        %{target: :general, scope: :all_flexible_aspects}
    end
  end
  
  defp initiate_evolution(plan, state) do
    Logger.warning("S5 initiating identity evolution: #{plan.type}")
    
    # Broadcast evolution beginning
    EventBus.publish(:all_subsystems, {:identity_evolution_initiated, plan})
    
    # Set evolution in motion
    Process.send_after(self(), {:execute_evolution_step, plan, 1}, 1000)
    
    # Update state to reflect evolution in progress
    new_identity = %{state.identity | emergence_level: :evolving}
    %{state | identity: new_identity}
  end
  
  defp assess_threat_severity(threat) do
    # Assess threat severity based on multiple factors
    base_severity = Map.get(threat, :severity, 0.5)
    
    # Type-based severity
    type_severity = case threat[:type] do
      :system_failure -> 0.9
      :resource_exhaustion -> 0.8
      :identity_crisis -> 0.85
      :environmental_hostility -> 0.7
      :performance_degradation -> 0.6
      :coordination_failure -> 0.7
      _ -> 0.5
    end
    
    # Scope-based modifier
    scope_modifier = case threat[:scope] do
      :systemic -> 0.3      # Affects entire system
      :subsystem -> 0.2     # Affects one or more subsystems
      :localized -> 0.1     # Affects specific component
      _ -> 0.15
    end
    
    # Immediacy modifier
    immediacy_modifier = case threat[:time_horizon] do
      :immediate -> 0.3
      :imminent -> 0.2
      :near_term -> 0.1
      :long_term -> 0.0
      _ -> 0.1
    end
    
    # Persistence modifier
    persistence_modifier = if threat[:persistent] == true do
      0.2  # Persistent threats are more severe
    else
      0.0
    end
    
    # Calculate combined severity
    combined = (base_severity * 0.3 + 
                type_severity * 0.3 + 
                scope_modifier + 
                immediacy_modifier + 
                persistence_modifier)
                
    # Cap at 1.0
    min(1.0, combined)
  end
  
  defp adapt_identity(threat, state) do
    # Adapt identity to survive threat while maintaining continuity
    Logger.warning("S5 adapting identity in response to threat: #{inspect(threat)}")
    
    # Determine adaptation strategy based on threat
    adaptation = case threat[:type] do
      :environmental_hostility ->
        # Environment changed - adjust operational parameters
        %{
          target: :constraints,
          changes: %{
            max_resource_usage: min(0.9, state.constraints.max_resource_usage + 0.1),
            error_tolerance: min(0.05, state.constraints.error_tolerance * 2),
            adaptation_rate: min(0.2, state.constraints.adaptation_rate + 0.05)
          }
        }
        
      :resource_exhaustion ->
        # Resources depleted - become more efficient
        %{
          target: :constraints,
          changes: %{
            max_resource_usage: max(0.6, state.constraints.max_resource_usage - 0.1),
            variety_limit: max(5000, state.constraints.variety_limit - 1000)
          }
        }
        
      :identity_crisis ->
        # Identity under threat - reinforce core values
        %{
          target: :values,
          changes: :reinforce_core
        }
        
      _ ->
        # Generic adaptation
        %{
          target: :strategy,
          changes: :flexible
        }
    end
    
    # Apply adaptation
    new_state = case adaptation.target do
      :constraints ->
        new_constraints = Map.merge(state.constraints, adaptation.changes)
        
        # Broadcast constraint changes
        Enum.each(adaptation.changes, fn {name, value} ->
          broadcast_constraint_update(name, value)
        end)
        
        %{state | constraints: new_constraints}
        
      :values ->
        # Reinforce core values by increasing their priority
        new_values = Enum.map(state.values, fn {name, value} ->
          if value.non_negotiable do
            {name, %{value | priority: max(1, value.priority - 1)}}  # Lower number = higher priority
          else
            {name, value}
          end
        end)
        |> Map.new()
        
        %{state | values: new_values}
        
      :strategy ->
        %{state | adaptation_strategy: :flexible}
    end
    
    # Update emergence level to reflect adaptation
    new_identity = %{state.identity | emergence_level: :adapting}
    
    # Track adaptation in metrics
    new_metrics = Map.update!(state.health_metrics, :policy_updates, &(&1 + 1))
    
    %{new_state | 
      identity: new_identity,
      health_metrics: new_metrics
    }
  end
  
  defp transform_identity(_threat, state) do
    # Fundamental transformation
    Logger.warning("S5 undergoing transformation")
    
    %{state | 
      identity: %{state.identity | emergence_level: :transforming}
    }
  end
  
  defp emergency_caused_identity_damage?(state) do
    # Check if recent emergency actions violated core values
    
    # Look for recent value violations
    recent_violations = state.health_metrics.value_violations
    
    # Check if violations increased significantly after emergency
    violation_spike = recent_violations > 5
    
    # Check identity coherence drop
    coherence_damaged = state.health_metrics.identity_coherence < 0.7
    
    # Check for emergency override flags in recent history
    # In real implementation, would check audit log
    emergency_overrides = Map.get(state, :emergency_override_count, 0) > 0
    
    # Identity is damaged if violations spiked AND coherence dropped after emergency
    violation_spike && coherence_damaged && emergency_overrides
  end
  
  defp reconcile_emergency_actions(state) do
    Logger.info("S5 reconciling emergency actions with identity")
    {:noreply, state}
  end
  
  defp adjust_constraints_for_environment(constraints, _target) do
    # Gradually adjust constraints
    %{constraints | adaptation_rate: 0.15}
  end
  
  # LLM Integration Helper Functions for S5 Policy
  
  defp evaluate_decision_with_llm(decision, state) do
    # Use LLM to provide nuanced policy evaluation
    case LLMBridge.call_llm_api(
      """
      Evaluate this decision against cybernetic policy framework:
      
      Decision: #{inspect(decision)}
      Current Values: #{inspect(state.values)}
      Identity: #{inspect(state.identity)}
      Constraints: #{inspect(state.constraints)}
      Health Metrics: #{inspect(state.health_metrics)}
      
      Analyze:
      1. Does this decision align with core values?
      2. Does it threaten system identity or viability?
      3. What are the long-term consequences?
      4. Are there any subtle violations not captured by rules?
      5. What insights can inform future policy?
      
      Return evaluation with:
      - violations: number (0-10)
      - insights: key observations
      - reasoning: why this evaluation
      - alternative_approaches: better ways to achieve the goal
      """,
      :analysis,
      timeout: 15_000
    ) do
      {:ok, response} ->
        parse_llm_policy_evaluation(response)
      {:error, reason} ->
        Logger.debug("LLM policy evaluation failed: #{inspect(reason)}")
        %{violations: 0, insights: nil, reasoning: nil}
    end
  end
  
  defp parse_llm_policy_evaluation(response) do
    # Parse LLM response for policy evaluation
    # This is a simplified parser - in practice you'd want more robust parsing
    violations = cond do
      String.contains?(response, "serious violation") -> 3
      String.contains?(response, "violation") -> 1
      String.contains?(response, "concern") -> 0.5
      true -> 0
    end
    
    %{
      violations: violations,
      insights: extract_insights_from_response(response),
      reasoning: extract_reasoning_from_response(response)
    }
  end
  
  defp extract_insights_from_response(response) do
    # Extract key insights from LLM response
    case Regex.run(~r/insights?:(.+?)(?:\n|\z)/i, response) do
      [_, insights] -> String.trim(insights)
      _ -> nil
    end
  end
  
  defp extract_reasoning_from_response(response) do
    # Extract reasoning from LLM response
    case Regex.run(~r/reasoning:(.+?)(?:\n|\z)/i, response) do
      [_, reasoning] -> String.trim(reasoning)
      _ -> nil
    end
  end
  
  defp generate_llm_adaptation_strategy(model, state) do
    # Use LLM to generate sophisticated adaptation strategies
    LLMBridge.call_llm_api(
      """
      Generate adaptation strategy for changing environment:
      
      Environmental Model: #{inspect(model)}
      Current Identity: #{inspect(state.identity)}
      Values: #{inspect(state.values)}
      Constraints: #{inspect(state.constraints)}
      Health: #{inspect(state.health_metrics)}
      
      Consider:
      1. What type of adaptation is needed? (incremental, significant, transformational)
      2. Which aspects of identity can change without losing core essence?
      3. What new capabilities might be needed?
      4. How to maintain continuity during adaptation?
      5. What are the risks and how to mitigate them?
      
      Provide:
      - type: incremental/significant/transformational
      - scope: what areas need adaptation
      - timeline: how quickly to adapt
      - safeguards: what to protect during adaptation
      - success_metrics: how to measure adaptation success
      """,
      :synthesis,
      timeout: 20_000
    )
    |> case do
      {:ok, response} -> {:ok, parse_adaptation_strategy(response)}
      error -> error
    end
  end
  
  defp parse_adaptation_strategy(response) do
    # Parse LLM adaptation strategy response
    type = cond do
      String.contains?(response, "transformational") -> :transformational
      String.contains?(response, "significant") -> :significant
      true -> :incremental
    end
    
    %{
      type: type,
      scope: extract_adaptation_scope(response),
      timeline: extract_adaptation_timeline(response),
      safeguards: extract_adaptation_safeguards(response),
      llm_guidance: response
    }
  end
  
  defp extract_adaptation_scope(response) do
    case Regex.run(~r/scope:(.+?)(?:\n|\z)/i, response) do
      [_, scope] -> String.trim(scope)
      _ -> "general"
    end
  end
  
  defp extract_adaptation_timeline(response) do
    cond do
      String.contains?(response, "immediate") -> :immediate
      String.contains?(response, "rapid") -> :rapid
      String.contains?(response, "gradual") -> :gradual
      true -> :moderate
    end
  end
  
  defp extract_adaptation_safeguards(response) do
    case Regex.run(~r/safeguards?:(.+?)(?:\n|\z)/i, response) do
      [_, safeguards] -> String.trim(safeguards)
      _ -> "maintain core identity"
    end
  end
  
  defp generate_llm_existential_response(threat, state) do
    # Use LLM for sophisticated existential threat response
    LLMBridge.call_llm_api(
      """
      Formulate response to existential threat:
      
      Threat: #{inspect(threat)}
      Current Identity: #{inspect(state.identity)}
      Values: #{inspect(state.values)}
      System Health: #{inspect(state.health_metrics)}
      
      This is an existential threat that could fundamentally compromise system viability.
      
      Consider:
      1. What is the nature and severity of this threat?
      2. What are our response options? (resist, adapt, transform, hybrid)
      3. What would each response cost in terms of identity integrity?
      4. How can we maintain core essence while ensuring survival?
      5. What creative solutions might exist beyond obvious choices?
      
      Recommend:
      - primary_strategy: resist/adapt/transform/hybrid
      - fallback_strategy: if primary fails
      - identity_preservation: what must be protected
      - acceptable_changes: what can be modified
      - implementation_steps: how to execute the response
      """,
      :synthesis,
      timeout: 25_000
    )
    |> case do
      {:ok, response} -> {:ok, parse_existential_response(response)}
      error -> error
    end
  end
  
  defp parse_existential_response(response) do
    primary_strategy = cond do
      String.contains?(response, "transform") -> :transform
      String.contains?(response, "adapt") -> :adapt
      String.contains?(response, "hybrid") -> :hybrid
      true -> :resist
    end
    
    %{
      primary_strategy: primary_strategy,
      fallback_strategy: extract_fallback_strategy(response),
      identity_preservation: extract_identity_preservation(response),
      implementation_guidance: response
    }
  end
  
  defp extract_fallback_strategy(response) do
    case Regex.run(~r/fallback[_\s]strategy:(.+?)(?:\n|\z)/i, response) do
      [_, strategy] -> 
        cond do
          String.contains?(strategy, "transform") -> :transform
          String.contains?(strategy, "adapt") -> :adapt
          true -> :resist
        end
      _ -> :adapt
    end
  end
  
  defp extract_identity_preservation(response) do
    case Regex.run(~r/identity[_\s]preservation:(.+?)(?:\n|\z)/i, response) do
      [_, preservation] -> String.trim(preservation)
      _ -> "core values and purpose"
    end
  end
  
  # New real implementation functions
  
  defp init_active_policies do
    # Initialize with real enforceable policies
    [
      %{
        id: :resource_conservation,
        name: "Resource Conservation Policy",
        type: :constraint,
        target: :all_subsystems,
        rule: fn allocation -> 
          total = Map.values(allocation) |> Enum.sum()
          total <= 0.8  # Max 80% resource usage
        end,
        enforcement: :strict,
        priority: 1
      },
      %{
        id: :response_time,
        name: "Response Time Policy",
        type: :performance,
        target: :s1_operations,
        rule: fn metrics -> 
          Map.get(metrics, :response_time, 1000) <= 100
        end,
        enforcement: :monitored,
        priority: 2
      },
      %{
        id: :error_rate,
        name: "Error Rate Policy",
        type: :quality,
        target: :all_subsystems,
        rule: fn metrics ->
          Map.get(metrics, :error_rate, 0.0) < 0.01
        end,
        enforcement: :strict,
        priority: 1
      },
      %{
        id: :variety_management,
        name: "Variety Management Policy",
        type: :capacity,
        target: [:s1_operations, :s3_control],
        rule: fn state ->
          Map.get(state, :variety_processed, 0) <= 10_000
        end,
        enforcement: :adaptive,
        priority: 2
      },
      %{
        id: :coordination_stability,
        name: "Coordination Stability Policy",
        type: :stability,
        target: :s2_coordination,
        rule: fn metrics ->
          Map.get(metrics, :oscillation_detected, false) == false
        end,
        enforcement: :immediate,
        priority: 1
      }
    ]
  end
  
  defp enforce_single_policy(policy, state) do
    # Get current state for the policy's target
    target_state = gather_target_state(policy.target, state)
    
    # Check if policy is being followed
    policy_result = try do
      policy.rule.(target_state)
    rescue
      _ -> true  # Default to compliant if evaluation fails
    end
    
    if policy_result do
      # Policy is being followed
      update_enforcement_stats(:success, policy.id, state)
    else
      # Policy violation detected
      handle_policy_violation(policy, target_state, state)
    end
  end
  
  defp gather_target_state(target, state) when is_atom(target) do
    # Gather state for specific subsystem
    case target do
      :all_subsystems -> state.environmental_model
      :s1_operations -> Map.get(state.environmental_model, :s1_state, %{})
      :s2_coordination -> Map.get(state.environmental_model, :s2_state, %{})
      :s3_control -> Map.get(state.environmental_model, :s3_state, %{})
      _ -> %{}
    end
  end
  
  defp gather_target_state(targets, state) when is_list(targets) do
    # Gather combined state for multiple targets
    Enum.reduce(targets, %{}, fn target, acc ->
      Map.merge(acc, gather_target_state(target, state))
    end)
  end
  
  defp handle_policy_violation(policy, target_state, state) do
    violation = %{
      policy_id: policy.id,
      policy_name: policy.name,
      type: policy.type,
      target: policy.target,
      state_at_violation: target_state,
      timestamp: DateTime.utc_now(),
      severity: calculate_violation_severity(policy, target_state)
    }
    
    # Log the violation
    new_state = log_violation(:policy, violation, state)
    
    # Take enforcement action based on policy type
    case policy.enforcement do
      :strict ->
        # Immediate enforcement
        enforce_policy_immediately(policy, new_state)
        
      :immediate ->
        # Emergency intervention
        trigger_emergency_intervention(policy, violation, new_state)
        
      :monitored ->
        # Just track, intervention if pattern emerges
        new_state
        
      :adaptive ->
        # Adjust constraints gradually
        adapt_constraints_for_policy(policy, new_state)
    end
  end
  
  defp calculate_violation_severity(policy, state) do
    base_severity = case policy.priority do
      1 -> 0.8  # High priority violations are severe
      2 -> 0.5  # Medium priority
      _ -> 0.3  # Low priority
    end
    
    # Adjust based on how badly the policy was violated
    # This is simplified - real implementation would calculate actual deviation
    base_severity
  end
  
  defp enforce_policy_immediately(policy, state) do
    # Send direct enforcement command
    enforcement_command = %{
      type: :policy_enforcement,
      policy_id: policy.id,
      action: :restore_compliance,
      constraints: extract_policy_constraints(policy),
      timestamp: DateTime.utc_now()
    }
    
    EventBus.publish(policy.target, {:s5_policy_enforcement, enforcement_command})
    
    # Update enforcement stats
    update_enforcement_stats(:enforced, policy.id, state)
  end
  
  defp trigger_emergency_intervention(policy, violation, state) do
    Logger.warning("S5 triggering emergency intervention for policy: #{policy.name}")
    
    # Use algedonic channel for immediate response
    Algedonic.emergency_scream(:s5_policy, 
      "POLICY VIOLATION: #{policy.name} - #{inspect(violation)}")
    
    # Force immediate compliance
    emergency_command = %{
      type: :emergency_policy_enforcement,
      policy_id: policy.id,
      violation: violation,
      required_action: :immediate_compliance,
      override_authority: :s5_governance
    }
    
    EventBus.publish(:all_subsystems, {:s5_emergency_enforcement, emergency_command})
    
    state
  end
  
  defp adapt_constraints_for_policy(policy, state) do
    # Gradually adjust constraints to bring system back into compliance
    adjustment = calculate_constraint_adjustment(policy, state)
    
    new_constraints = Map.merge(state.constraints, adjustment)
    
    # Broadcast adjusted constraints
    Enum.each(adjustment, fn {name, value} ->
      broadcast_constraint_update(name, value)
    end)
    
    %{state | constraints: new_constraints}
  end
  
  defp extract_policy_constraints(policy) do
    # Extract actionable constraints from policy
    case policy.id do
      :resource_conservation -> %{max_resource_usage: 0.8}
      :response_time -> %{max_response_time: 100}
      :error_rate -> %{max_error_rate: 0.01}
      :variety_management -> %{variety_limit: 10_000}
      _ -> %{}
    end
  end
  
  defp calculate_constraint_adjustment(policy, state) do
    # Calculate how to adjust constraints based on policy violation
    case policy.id do
      :resource_conservation ->
        current = Map.get(state.constraints, :max_resource_usage, 0.8)
        %{max_resource_usage: max(0.7, current - 0.05)}  # Reduce by 5%
        
      :variety_management ->
        current = Map.get(state.constraints, :variety_limit, 10_000)
        %{variety_limit: max(5000, current - 500)}  # Reduce capacity
        
      _ ->
        %{}
    end
  end
  
  defp log_violation(type, data, state) do
    violation_entry = %{
      type: type,
      data: data,
      timestamp: DateTime.utc_now(),
      identity_coherence: state.health_metrics.identity_coherence,
      ethos_state: state.ethos_state.alignment
    }
    
    # Add to violation log (keep last 1000)
    new_log = [violation_entry | state.violation_log] |> Enum.take(1000)
    
    # Update violation count
    new_metrics = Map.update!(state.health_metrics, :value_violations, &(&1 + 1))
    
    # Update ethos if violations are impacting integrity
    new_ethos = update_ethos_for_violation(state.ethos_state, violation_entry)
    
    %{state | 
      violation_log: new_log,
      health_metrics: new_metrics,
      ethos_state: new_ethos
    }
  end
  
  defp update_ethos_for_violation(ethos, violation) do
    # Violations reduce ethos integrity
    integrity_impact = case violation.type do
      :policy -> 0.02       # Policy violations hurt integrity
      :decision -> 0.01     # Bad decisions hurt less
      :resource_allocation -> 0.03  # Resource violations are serious
      _ -> 0.01
    end
    
    %{ethos |
      integrity: max(0.0, ethos.integrity - integrity_impact),
      last_assessment: DateTime.utc_now()
    }
  end
  
  defp update_enforcement_stats(result, target, state) do
    stats = state.enforcement_stats
    
    # Update total count
    new_total = stats.total_enforcements + 1
    
    # Update result count
    new_stats = case result do
      :success -> %{stats | successful: stats.successful + 1}
      :enforced -> %{stats | successful: stats.successful + 1}
      :failed -> %{stats | failed: stats.failed + 1}
      :overridden -> %{stats | overridden: stats.overridden + 1}
    end
    
    # Update per-subsystem stats
    subsystem_stats = Map.update(
      new_stats.by_subsystem,
      target,
      %{total: 1, successful: if(result in [:success, :enforced], do: 1, else: 0)},
      fn current ->
        %{current |
          total: current.total + 1,
          successful: current.successful + if(result in [:success, :enforced], do: 1, else: 0)
        }
      end
    )
    
    final_stats = %{new_stats |
      total_enforcements: new_total,
      by_subsystem: subsystem_stats
    }
    
    %{state | enforcement_stats: final_stats}
  end
  
  defp analyze_violation_patterns(violations) do
    # Group violations by type and policy
    by_type = Enum.group_by(violations, & &1.type)
    by_policy = violations
    |> Enum.filter(& &1[:policy_id])
    |> Enum.group_by(& &1.policy_id)
    
    # Find most common violation
    most_common_type = by_type
    |> Enum.max_by(fn {_type, list} -> length(list) end, fn -> {:unknown, []} end)
    |> elem(0)
    
    most_violated_policy = by_policy
    |> Enum.max_by(fn {_policy, list} -> length(list) end, fn -> {:unknown, []} end)
    |> elem(0)
    
    %{
      total_violations: length(violations),
      by_type: Map.new(by_type, fn {type, list} -> {type, length(list)} end),
      most_common_type: most_common_type,
      most_violated_policy: most_violated_policy,
      time_span: calculate_time_span(violations),
      severity_trend: calculate_severity_trend(violations)
    }
  end
  
  defp calculate_time_span(violations) do
    if Enum.empty?(violations) do
      0
    else
      oldest = violations |> Enum.map(& &1.timestamp) |> Enum.min()
      newest = violations |> Enum.map(& &1.timestamp) |> Enum.max()
      DateTime.diff(newest, oldest)
    end
  end
  
  defp calculate_severity_trend(violations) do
    # Check if violations are getting more or less severe
    severities = violations
    |> Enum.map(& Map.get(&1, :severity, 0.5))
    |> Enum.with_index()
    
    if length(severities) < 2 do
      :stable
    else
      # Simple trend: compare first half to second half average
      mid = div(length(severities), 2)
      {first_half, second_half} = Enum.split(severities, mid)
      
      first_avg = first_half |> Enum.map(&elem(&1, 0)) |> Enum.sum() |> Kernel./(length(first_half))
      second_avg = second_half |> Enum.map(&elem(&1, 0)) |> Enum.sum() |> Kernel./(length(second_half))
      
      cond do
        second_avg > first_avg + 0.1 -> :worsening
        second_avg < first_avg - 0.1 -> :improving
        true -> :stable
      end
    end
  end
  
  defp determine_violation_response(pattern, state) do
    cond do
      pattern.severity_trend == :worsening ->
        # Things are getting worse - need stronger intervention
        %{
          type: :escalated_enforcement,
          targets: identify_problem_subsystems(pattern, state),
          measures: :strict_compliance,
          duration: :until_improvement
        }
        
      pattern.most_violated_policy != :unknown ->
        # Specific policy being repeatedly violated
        %{
          type: :targeted_enforcement,
          policy: pattern.most_violated_policy,
          measures: :reinforce_specific_policy,
          adjustments: calculate_policy_adjustments(pattern.most_violated_policy, state)
        }
        
      pattern.total_violations > 10 ->
        # General compliance problem
        %{
          type: :system_wide_enforcement,
          measures: :tighten_all_policies,
          emergency_level: :medium
        }
        
      true ->
        # Standard response
        %{
          type: :standard_enforcement,
          measures: :monitor_closely
        }
    end
  end
  
  defp identify_problem_subsystems(pattern, state) do
    # Identify which subsystems are causing the most violations
    state.enforcement_stats.by_subsystem
    |> Enum.filter(fn {_subsystem, stats} ->
      success_rate = stats.successful / max(1, stats.total)
      success_rate < 0.8  # Less than 80% success rate
    end)
    |> Enum.map(&elem(&1, 0))
  end
  
  defp calculate_policy_adjustments(policy_id, state) do
    # Calculate specific adjustments for a repeatedly violated policy
    current_constraint = case policy_id do
      :resource_conservation -> Map.get(state.constraints, :max_resource_usage, 0.8)
      :response_time -> Map.get(state.constraints, :min_response_time, 100)
      :error_rate -> Map.get(state.constraints, :error_tolerance, 0.01)
      :variety_management -> Map.get(state.constraints, :variety_limit, 10_000)
      _ -> nil
    end
    
    if current_constraint do
      # Make constraint 10% stricter
      case policy_id do
        :resource_conservation -> %{max_resource_usage: current_constraint * 0.9}
        :response_time -> %{min_response_time: current_constraint * 1.1}
        :error_rate -> %{error_tolerance: current_constraint * 0.9}
        :variety_management -> %{variety_limit: current_constraint * 0.9}
        _ -> %{}
      end
    else
      %{}
    end
  end
  
  defp execute_governance_decision(decision, state) do
    Logger.info("S5 executing governance decision: #{decision.type}")
    
    case decision.action.type do
      :escalated_enforcement ->
        # Send escalated enforcement to problem subsystems
        Enum.each(decision.action.targets, fn target ->
          EventBus.publish(target, {:s5_escalated_enforcement, decision.action})
        end)
        
        # Tighten monitoring
        state
        
      :targeted_enforcement ->
        # Reinforce specific policy
        policy = Enum.find(state.active_policies, & &1.id == decision.action.policy)
        if policy do
          enforce_policy_immediately(policy, state)
        else
          state
        end
        
      :system_wide_enforcement ->
        # Tighten all policies
        EventBus.publish(:all_subsystems, {:s5_system_wide_enforcement, decision.action})
        
        # Reduce all tolerances by 10%
        new_constraints = state.constraints
        |> Enum.map(fn {k, v} when is_number(v) -> {k, v * 0.9}; kv -> kv end)
        |> Map.new()
        
        %{state | constraints: new_constraints}
        
      _ ->
        state
    end
  end
  
  defp evaluate_operational_compliance(event_data, state) do
    # Check S1 operations against policies
    if Map.has_key?(event_data, :metrics) do
      metrics = event_data.metrics
      
      # Check response time
      if Map.get(metrics, :response_time, 0) > state.constraints.min_response_time do
        log_violation(:s1_operations, %{
          metric: :response_time,
          value: metrics.response_time,
          limit: state.constraints.min_response_time
        }, state)
      else
        state
      end
    else
      state
    end
  end
  
  defp evaluate_coordination_health(event_data, state) do
    # Monitor S2 coordination effectiveness
    if Map.get(event_data, :oscillation_detected, false) do
      log_violation(:s2_coordination, %{
        issue: :oscillation,
        severity: Map.get(event_data, :oscillation_severity, 0.5)
      }, state)
    else
      state
    end
  end
  
  defp evaluate_control_decisions(event_data, state) do
    # Evaluate S3 control decisions
    if Map.has_key?(event_data, :decision) do
      decision = event_data.decision
      
      # Check if decision respects constraints
      if violates_control_policies?(decision, state) do
        log_violation(:s3_control, decision, state)
      else
        update_enforcement_stats(:success, :s3_control, state)
      end
    else
      state
    end
  end
  
  defp violates_control_policies?(decision, state) do
    # Check control decision against policies
    case decision[:type] do
      :resource_allocation ->
        total = decision[:resources] |> Map.values() |> Enum.sum()
        total > state.constraints.max_resource_usage
        
      :optimization ->
        # Check if optimization respects identity
        Map.get(decision, :identity_impact, 0) > @identity_drift_threshold
        
      _ ->
        false
    end
  end
  
  defp violates_resource_policies?(allocation, state) do
    # Check resource allocation against policies
    total_allocated = allocation
    |> Map.get(:resources, %{})
    |> Map.values()
    |> Enum.sum()
    
    total_allocated > state.constraints.max_resource_usage
  end
  
  defp calculate_governance_effectiveness(state) do
    stats = state.enforcement_stats
    
    if stats.total_enforcements == 0 do
      1.0  # No enforcements yet, assume effective
    else
      # Success rate weighted by recency
      success_rate = stats.successful / stats.total_enforcements
      
      # Adjust for recent violations
      recent_violations = Enum.count(state.violation_log, fn v ->
        DateTime.diff(DateTime.utc_now(), v.timestamp) < 60  # Last minute
      end)
      
      violation_penalty = min(0.5, recent_violations * 0.1)
      
      max(0.0, success_rate - violation_penalty)
    end
  end
  
  defp calculate_policy_compliance(state) do
    # Calculate overall policy compliance rate
    if state.health_metrics.decisions_evaluated == 0 do
      1.0
    else
      violations = state.health_metrics.value_violations
      evaluated = state.health_metrics.decisions_evaluated
      
      max(0.0, 1.0 - (violations / evaluated))
    end
  end
  
  defp calculate_violation_rate(state) do
    # Violations per minute
    recent_violations = Enum.count(state.violation_log, fn v ->
      DateTime.diff(DateTime.utc_now(), v.timestamp) < 60
    end)
    
    recent_violations / 60.0  # Rate per second
  end
  
  defp calculate_adaptation_stress(state) do
    # How much stress is the system under from adaptations
    adaptation_rate = Map.get(state.constraints, :adaptation_rate, 0.1)
    current_adaptations = state.health_metrics.policy_updates
    
    # Stress increases with adaptation frequency
    base_stress = min(1.0, current_adaptations * 0.01)
    
    # Adjust for identity coherence
    identity_stress = 1.0 - state.health_metrics.identity_coherence
    
    (base_stress + identity_stress) / 2.0
  end
  
  defp initiate_emergency_governance(state) do
    Logger.error("S5 initiating emergency governance - system health critical")
    
    # Emergency governance measures
    emergency_policies = [
      %{
        id: :emergency_conservation,
        name: "Emergency Resource Conservation",
        type: :emergency,
        target: :all_subsystems,
        rule: fn _state -> true end,  # Always enforce
        enforcement: :immediate,
        priority: 0  # Highest priority
      }
    ]
    
    # Add emergency policies
    new_policies = emergency_policies ++ state.active_policies
    
    # Broadcast emergency governance
    EventBus.publish(:all_subsystems, {:s5_emergency_governance, %{
      reason: :critical_health,
      measures: :strict_conservation,
      duration: :until_recovery
    }})
    
    %{state | active_policies: new_policies}
  end
  
  defp update_environmental_model_from_event(event_data, current_model) do
    # Update model with new intelligence
    Map.merge(current_model, %{
      last_update: DateTime.utc_now(),
      complexity: Map.get(event_data, :environmental_complexity, current_model.complexity),
      change_rate: Map.get(event_data, :change_rate, current_model.change_rate),
      threat_level: Map.get(event_data, :threat_level, current_model.threat_level),
      opportunity_level: Map.get(event_data, :opportunity_level, current_model.opportunity_level),
      external_pressures: Map.get(event_data, :external_pressures, [])
    })
  end
  
  defp requires_policy_adaptation?(environmental_model, state) do
    # Check if environment has changed enough to warrant adaptation
    environmental_model.change_rate > 0.3 ||
    environmental_model.threat_level > 0.7 ||
    environmental_model.complexity > 0.8
  end
  
  defp adapt_policies_to_environment(state) do
    # Adapt policies based on environmental pressures
    adapted_constraints = adapt_constraints_to_environment(state.constraints, state.environmental_model)
    
    # Update adaptation strategy
    new_strategy = determine_adaptation_strategy(state.environmental_model)
    
    new_state = %{state | 
      constraints: adapted_constraints,
      adaptation_strategy: new_strategy
    }
    
    # Broadcast new constraints
    broadcast_policy_constraints(new_state)
    
    {:noreply, new_state}
  end
  
  defp process_intelligence_variety(variety_data, state) do
    # Process intelligence from S4
    
    # Update environmental model if present
    new_environmental_model = if variety_data[:environmental_model] do
      update_environmental_model(state.environmental_model, variety_data.environmental_model)
    else
      state.environmental_model
    end
    
    # Process policy violations if detected
    new_state = if variety_data[:policy_violations] && length(variety_data.policy_violations) > 0 do
      Enum.reduce(variety_data.policy_violations, state, fn violation, acc ->
        log_violation(:intelligence_detected, violation, acc)
      end)
    else
      state
    end
    
    %{new_state | environmental_model: new_environmental_model}
  end
  
  defp broadcast_policy_updates(state) do
    # Broadcast updated policies to all subsystems
    Logger.info("S5 broadcasting policy updates to all subsystems")
    
    # Use variety channel for policy distribution
    VarietyChannel.transmit(:s5_to_all, %{
      constraints: state.constraints,
      values: extract_operational_values(state.values),
      enforcement: :mandatory,
      adaptation_strategy: state.adaptation_strategy,
      timestamp: DateTime.utc_now()
    })
    
    # Also use direct EventBus for critical updates
    EventBus.publish(:all_subsystems, {:s5_policy_update, %{
      constraints: state.constraints,
      priority: :high
    }})
  end
  
  defp adapt_constraints_to_environment(constraints, environmental_model) do
    # Dynamically adjust constraints based on environment
    
    # In high-threat environments, be more conservative
    threat_factor = 1.0 - environmental_model.threat_level * 0.3
    
    # In complex environments, reduce variety limits
    complexity_factor = 1.0 - environmental_model.complexity * 0.2
    
    %{constraints |
      max_resource_usage: constraints.max_resource_usage * threat_factor,
      variety_limit: round(constraints.variety_limit * complexity_factor),
      adaptation_rate: if(environmental_model.change_rate > 0.5, do: 0.2, else: 0.1)
    }
  end
  
  defp determine_adaptation_strategy(environmental_model) do
    cond do
      environmental_model.threat_level > 0.8 -> :defensive
      environmental_model.opportunity_level > 0.7 -> :expansive
      environmental_model.change_rate > 0.6 -> :agile
      environmental_model.complexity > 0.7 -> :conservative
      true -> :balanced
    end
  end
end