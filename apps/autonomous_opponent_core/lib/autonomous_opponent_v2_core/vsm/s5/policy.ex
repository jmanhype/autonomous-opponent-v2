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
  
  defstruct [
    :identity,
    :values,
    :constraints,
    :policy_rules,
    :environmental_model,
    :adaptation_strategy,
    :health_metrics
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
    # Subscribe to intelligence and algedonic signals
    EventBus.subscribe(:s4_intelligence)
    EventBus.subscribe(:emergency_algedonic)
    EventBus.subscribe(:algedonic_intervention)
    
    # Start monitoring
    Process.send_after(self(), :evaluate_identity, 10_000)
    Process.send_after(self(), :report_health, 1000)
    
    state = %__MODULE__{
      identity: define_core_identity(opts),
      values: define_core_values(),
      constraints: init_policy_constraints(),
      policy_rules: init_policy_rules(),
      environmental_model: %{},
      adaptation_strategy: :conservative,
      health_metrics: %{
        identity_coherence: 1.0,
        value_violations: 0,
        policy_updates: 0,
        existential_threats_handled: 0
      }
    }
    
    # Broadcast initial constraints to all subsystems
    broadcast_policy_constraints(state)
    
    Logger.info("S5 Policy online - I think, therefore we are")
    
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
    EventBus.publish(:s5_health, %{health: health})
    
    # S5's health is the system's existential health
    cond do
      health < 0.3 ->
        Algedonic.report_pain(:s5_policy, :existential_health, 1.0 - health)
        
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
  
  defp constraint_aligns_with_identity?(name, value, state) do
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
    violations = Enum.reduce(state.values, 0, fn {_name, value}, acc ->
      if violates_value?(decision, value) do
        acc + value.priority
      else
        acc
      end
    end)
    
    %{
      decision: decision,
      violations: violations,
      alignment: calculate_alignment(decision, state),
      recommendation: if(violations > 0, do: :reject, else: :approve)
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
    # How do we respond to existential threats?
    threat_severity = assess_threat_severity(threat)
    
    cond do
      threat_severity > 0.9 ->
        # Transform or die
        %{strategy: :transform, urgency: :immediate}
        
      threat_severity > 0.7 ->
        # Adapt to survive
        %{strategy: :adapt, urgency: :high}
        
      true ->
        # Resist and maintain identity
        %{strategy: :resist, urgency: :normal}
    end
  end
  
  defp calculate_identity_coherence(state) do
    # How much are we still "ourselves"?
    base_coherence = 1.0
    
    # Deduct for value violations
    violation_penalty = min(0.5, state.health_metrics.value_violations * 0.1)
    
    # Deduct for excessive adaptations
    adaptation_penalty = min(0.3, state.health_metrics.policy_updates * 0.01)
    
    max(0.0, base_coherence - violation_penalty - adaptation_penalty)
  end
  
  defp calculate_health_score(state) do
    # S5 health is about identity and purpose
    metrics = state.health_metrics
    
    # Weighted health calculation
    identity_weight = 0.5
    operational_weight = 0.3
    threat_weight = 0.2
    
    identity_score = metrics.identity_coherence * identity_weight
    operational_score = (1.0 - min(1.0, metrics.value_violations / 10)) * operational_weight
    threat_score = (1.0 - min(1.0, metrics.existential_threats_handled / 5)) * threat_weight
    
    identity_score + operational_score + threat_score
  end
  
  defp broadcast_constraint_update(name, value) do
    EventBus.publish(:s5_policy, {:constraint_update, name, value})
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
  
  defp violates_value?(_decision, _value) do
    # Check if decision violates a value
    false  # Simplified
  end
  
  defp calculate_alignment(_decision, _state) do
    0.8  # Simplified
  end
  
  defp update_environmental_model(current_model, intelligence_report) do
    # Update our understanding of the environment
    Map.merge(current_model, intelligence_report.environmental_model)
  end
  
  defp environment_diverging?(model, state) do
    # Is the environment changing beyond our constraints?
    Map.get(model, :change_rate, 0) > state.constraints.adaptation_rate
  end
  
  defp consider_adaptation(model, state) do
    %{
      required: Map.get(model, :adaptation_pressure, 0) > 0.5,
      type: :incremental,
      target_state: model.optimal_configuration
    }
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
  
  defp consider_identity_evolution(_state) do
    Logger.info("S5 considering identity evolution")
    # Complex logic for evolving identity while maintaining continuity
  end
  
  defp assess_threat_severity(_threat) do
    # Assess how severe the threat is
    0.5  # Simplified
  end
  
  defp adapt_identity(_threat, state) do
    # Adapt identity to survive threat
    state
  end
  
  defp transform_identity(_threat, state) do
    # Fundamental transformation
    Logger.warning("S5 undergoing transformation")
    
    %{state | 
      identity: %{state.identity | emergence_level: :transforming}
    }
  end
  
  defp emergency_caused_identity_damage?(_state) do
    # Check if emergency actions violated core values
    false  # Simplified
  end
  
  defp reconcile_emergency_actions(state) do
    Logger.info("S5 reconciling emergency actions with identity")
    {:noreply, state}
  end
  
  defp adjust_constraints_for_environment(constraints, _target) do
    # Gradually adjust constraints
    %{constraints | adaptation_rate: 0.15}
  end
end