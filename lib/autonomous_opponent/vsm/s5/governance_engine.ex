defmodule AutonomousOpponent.VSM.S5.GovernanceEngine do
  @moduledoc """
  Governance engine component for S5 Policy.

  Implements decision-making processes, policy evaluation, and
  governance rule enforcement. Manages system-wide directives
  and constitutional compliance.
  """

  use GenServer
  require Logger

  defstruct [
    :decision_history,
    :policy_templates,
    :evaluation_state
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def evaluate_action(server \\ __MODULE__, action, context) do
    GenServer.call(server, {:evaluate_action, action, context})
  end

  def make_decision(server \\ __MODULE__, issue, context) do
    GenServer.call(server, {:make_decision, issue, context})
  end

  def create_policy(server \\ __MODULE__, policy_params) do
    GenServer.call(server, {:create_policy, policy_params})
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      decision_history: [],
      policy_templates: init_policy_templates(),
      evaluation_state: init_evaluation_state()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:evaluate_action, action, context}, _from, state) do
    # Evaluate action against all governance layers
    evaluation = perform_action_evaluation(action, context, state)

    # Record decision
    decision_record = %{
      timestamp: System.monotonic_time(:millisecond),
      action: action,
      evaluation: evaluation,
      context: context
    }

    new_history = [decision_record | state.decision_history] |> Enum.take(1000)
    new_state = %{state | decision_history: new_history}

    {:reply, evaluation, new_state}
  end

  @impl true
  def handle_call({:make_decision, issue, context}, _from, state) do
    # Analyze issue
    analysis = analyze_governance_issue(issue, context, state)

    # Generate decision
    decision = generate_governance_decision(analysis, context, state)

    # Create policy if needed
    decision =
      if should_create_policy?(analysis) do
        policy = create_policy_from_analysis(analysis, state.policy_templates)

        Map.put(decision, :creates_policy, true)
        |> Map.put(:policy, policy)
      else
        Map.put(decision, :creates_policy, false)
      end

    {:reply, decision, state}
  end

  @impl true
  def handle_call({:create_policy, params}, _from, state) do
    # Create policy from parameters
    policy = build_policy(params, state.policy_templates)

    # Validate policy
    case validate_policy(policy, state) do
      :ok ->
        {:reply, {:ok, policy}, state}

      {:error, reason} = error ->
        {:reply, error, state}
    end
  end

  defp init_policy_templates do
    %{
      resource_allocation: %{
        type: :resource_management,
        # 1 hour
        duration: 3_600_000,
        # 5 minutes
        review_interval: 300_000,
        directives: [:optimize, :balance, :prioritize]
      },
      emergency_response: %{
        type: :crisis_management,
        # 30 minutes
        duration: 1_800_000,
        # 1 minute
        review_interval: 60_000,
        directives: [:mitigate, :isolate, :recover]
      },
      adaptation: %{
        type: :system_evolution,
        # Permanent
        duration: nil,
        # 1 hour
        review_interval: 3_600_000,
        directives: [:learn, :adapt, :evolve]
      }
    }
  end

  defp init_evaluation_state do
    %{
      evaluation_criteria: %{
        identity_alignment: 0.3,
        value_compliance: 0.3,
        goal_contribution: 0.2,
        rule_adherence: 0.1,
        constitutional_compliance: 0.1
      },
      threshold: 0.6
    }
  end

  defp perform_action_evaluation(action, context, state) do
    scores = %{
      identity_alignment: evaluate_identity_alignment(action, context.identity),
      value_compliance: evaluate_value_compliance(action, context.values),
      goal_contribution: evaluate_goal_contribution(action, context.goals),
      rule_adherence: evaluate_rule_adherence(action, context.rules),
      constitutional_compliance: evaluate_constitutional_compliance(action, context.invariants)
    }

    # Calculate weighted score
    weighted_score = calculate_weighted_score(scores, state.evaluation_state.evaluation_criteria)

    # Determine decision
    decision =
      if weighted_score >= state.evaluation_state.threshold do
        :approved
      else
        :rejected
      end

    %{
      decision: decision,
      score: weighted_score,
      scores: scores,
      reasons: generate_evaluation_reasons(scores, decision)
    }
  end

  defp analyze_governance_issue(issue, context, state) do
    %{
      issue_type: categorize_issue(issue),
      severity: assess_issue_severity(issue),
      affected_subsystems: identify_affected_subsystems(issue),
      historical_precedent: find_historical_precedent(issue, state.decision_history),
      recommended_actions: generate_recommended_actions(issue, context)
    }
  end

  defp generate_governance_decision(analysis, context, state) do
    # Base decision on analysis and context
    primary_action = select_primary_action(analysis.recommended_actions, context)

    %{
      issue_type: analysis.issue_type,
      severity: analysis.severity,
      decision: primary_action,
      directives: generate_directives(primary_action, analysis),
      monitoring_requirements: determine_monitoring_requirements(analysis),
      success_criteria: define_success_criteria(primary_action, analysis)
    }
  end

  defp should_create_policy?(analysis) do
    analysis.severity in [:high, :critical] or
      analysis.historical_precedent == nil
  end

  defp create_policy_from_analysis(analysis, templates) do
    template = select_policy_template(analysis.issue_type, templates)

    %{
      id: "policy_#{:erlang.unique_integer([:positive])}",
      type: template.type,
      issue_type: analysis.issue_type,
      directives: customize_directives(template.directives, analysis),
      affected_subsystems: analysis.affected_subsystems,
      duration: template.duration,
      review_interval: template.review_interval,
      success_criteria: analysis[:success_criteria],
      created_at: System.monotonic_time(:millisecond)
    }
  end

  defp build_policy(params, templates) do
    template = Map.get(templates, params[:template], templates.adaptation)

    Map.merge(template, params)
    |> Map.put(:id, "policy_#{:erlang.unique_integer([:positive])}")
    |> Map.put(:created_at, System.monotonic_time(:millisecond))
  end

  defp validate_policy(policy, _state) do
    cond do
      policy.directives == [] ->
        {:error, :no_directives}

      policy.affected_subsystems == nil ->
        {:error, :no_target_subsystems}

      true ->
        :ok
    end
  end

  defp evaluate_identity_alignment(action, identity) do
    # Check if action aligns with system identity
    if action[:purpose] in identity.core_capabilities do
      1.0
    else
      # Check trait alignment
      trait_alignment = calculate_trait_alignment(action, identity.personality_traits)
      trait_alignment
    end
  end

  defp evaluate_value_compliance(action, values) do
    # Check action against values
    violated_values = find_violated_values(action, values)

    if Enum.empty?(violated_values) do
      # Check positive value contribution
      value_contribution = calculate_value_contribution(action, values.core_values)
      value_contribution
    else
      0.0
    end
  end

  defp evaluate_goal_contribution(action, goals) do
    # Check if action contributes to goals
    contributing_goals =
      Enum.filter(goals, fn goal ->
        contributes_to_goal?(action, goal)
      end)

    if Enum.empty?(contributing_goals) do
      # Neutral
      0.5
    else
      # Weight by goal priority
      total_priority =
        contributing_goals
        |> Enum.map(& &1.priority)
        |> Enum.sum()

      total_priority / length(goals)
    end
  end

  defp evaluate_rule_adherence(action, rules) do
    # Check action against governance rules
    if violates_rules?(action, rules) do
      0.0
    else
      1.0
    end
  end

  defp evaluate_constitutional_compliance(action, invariants) do
    # Check constitutional compliance
    violations =
      Enum.filter(invariants, fn {invariant, _desc} ->
        violates_invariant?(action, invariant)
      end)

    if Enum.empty?(violations) do
      1.0
    else
      0.0
    end
  end

  defp calculate_weighted_score(scores, criteria) do
    Enum.reduce(scores, 0.0, fn {criterion, score}, acc ->
      weight = Map.get(criteria, criterion, 0.0)
      acc + score * weight
    end)
  end

  defp generate_evaluation_reasons(scores, decision) do
    low_scores = Enum.filter(scores, fn {_criterion, score} -> score < 0.5 end)

    if decision == :rejected do
      Enum.map(low_scores, fn {criterion, score} ->
        "Low #{criterion}: #{Float.round(score, 2)}"
      end)
    else
      ["All criteria met"]
    end
  end

  defp categorize_issue(issue) do
    cond do
      issue[:type] -> issue.type
      issue[:resource_shortage] -> :resource_management
      issue[:threat] -> :security
      issue[:opportunity] -> :strategic
      true -> :general
    end
  end

  defp assess_issue_severity(issue) do
    issue[:severity] || :medium
  end

  defp identify_affected_subsystems(issue) do
    issue[:affected_subsystems] || [:all]
  end

  defp find_historical_precedent(issue, history) do
    Enum.find(history, fn record ->
      similar_issue?(record[:issue] || record[:action], issue)
    end)
  end

  defp generate_recommended_actions(issue, _context) do
    case categorize_issue(issue) do
      :resource_management ->
        [:optimize_allocation, :request_resources, :reduce_consumption]

      :security ->
        [:activate_defenses, :isolate_threat, :assess_damage]

      :strategic ->
        [:analyze_opportunity, :allocate_resources, :monitor_progress]

      _ ->
        [:investigate, :monitor, :report]
    end
  end

  defp select_primary_action(recommended_actions, _context) do
    # Select first recommended action (simplified)
    Enum.at(recommended_actions, 0, :investigate)
  end

  defp generate_directives(action, analysis) do
    base_directives = [
      {:priority, severity_to_priority(analysis.severity)},
      {:action, action},
      {:targets, analysis.affected_subsystems}
    ]

    # Add specific directives based on action
    case action do
      :optimize_allocation ->
        base_directives ++ [{:method, :pareto_optimization}]

      :activate_defenses ->
        base_directives ++ [{:mode, :active_defense}]

      _ ->
        base_directives
    end
  end

  defp determine_monitoring_requirements(analysis) do
    case analysis.severity do
      :critical -> :continuous
      :high -> :frequent
      :medium -> :periodic
      _ -> :minimal
    end
  end

  defp define_success_criteria(action, _analysis) do
    case action do
      :optimize_allocation ->
        %{metric: :resource_efficiency, target: 0.8, timeframe: 3_600_000}

      :activate_defenses ->
        %{metric: :threat_mitigation, target: 1.0, timeframe: 300_000}

      _ ->
        %{metric: :completion, target: 1.0, timeframe: 7_200_000}
    end
  end

  defp select_policy_template(issue_type, templates) do
    case issue_type do
      :resource_management -> templates.resource_allocation
      :security -> templates.emergency_response
      _ -> templates.adaptation
    end
  end

  defp customize_directives(template_directives, analysis) do
    # Customize directives based on analysis
    template_directives ++ analysis[:specific_directives] || []
  end

  defp calculate_trait_alignment(action, traits) do
    # Simple trait alignment calculation
    relevant_traits = extract_relevant_traits(action)

    if Enum.empty?(relevant_traits) do
      0.5
    else
      trait_scores =
        Enum.map(relevant_traits, fn trait ->
          Map.get(traits, trait, 0.5)
        end)

      Enum.sum(trait_scores) / length(trait_scores)
    end
  end

  defp find_violated_values(action, values) do
    # Check for value violations
    # Simplified
    []
  end

  defp calculate_value_contribution(action, core_values) do
    # Calculate how action contributes to values
    # Simplified
    0.7
  end

  defp contributes_to_goal?(action, goal) do
    action[:contributes_to] == goal.id or
      action[:type] == goal[:type]
  end

  defp violates_rules?(_action, _rules) do
    # Simplified
    false
  end

  defp violates_invariant?(_action, _invariant) do
    # Simplified
    false
  end

  defp similar_issue?(issue1, issue2) do
    issue1[:type] == issue2[:type]
  end

  defp severity_to_priority(severity) do
    case severity do
      :critical -> :maximum
      :high -> :high
      :medium -> :normal
      _ -> :low
    end
  end

  defp extract_relevant_traits(action) do
    case action[:type] do
      :optimization -> [:efficiency, :adaptability]
      :defense -> [:resilience]
      :exploration -> [:curiosity]
      :collaboration -> [:cooperation]
      _ -> []
    end
  end
end
