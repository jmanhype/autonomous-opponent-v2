defmodule AutonomousOpponent.VSM.S5.IdentityManager do
  @moduledoc """
  Identity management component for S5 Policy.
  
  Manages system self-awareness, identity evolution, and self-model
  maintenance. Implements reflective processes for identity development
  and personality trait evolution.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :identity_history,
    :self_model,
    :reflection_state
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  def get_current_identity(server \\ __MODULE__, base_identity) do
    GenServer.call(server, {:get_identity, base_identity})
  end
  
  def evolve_identity(server \\ __MODULE__, current_identity, context) do
    GenServer.call(server, {:evolve_identity, current_identity, context})
  end
  
  def reflect_on_experience(server \\ __MODULE__, experience) do
    GenServer.cast(server, {:reflect, experience})
  end
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      identity_history: [],
      self_model: init_self_model(),
      reflection_state: init_reflection_state()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_identity, base_identity}, _from, state) do
    # Enhance base identity with current self-model
    current_identity = merge_with_self_model(base_identity, state.self_model)
    
    {:reply, current_identity, state}
  end
  
  @impl true
  def handle_call({:evolve_identity, current_identity, context}, _from, state) do
    # Analyze experiences for identity evolution
    evolution_factors = analyze_evolution_factors(context, state)
    
    # Apply evolution
    evolved_identity = apply_identity_evolution(current_identity, evolution_factors)
    
    # Update self-model
    new_self_model = update_self_model(state.self_model, evolved_identity, context)
    
    # Record in history
    history_entry = %{
      timestamp: System.monotonic_time(:millisecond),
      identity: evolved_identity,
      factors: evolution_factors,
      context: context
    }
    
    new_history = [history_entry | state.identity_history] |> Enum.take(50)
    
    new_state = %{state |
      identity_history: new_history,
      self_model: new_self_model
    }
    
    {:reply, evolved_identity, new_state}
  end
  
  @impl true
  def handle_cast({:reflect, experience}, state) do
    # Add experience to reflection queue
    new_reflection = add_to_reflection(experience, state.reflection_state)
    
    # Process if queue is full
    new_state = if should_process_reflection?(new_reflection) do
      processed_model = process_reflections(new_reflection, state.self_model)
      %{state |
        self_model: processed_model,
        reflection_state: reset_reflection_state(new_reflection)
      }
    else
      %{state | reflection_state: new_reflection}
    end
    
    {:noreply, new_state}
  end
  
  defp init_self_model do
    %{
      capabilities: %{
        learned: [],
        developing: [],
        mastered: []
      },
      behavioral_patterns: %{},
      success_patterns: [],
      failure_patterns: [],
      adaptation_strategies: []
    }
  end
  
  defp init_reflection_state do
    %{
      experience_queue: [],
      reflection_threshold: 10,
      last_reflection: nil
    }
  end
  
  defp merge_with_self_model(base_identity, self_model) do
    # Update SWOT analysis
    updated_self_model = %{base_identity.self_model |
      strengths: extract_strengths(self_model),
      weaknesses: extract_weaknesses(self_model),
      opportunities: extract_opportunities(self_model),
      threats: extract_threats(self_model)
    }
    
    %{base_identity | self_model: updated_self_model}
  end
  
  defp analyze_evolution_factors(context, state) do
    %{
      experience_diversity: calculate_experience_diversity(context.experiences),
      achievement_rate: calculate_achievement_rate(context.achievements),
      environmental_pressure: assess_environmental_pressure(context.environment),
      adaptation_success: measure_adaptation_success(state.identity_history)
    }
  end
  
  defp apply_identity_evolution(identity, factors) do
    # Evolve personality traits
    evolved_traits = Enum.map(identity.personality_traits, fn {trait, value} ->
      evolution_delta = calculate_trait_evolution(trait, value, factors)
      new_value = max(0.0, min(1.0, value + evolution_delta))
      {trait, new_value}
    end)
    |> Map.new()
    
    # Update evolution stage if appropriate
    new_stage = determine_evolution_stage(evolved_traits, factors, identity.evolution_stage)
    
    %{identity |
      personality_traits: evolved_traits,
      evolution_stage: new_stage
    }
  end
  
  defp calculate_trait_evolution(trait, current_value, factors) do
    case trait do
      :adaptability ->
        factors.experience_diversity * 0.1 * (1 - current_value)
      
      :resilience ->
        factors.environmental_pressure * 0.05 * (1 - current_value)
      
      :curiosity ->
        (factors.experience_diversity * 0.1 - factors.achievement_rate * 0.05) * (1 - current_value)
      
      :cooperation ->
        factors.adaptation_success * 0.1 * (1 - current_value)
      
      _ ->
        0.0
    end
  end
  
  defp determine_evolution_stage(traits, factors, current_stage) do
    avg_trait_value = traits
                     |> Map.values()
                     |> Enum.sum()
                     |> Kernel./(map_size(traits))
    
    cond do
      avg_trait_value > 0.8 and factors.achievement_rate > 0.7 ->
        :mature
      
      avg_trait_value > 0.6 and current_stage == :emerging ->
        :developing
      
      avg_trait_value > 0.4 and current_stage == :nascent ->
        :emerging
      
      true ->
        current_stage
    end
  end
  
  defp update_self_model(self_model, evolved_identity, context) do
    # Update capabilities based on achievements
    new_capabilities = update_capabilities(
      self_model.capabilities,
      context.achievements
    )
    
    # Learn behavioral patterns
    new_patterns = extract_behavioral_patterns(
      context.experiences,
      self_model.behavioral_patterns
    )
    
    %{self_model |
      capabilities: new_capabilities,
      behavioral_patterns: new_patterns
    }
  end
  
  defp add_to_reflection(experience, reflection_state) do
    %{reflection_state |
      experience_queue: [experience | reflection_state.experience_queue]
    }
  end
  
  defp should_process_reflection?(reflection_state) do
    length(reflection_state.experience_queue) >= reflection_state.reflection_threshold
  end
  
  defp process_reflections(reflection_state, self_model) do
    experiences = reflection_state.experience_queue
    
    # Extract patterns from experiences
    success_patterns = extract_success_patterns(experiences)
    failure_patterns = extract_failure_patterns(experiences)
    
    # Update self-model with learned patterns
    %{self_model |
      success_patterns: merge_patterns(self_model.success_patterns, success_patterns),
      failure_patterns: merge_patterns(self_model.failure_patterns, failure_patterns)
    }
  end
  
  defp reset_reflection_state(reflection_state) do
    %{reflection_state |
      experience_queue: [],
      last_reflection: System.monotonic_time(:millisecond)
    }
  end
  
  # Helper functions
  
  defp extract_strengths(self_model) do
    self_model.capabilities.mastered
  end
  
  defp extract_weaknesses(self_model) do
    self_model.failure_patterns
    |> Enum.map(& &1.area)
    |> Enum.uniq()
    |> Enum.take(5)
  end
  
  defp extract_opportunities(self_model) do
    self_model.capabilities.developing
  end
  
  defp extract_threats(_self_model) do
    []  # Would analyze failure patterns for systemic threats
  end
  
  defp calculate_experience_diversity(experiences) do
    if length(experiences) == 0 do
      0.0
    else
      unique_types = experiences
                    |> Enum.map(& &1[:type])
                    |> Enum.uniq()
                    |> length()
      
      min(1.0, unique_types / 10)
    end
  end
  
  defp calculate_achievement_rate(achievements) do
    if length(achievements) == 0 do
      0.5
    else
      successful = Enum.count(achievements, & &1[:success])
      successful / length(achievements)
    end
  end
  
  defp assess_environmental_pressure(environment) do
    # Simplified pressure assessment
    0.3
  end
  
  defp measure_adaptation_success(history) do
    # Measure how well adaptations have worked
    recent_history = Enum.take(history, 10)
    
    if length(recent_history) < 2 do
      0.5
    else
      # Check if traits are improving
      trait_improvements = Enum.chunk_every(recent_history, 2, 1, :discard)
      |> Enum.count(fn [newer, older] ->
        avg_traits(newer.identity) > avg_traits(older.identity)
      end)
      
      trait_improvements / (length(recent_history) - 1)
    end
  end
  
  defp avg_traits(identity) do
    values = Map.values(identity.personality_traits)
    Enum.sum(values) / length(values)
  end
  
  defp update_capabilities(capabilities, achievements) do
    # Move capabilities based on achievements
    achievements
    |> Enum.reduce(capabilities, fn achievement, caps ->
      if achievement[:success] and achievement[:skill] do
        skill = achievement.skill
        
        cond do
          skill in caps.developing ->
            # Promote to mastered
            %{caps |
              developing: List.delete(caps.developing, skill),
              mastered: [skill | caps.mastered] |> Enum.uniq()
            }
          
          skill in caps.learned ->
            # Promote to developing
            %{caps |
              learned: List.delete(caps.learned, skill),
              developing: [skill | caps.developing] |> Enum.uniq()
            }
          
          true ->
            # New skill learned
            %{caps |
              learned: [skill | caps.learned] |> Enum.uniq()
            }
        end
      else
        caps
      end
    end)
  end
  
  defp extract_behavioral_patterns(experiences, existing_patterns) do
    # Group experiences by type and outcome
    new_patterns = experiences
    |> Enum.group_by(& &1[:type])
    |> Enum.map(fn {type, exps} ->
      success_rate = Enum.count(exps, & &1[:success]) / length(exps)
      {type, %{count: length(exps), success_rate: success_rate}}
    end)
    |> Map.new()
    
    # Merge with existing patterns
    Map.merge(existing_patterns, new_patterns, fn _k, old, new ->
      %{
        count: old.count + new.count,
        success_rate: (old.success_rate * old.count + new.success_rate * new.count) / 
                     (old.count + new.count)
      }
    end)
  end
  
  defp extract_success_patterns(experiences) do
    experiences
    |> Enum.filter(& &1[:success])
    |> Enum.group_by(& &1[:pattern])
    |> Enum.map(fn {pattern, instances} ->
      %{
        pattern: pattern,
        frequency: length(instances),
        contexts: Enum.map(instances, & &1[:context]) |> Enum.uniq()
      }
    end)
    |> Enum.sort_by(& &1.frequency, :desc)
    |> Enum.take(10)
  end
  
  defp extract_failure_patterns(experiences) do
    experiences
    |> Enum.filter(& not &1[:success])
    |> Enum.group_by(& &1[:failure_reason])
    |> Enum.map(fn {reason, instances} ->
      %{
        area: reason,
        frequency: length(instances),
        contexts: Enum.map(instances, & &1[:context]) |> Enum.uniq()
      }
    end)
    |> Enum.sort_by(& &1.frequency, :desc)
    |> Enum.take(5)
  end
  
  defp merge_patterns(existing, new) do
    # Merge and deduplicate patterns
    (existing ++ new)
    |> Enum.uniq_by(& &1[:pattern] || &1[:area])
    |> Enum.take(15)
  end
end