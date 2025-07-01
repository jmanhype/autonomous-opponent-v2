defmodule AutonomousOpponent.VSM.S5.ValueSystem do
  @moduledoc """
  Value system component for S5 Policy.
  
  Manages system values, ethical constraints, and value learning.
  Implements value conflict resolution and adaptation based on
  experience and environmental feedback.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :value_history,
    :conflict_resolver,
    :learning_state
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  def update_values(server \\ __MODULE__, current_values, updates) do
    GenServer.call(server, {:update_values, current_values, updates})
  end
  
  def resolve_conflict(server \\ __MODULE__, conflicting_values) do
    GenServer.call(server, {:resolve_conflict, conflicting_values})
  end
  
  def adapt_to_environment(server \\ __MODULE__, current_values, env_data) do
    GenServer.call(server, {:adapt_to_environment, current_values, env_data})
  end
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      value_history: [],
      conflict_resolver: init_conflict_resolver(),
      learning_state: init_value_learning()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:update_values, current_values, updates}, _from, state) do
    # Apply updates with learning
    updated_values = apply_value_updates(current_values, updates, state.learning_state)
    
    # Check for conflicts
    conflicts = detect_value_conflicts(updated_values)
    
    # Resolve conflicts if any
    final_values = if Enum.empty?(conflicts) do
      updated_values
    else
      resolve_value_conflicts(updated_values, conflicts, state.conflict_resolver)
    end
    
    # Record in history
    history_entry = %{
      timestamp: System.monotonic_time(:millisecond),
      values: final_values,
      updates: updates,
      conflicts_resolved: length(conflicts)
    }
    
    new_history = [history_entry | state.value_history] |> Enum.take(100)
    new_state = %{state | value_history: new_history}
    
    {:reply, final_values, new_state}
  end
  
  @impl true
  def handle_call({:resolve_conflict, conflicting_values}, _from, state) do
    resolution = perform_conflict_resolution(
      conflicting_values,
      state.conflict_resolver,
      state.value_history
    )
    
    {:reply, resolution, state}
  end
  
  @impl true
  def handle_call({:adapt_to_environment, current_values, env_data}, _from, state) do
    # Analyze environmental pressures
    value_pressures = analyze_environmental_pressures(env_data)
    
    # Adapt values based on pressures
    adapted_values = adapt_values(current_values, value_pressures, state.learning_state)
    
    # Update learning state
    new_learning = update_learning_from_adaptation(
      state.learning_state,
      value_pressures,
      adapted_values
    )
    
    new_state = %{state | learning_state: new_learning}
    
    {:reply, adapted_values, new_state}
  end
  
  defp init_conflict_resolver do
    %{
      resolution_strategies: [
        :weighted_average,
        :priority_based,
        :context_sensitive,
        :ethical_override
      ],
      ethical_priorities: %{
        no_harm: 1.0,
        sustainability: 0.9,
        fairness: 0.8,
        transparency: 0.7
      }
    }
  end
  
  defp init_value_learning do
    %{
      adaptation_rate: 0.1,
      stability_factor: 0.8,
      experience_weights: %{
        success: 1.0,
        failure: -0.5,
        neutral: 0.1
      },
      learned_associations: %{}
    }
  end
  
  defp apply_value_updates(current_values, updates, learning_state) do
    # Apply updates with learning rate
    base_updates = Map.merge(current_values, %{
      core_values: apply_core_value_updates(
        current_values.core_values,
        updates,
        learning_state.adaptation_rate
      ),
      learned_values: apply_learned_value_updates(
        current_values.learned_values,
        updates,
        learning_state
      )
    })
    
    # Normalize values
    normalize_values(base_updates)
  end
  
  defp apply_core_value_updates(core_values, updates, adaptation_rate) do
    Enum.reduce(updates, core_values, fn update, values ->
      if Map.has_key?(values, update.value) do
        current = Map.get(values, update.value)
        # Apply update with adaptation rate
        new_value = current + (update.weight - current) * adaptation_rate
        Map.put(values, update.value, max(0.0, min(1.0, new_value)))
      else
        values
      end
    end)
  end
  
  defp apply_learned_value_updates(learned_values, updates, learning_state) do
    Enum.reduce(updates, learned_values, fn update, values ->
      if update[:learned] do
        # Add or update learned value
        current = Map.get(values, update.value, 0.0)
        new_value = current * learning_state.stability_factor + 
                   update.weight * (1 - learning_state.stability_factor)
        Map.put(values, update.value, new_value)
      else
        values
      end
    end)
  end
  
  defp detect_value_conflicts(values) do
    conflicts = []
    
    # Check core value conflicts
    conflicts = conflicts ++ detect_core_conflicts(values.core_values)
    
    # Check learned vs core conflicts
    conflicts = conflicts ++ detect_learned_conflicts(
      values.core_values,
      values.learned_values
    )
    
    # Check ethical constraint violations
    conflicts ++ detect_ethical_conflicts(values, values.ethical_constraints)
  end
  
  defp detect_core_conflicts(core_values) do
    # Detect opposing values with high weights
    opposing_pairs = [
      {:efficiency, :innovation},
      {:stability, :adaptability}
    ]
    
    Enum.flat_map(opposing_pairs, fn {v1, v2} ->
      val1 = Map.get(core_values, v1, 0)
      val2 = Map.get(core_values, v2, 0)
      
      if val1 > 0.8 and val2 > 0.8 do
        [%{type: :opposing_values, values: [v1, v2], severity: :high}]
      else
        []
      end
    end)
  end
  
  defp detect_learned_conflicts(core_values, learned_values) do
    # Check if learned values conflict with core values
    Enum.flat_map(learned_values, fn {learned, weight} ->
      conflicting_core = find_conflicting_core_value(learned, core_values)
      
      if conflicting_core and weight > 0.7 do
        [%{
          type: :learned_core_conflict,
          learned_value: learned,
          core_value: conflicting_core,
          severity: :medium
        }]
      else
        []
      end
    end)
  end
  
  defp detect_ethical_conflicts(values, ethical_constraints) do
    # Check if any values violate ethical constraints
    Enum.flat_map(values.core_values ++ values.learned_values, fn {value, weight} ->
      violated_constraint = find_violated_constraint(value, weight, ethical_constraints)
      
      if violated_constraint do
        [%{
          type: :ethical_violation,
          value: value,
          constraint: violated_constraint,
          severity: :critical
        }]
      else
        []
      end
    end)
  end
  
  defp resolve_value_conflicts(values, conflicts, resolver) do
    # Sort conflicts by severity
    sorted_conflicts = Enum.sort_by(conflicts, & severity_priority(&1.severity), :desc)
    
    # Resolve each conflict
    Enum.reduce(sorted_conflicts, values, fn conflict, current_values ->
      resolve_single_conflict(conflict, current_values, resolver)
    end)
  end
  
  defp resolve_single_conflict(conflict, values, resolver) do
    case conflict.type do
      :opposing_values ->
        resolve_opposing_values(conflict, values, resolver)
      
      :learned_core_conflict ->
        resolve_learned_core_conflict(conflict, values)
      
      :ethical_violation ->
        resolve_ethical_violation(conflict, values, resolver)
      
      _ ->
        values
    end
  end
  
  defp perform_conflict_resolution(conflicting_values, resolver, history) do
    # Analyze historical resolutions
    historical_patterns = analyze_resolution_history(history)
    
    # Choose resolution strategy
    strategy = select_resolution_strategy(
      conflicting_values,
      resolver.resolution_strategies,
      historical_patterns
    )
    
    # Apply strategy
    apply_resolution_strategy(strategy, conflicting_values, resolver)
  end
  
  defp analyze_environmental_pressures(env_data) do
    pressures = %{}
    
    # Market pressure affects efficiency vs innovation
    if env_data[:market_conditions] do
      market = env_data.market_conditions
      pressures = Map.merge(pressures, %{
        efficiency: (if market.competition == :high, do: 0.8, else: 0.5),
        innovation: (if market.opportunities > 3, do: 0.9, else: 0.4)
      })
    end
    
    # Threat assessment affects resilience vs exploration
    if env_data[:threat_assessment] do
      threat = env_data.threat_assessment
      pressures = Map.merge(pressures, %{
        viability: if threat.level == :high, do: 1.0, else: 0.7,
        adaptability: if threat.level == :low, do: 0.8, else: 0.4
      })
    end
    
    pressures
  end
  
  defp adapt_values(current_values, pressures, learning_state) do
    # Adapt core values based on pressures
    adapted_core = Enum.reduce(pressures, current_values.core_values, fn {value, pressure}, cores ->
      if Map.has_key?(cores, value) do
        current = Map.get(cores, value)
        # Move value toward pressure with learning rate
        adapted = current + (pressure - current) * learning_state.adaptation_rate
        Map.put(cores, value, adapted)
      else
        cores
      end
    end)
    
    %{current_values | core_values: normalize_value_map(adapted_core)}
  end
  
  defp update_learning_from_adaptation(learning_state, pressures, adapted_values) do
    # Record adaptation pattern
    adaptation_pattern = %{
      pressures: pressures,
      result: adapted_values,
      timestamp: System.monotonic_time(:millisecond)
    }
    
    # Update learned associations
    new_associations = Map.merge(
      learning_state.learned_associations,
      extract_associations(pressures, adapted_values)
    )
    
    %{learning_state | learned_associations: new_associations}
  end
  
  defp normalize_values(values) do
    %{values |
      core_values: normalize_value_map(values.core_values),
      learned_values: normalize_value_map(values.learned_values)
    }
  end
  
  defp normalize_value_map(value_map) do
    total = value_map
           |> Map.values()
           |> Enum.sum()
    
    if total > 0 do
      Enum.map(value_map, fn {k, v} -> {k, v / total} end)
      |> Map.new()
    else
      value_map
    end
  end
  
  defp find_conflicting_core_value(_learned, _core_values) do
    # Simplified - would check semantic conflicts
    nil
  end
  
  defp find_violated_constraint(_value, _weight, _constraints) do
    # Simplified - would check constraint violations
    nil
  end
  
  defp severity_priority(severity) do
    case severity do
      :critical -> 3
      :high -> 2
      :medium -> 1
      :low -> 0
    end
  end
  
  defp resolve_opposing_values(conflict, values, resolver) do
    [v1, v2] = conflict.values
    
    # Use weighted average based on context
    weight1 = Map.get(values.core_values, v1, 0)
    weight2 = Map.get(values.core_values, v2, 0)
    
    # Reduce both to sustainable levels
    avg = (weight1 + weight2) / 2
    balanced = avg * 0.7  # Reduce to 70% to avoid conflict
    
    put_in(values, [:core_values, v1], balanced)
    |> put_in([:core_values, v2], balanced)
  end
  
  defp resolve_learned_core_conflict(conflict, values) do
    # Core values take precedence
    update_in(values.learned_values, fn learned ->
      Map.put(learned, conflict.learned_value, 0.3)  # Reduce learned value
    end)
  end
  
  defp resolve_ethical_violation(conflict, values, resolver) do
    # Ethical constraints override - set violating value to safe level
    if Map.has_key?(values.core_values, conflict.value) do
      put_in(values, [:core_values, conflict.value], 0.3)
    else
      update_in(values.learned_values, fn learned ->
        Map.put(learned, conflict.value, 0.1)
      end)
    end
  end
  
  defp analyze_resolution_history(history) do
    # Extract patterns from historical resolutions
    history
    |> Enum.take(20)
    |> Enum.map(& &1[:conflicts_resolved])
    |> Enum.filter(& &1 > 0)
    |> length()
  end
  
  defp select_resolution_strategy(_conflicting_values, strategies, _historical_patterns) do
    # Default to weighted average
    Enum.at(strategies, 0)
  end
  
  defp apply_resolution_strategy(strategy, conflicting_values, resolver) do
    case strategy do
      :weighted_average ->
        %{
          resolution: :balanced,
          values: balance_values(conflicting_values)
        }
      
      :priority_based ->
        %{
          resolution: :prioritized,
          values: prioritize_values(conflicting_values, resolver)
        }
      
      :ethical_override ->
        %{
          resolution: :ethical,
          values: apply_ethical_override(conflicting_values, resolver)
        }
      
      _ ->
        %{resolution: :default, values: conflicting_values}
    end
  end
  
  defp balance_values(values) do
    avg = Enum.sum(values) / length(values)
    Enum.map(values, fn _ -> avg end)
  end
  
  defp prioritize_values(values, resolver) do
    # Sort by ethical priority
    values  # Simplified
  end
  
  defp apply_ethical_override(values, resolver) do
    # Apply ethical constraints
    values  # Simplified
  end
  
  defp extract_associations(pressures, _adapted_values) do
    # Extract learned associations between pressures and successful adaptations
    Enum.map(pressures, fn {k, v} -> {k, %{pressure: v}} end)
    |> Map.new()
  end
end