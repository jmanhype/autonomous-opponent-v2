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
    
    # Broadcast initial constraints to all subsystems after a delay
    Process.send_after(self(), :broadcast_initial_constraints, 1000)
    
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
  
  defp formulate_existential_response(threat, _state) do
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
  
  defp consider_adaptation(model, _state) do
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
end