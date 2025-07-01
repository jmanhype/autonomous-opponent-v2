defmodule AutonomousOpponent.VSM.S4.ScenarioModeler do
  @moduledoc """
  Scenario modeling component for S4 Intelligence.

  Generates future scenarios based on environmental models and patterns,
  with uncertainty quantification and cross-domain learning.
  """

  use GenServer
  require Logger

  defstruct [
    :modeling_engines,
    :scenario_history,
    :learning_state
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def generate_scenarios(server \\ __MODULE__, environmental_model, params) do
    GenServer.call(server, {:generate_scenarios, environmental_model, params}, 30_000)
  end

  def evaluate_scenario(server \\ __MODULE__, scenario_id) do
    GenServer.call(server, {:evaluate_scenario, scenario_id})
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      modeling_engines: init_modeling_engines(),
      scenario_history: [],
      learning_state: init_learning_state()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:generate_scenarios, environmental_model, params}, _from, state) do
    # 1 hour default
    horizon = params[:horizon] || 3600_000
    scenario_count = params[:count] || 5

    # Generate base scenarios
    base_scenarios = generate_base_scenarios(environmental_model, horizon, state)

    # Apply variations
    varied_scenarios = apply_scenario_variations(base_scenarios, scenario_count)

    # Cross-domain learning application
    enhanced_scenarios = apply_cross_domain_learning(varied_scenarios, state.learning_state)

    # Add metadata and scoring
    final_scenarios =
      Enum.map(enhanced_scenarios, fn scenario ->
        scenario
        |> add_scenario_metadata(horizon)
        |> score_scenario_plausibility(environmental_model)
      end)

    # Record in history
    history_entry = %{
      timestamp: System.monotonic_time(:millisecond),
      scenarios: final_scenarios,
      model_version: environmental_model[:version]
    }

    new_history = [history_entry | state.scenario_history] |> Enum.take(50)

    {:reply, final_scenarios, %{state | scenario_history: new_history}}
  end

  @impl true
  def handle_call({:evaluate_scenario, scenario_id}, _from, state) do
    # Find scenario in history
    scenario = find_scenario_in_history(scenario_id, state.scenario_history)

    if scenario do
      evaluation = evaluate_scenario_accuracy(scenario, state)
      {:reply, {:ok, evaluation}, state}
    else
      {:reply, {:error, :scenario_not_found}, state}
    end
  end

  defp init_modeling_engines do
    %{
      trend_projection: :linear_extrapolation,
      monte_carlo: :probabilistic_sampling,
      system_dynamics: :feedback_loops,
      agent_based: :behavioral_simulation
    }
  end

  defp init_learning_state do
    %{
      domain_knowledge: %{
        operational: [],
        environmental: [],
        strategic: []
      },
      transfer_patterns: [],
      accuracy_history: []
    }
  end

  defp generate_base_scenarios(environmental_model, horizon, state) do
    # Generate scenarios using different engines
    scenarios = []

    # Trend projection scenario
    trend_scenario = generate_trend_scenario(environmental_model, horizon)
    scenarios = [trend_scenario | scenarios]

    # System dynamics scenario
    dynamics_scenario = generate_dynamics_scenario(environmental_model, horizon)
    scenarios = [dynamics_scenario | scenarios]

    # Monte Carlo scenarios
    mc_scenarios = generate_monte_carlo_scenarios(environmental_model, horizon, 3)
    scenarios = scenarios ++ mc_scenarios

    scenarios
  end

  defp generate_trend_scenario(model, horizon) do
    %{
      id: generate_scenario_id(),
      type: :trend_projection,
      horizon: horizon,
      variables: project_variables_linearly(model, horizon),
      events: [],
      constraints: extract_constraints(model)
    }
  end

  defp generate_dynamics_scenario(model, horizon) do
    %{
      id: generate_scenario_id(),
      type: :system_dynamics,
      horizon: horizon,
      variables: simulate_feedback_loops(model, horizon),
      events: generate_dynamic_events(model, horizon),
      constraints: extract_constraints(model)
    }
  end

  defp generate_monte_carlo_scenarios(model, horizon, count) do
    Enum.map(1..count, fn _ ->
      %{
        id: generate_scenario_id(),
        type: :monte_carlo,
        horizon: horizon,
        variables: sample_probabilistic_variables(model, horizon),
        events: sample_random_events(model, horizon),
        constraints: extract_constraints(model)
      }
    end)
  end

  defp apply_scenario_variations(base_scenarios, target_count) do
    if length(base_scenarios) >= target_count do
      Enum.take(base_scenarios, target_count)
    else
      # Generate variations
      variations_needed = target_count - length(base_scenarios)

      variations =
        Enum.flat_map(base_scenarios, fn scenario ->
          generate_variations(scenario, div(variations_needed, length(base_scenarios)) + 1)
        end)

      base_scenarios ++ Enum.take(variations, variations_needed)
    end
  end

  defp generate_variations(scenario, count) do
    Enum.map(1..count, fn i ->
      %{
        scenario
        | id: "#{scenario.id}_var_#{i}",
          variables: vary_variables(scenario.variables, 0.1 * i),
          events: vary_events(scenario.events)
      }
    end)
  end

  defp apply_cross_domain_learning(scenarios, learning_state) do
    Enum.map(scenarios, fn scenario ->
      # Apply learned patterns from other domains
      applicable_patterns = find_applicable_patterns(scenario, learning_state.transfer_patterns)

      Enum.reduce(applicable_patterns, scenario, fn pattern, acc ->
        apply_pattern_to_scenario(pattern, acc)
      end)
    end)
  end

  defp add_scenario_metadata(scenario, horizon) do
    Map.merge(scenario, %{
      created_at: System.monotonic_time(:millisecond),
      horizon_ms: horizon,
      confidence_factors: calculate_confidence_factors(scenario),
      key_assumptions: identify_key_assumptions(scenario)
    })
  end

  defp score_scenario_plausibility(scenario, environmental_model) do
    scores = %{
      consistency: score_internal_consistency(scenario),
      alignment: score_model_alignment(scenario, environmental_model),
      feasibility: score_feasibility(scenario),
      novelty: score_novelty(scenario)
    }

    overall_score = calculate_overall_score(scores)

    Map.merge(scenario, %{
      plausibility_scores: scores,
      overall_plausibility: overall_score
    })
  end

  defp project_variables_linearly(model, horizon) do
    # Simple linear projection
    current_values = extract_current_values(model)
    trends = extract_trends(model)

    Enum.map(current_values, fn {var, value} ->
      trend = Map.get(trends, var, 0)
      # per hour
      projected_value = value + trend * horizon / 3_600_000

      {var,
       %{
         current: value,
         projected: projected_value,
         trend: trend,
         method: :linear
       }}
    end)
    |> Map.new()
  end

  defp simulate_feedback_loops(model, horizon) do
    # Simplified system dynamics simulation
    variables = extract_current_values(model)
    relationships = model[:relationships] || []

    # Run simple simulation steps
    # Max 100 steps, 1 per minute
    steps = min(100, div(horizon, 60_000))

    Enum.reduce(1..steps, variables, fn _step, vars ->
      apply_feedback_effects(vars, relationships)
    end)
    |> Enum.map(fn {var, value} ->
      {var,
       %{
         current: Map.get(variables, var),
         projected: value,
         method: :system_dynamics
       }}
    end)
    |> Map.new()
  end

  defp sample_probabilistic_variables(model, horizon) do
    # Monte Carlo sampling
    variables = extract_current_values(model)
    uncertainties = extract_uncertainties(model)

    Enum.map(variables, fn {var, value} ->
      uncertainty = Map.get(uncertainties, var, 0.1)
      sampled_value = value * (1 + :rand.normal() * uncertainty)

      {var,
       %{
         current: value,
         projected: sampled_value,
         uncertainty: uncertainty,
         method: :monte_carlo
       }}
    end)
    |> Map.new()
  end

  defp generate_dynamic_events(model, horizon) do
    # Generate plausible events based on system dynamics
    potential_events = [
      %{type: :threshold_breach, probability: 0.3, impact: :high},
      %{type: :feedback_amplification, probability: 0.2, impact: :medium},
      %{type: :state_transition, probability: 0.4, impact: :medium}
    ]

    Enum.filter(potential_events, fn event ->
      :rand.uniform() < event.probability
    end)
    |> Enum.map(fn event ->
      %{
        event
        | timing: :rand.uniform() * horizon,
          details: generate_event_details(event.type, model)
      }
    end)
  end

  defp sample_random_events(model, horizon) do
    # Random event generation for Monte Carlo
    # Events per millisecond
    event_rate = 0.001
    expected_events = event_rate * horizon
    actual_events = :rand.poisson(expected_events)

    Enum.map(1..actual_events, fn _ ->
      %{
        type: Enum.random([:external_shock, :internal_failure, :opportunity]),
        timing: :rand.uniform() * horizon,
        impact: Enum.random([:low, :medium, :high]),
        probability: :rand.uniform()
      }
    end)
  end

  defp extract_constraints(model) do
    # Extract system constraints from model
    %{
      resource_limits: model[:resource_constraints] || %{},
      regulatory: model[:regulatory_constraints] || [],
      physical: model[:physical_constraints] || []
    }
  end

  defp vary_variables(variables, variation_factor) do
    Enum.map(variables, fn {var, data} ->
      if data[:projected] do
        varied_value = data.projected * (1 + :rand.normal() * variation_factor)
        {var, Map.put(data, :projected, varied_value)}
      else
        {var, data}
      end
    end)
    |> Map.new()
  end

  defp vary_events(events) do
    # Randomly modify some events
    Enum.map(events, fn event ->
      if :rand.uniform() < 0.3 do
        %{
          event
          | timing: event.timing * (0.8 + :rand.uniform() * 0.4),
            probability: event.probability * (0.9 + :rand.uniform() * 0.2)
        }
      else
        event
      end
    end)
  end

  defp find_applicable_patterns(_scenario, patterns) do
    # Find patterns that could apply to this scenario
    Enum.filter(patterns, fn pattern ->
      pattern.applicability_score > 0.7
    end)
  end

  defp apply_pattern_to_scenario(pattern, scenario) do
    # Apply learned pattern to scenario
    # This is a placeholder for complex pattern application
    scenario
  end

  defp calculate_confidence_factors(scenario) do
    %{
      variable_confidence: calculate_variable_confidence(scenario.variables),
      event_confidence: calculate_event_confidence(scenario.events),
      # High confidence in constraints
      constraint_confidence: 0.9
    }
  end

  defp identify_key_assumptions(scenario) do
    assumptions = []

    # Check for linear projection assumptions
    if Enum.any?(scenario.variables, fn {_, v} -> v[:method] == :linear end) do
      assumptions = ["Linear trend continuation" | assumptions]
    end

    # Check for system stability assumptions
    if scenario.type == :system_dynamics do
      assumptions = ["System feedback loops remain stable" | assumptions]
    end

    # Check for probabilistic assumptions
    if scenario.type == :monte_carlo do
      assumptions = ["Variables follow assumed probability distributions" | assumptions]
    end

    assumptions
  end

  defp score_internal_consistency(scenario) do
    # Check if variables are consistent with each other
    # Simplified scoring
    0.8 + :rand.uniform() * 0.2
  end

  defp score_model_alignment(scenario, model) do
    # Check alignment with environmental model
    0.7 + :rand.uniform() * 0.3
  end

  defp score_feasibility(scenario) do
    # Check if scenario respects constraints
    constraint_violations = count_constraint_violations(scenario)
    max(0, 1 - constraint_violations * 0.2)
  end

  defp score_novelty(scenario) do
    # Favor some novelty but not too extreme
    0.6 + :rand.uniform() * 0.2
  end

  defp calculate_overall_score(scores) do
    weights = %{
      consistency: 0.3,
      alignment: 0.3,
      feasibility: 0.3,
      novelty: 0.1
    }

    Enum.reduce(scores, 0, fn {metric, score}, acc ->
      acc + score * Map.get(weights, metric, 0)
    end)
  end

  defp find_scenario_in_history(scenario_id, history) do
    Enum.find_value(history, fn entry ->
      Enum.find(entry.scenarios, fn s -> s.id == scenario_id end)
    end)
  end

  defp evaluate_scenario_accuracy(scenario, state) do
    # Evaluate how accurate the scenario was (if time has passed)
    %{
      scenario_id: scenario.id,
      accuracy_metrics: calculate_accuracy_metrics(scenario),
      lessons_learned: extract_lessons(scenario, state)
    }
  end

  defp generate_scenario_id do
    "scenario_#{:erlang.unique_integer([:positive])}"
  end

  # Helper functions

  defp extract_current_values(model) do
    model[:entities]
    |> Enum.map(fn {name, entity} ->
      {name, entity[:value] || 0}
    end)
    |> Map.new()
  end

  defp extract_trends(model) do
    model[:temporal_patterns]
    |> Enum.filter(fn p -> p[:type] == :trend end)
    |> Enum.map(fn p -> {p[:variable], p[:slope] || 0} end)
    |> Map.new()
  end

  defp extract_uncertainties(_model) do
    # Default uncertainties
    %{default: 0.1}
  end

  defp apply_feedback_effects(variables, relationships) do
    # Simple feedback simulation
    Enum.reduce(relationships, variables, fn rel, vars ->
      if rel.type == :feedback do
        source_val = Map.get(vars, rel.from, 0)
        target_val = Map.get(vars, rel.to, 0)

        # Simple proportional feedback
        new_target = target_val + source_val * 0.01
        Map.put(vars, rel.to, new_target)
      else
        vars
      end
    end)
  end

  defp generate_event_details(type, _model) do
    case type do
      :threshold_breach ->
        %{variable: "resource_utilization", threshold: 0.9}

      :feedback_amplification ->
        %{loop: "demand_supply", amplification_factor: 1.5}

      :state_transition ->
        %{from_state: "normal", to_state: "stressed"}

      _ ->
        %{}
    end
  end

  defp calculate_variable_confidence(variables) do
    confidences =
      Enum.map(variables, fn {_, data} ->
        case data[:method] do
          :linear -> 0.7
          :system_dynamics -> 0.6
          :monte_carlo -> 0.5
          _ -> 0.5
        end
      end)

    if Enum.empty?(confidences) do
      0.5
    else
      Enum.sum(confidences) / length(confidences)
    end
  end

  defp calculate_event_confidence(events) do
    if Enum.empty?(events) do
      # No events is high confidence
      0.8
    else
      avg_probability = Enum.sum(Enum.map(events, &(&1[:probability] || 0.5))) / length(events)
      avg_probability
    end
  end

  defp count_constraint_violations(scenario) do
    # Count how many constraints are violated
    # Simplified - would need actual constraint checking
    0
  end

  defp calculate_accuracy_metrics(_scenario) do
    # Placeholder for actual accuracy calculation
    %{
      variable_accuracy: 0.7,
      event_accuracy: 0.6,
      timing_accuracy: 0.5
    }
  end

  defp extract_lessons(_scenario, _state) do
    # Extract lessons learned from scenario evaluation
    [
      "Linear projections tend to overestimate growth",
      "System dynamics capture feedback effects well",
      "Event timing has high uncertainty"
    ]
  end
end
