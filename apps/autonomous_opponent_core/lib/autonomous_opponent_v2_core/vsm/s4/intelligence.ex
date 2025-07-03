defmodule AutonomousOpponentV2Core.VSM.S4.Intelligence do
  @moduledoc """
  System 4: Intelligence - The environmental scanner and future modeler.
  
  S4 looks OUTWARD and FORWARD. It scans the environment beyond the
  immediate operations, detects patterns, and models possible futures.
  It feeds intelligence to S5 for policy decisions and S3 for operational
  adjustments.
  
  Key responsibilities:
  - Environmental scanning and pattern detection
  - Future scenario modeling
  - Pattern storage using Vector Store and HNSW
  - Intelligence reports to S5 and S3
  - Learning from S3 audit trails
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: Algedonic
  alias AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore
  alias AutonomousOpponentV2Core.Core.Metrics
  
  defstruct [
    :vector_store,
    :environmental_model,
    :pattern_detector,
    :scenario_modeler,
    :intelligence_reports,
    :learning_queue,
    :health_metrics
  ]
  
  # Intelligence thresholds
  @pattern_confidence_threshold 0.7
  @scenario_probability_threshold 0.6
  @environmental_scan_interval 10_000  # 10 seconds
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def scan_environment do
    GenServer.call(__MODULE__, :scan_environment)
  end
  
  def model_scenario(parameters) do
    GenServer.call(__MODULE__, {:model_scenario, parameters})
  end
  
  def get_intelligence_report do
    GenServer.call(__MODULE__, :get_intelligence)
  end
  
  def learn_from_audit(audit_data) do
    GenServer.cast(__MODULE__, {:learn, audit_data})
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Start Vector Store for pattern memory
    {:ok, vector_store} = VectorStore.start_link(
      name: :s4_vector_store,
      vector_dim: 64,
      subspaces: 8
    )
    
    # Subscribe to variety channels from other subsystems
    EventBus.subscribe(:s3_to_s4)  # Audit data from S3
    EventBus.subscribe(:external_environment)  # External signals
    EventBus.subscribe(:algedonic_intervention)  # Emergency overrides
    
    # Start environmental scanning
    Process.send_after(self(), :environmental_scan, @environmental_scan_interval)
    Process.send_after(self(), :report_health, 1000)
    
    state = %__MODULE__{
      vector_store: vector_store,
      environmental_model: init_environmental_model(),
      pattern_detector: init_pattern_detector(),
      scenario_modeler: init_scenario_modeler(),
      intelligence_reports: [],
      learning_queue: :queue.new(),
      health_metrics: %{
        patterns_detected: 0,
        scenarios_modeled: 0,
        predictions_accurate: 0,
        predictions_total: 0,
        environmental_complexity: 0.5
      }
    }
    
    Logger.info("S4 Intelligence online - scanning the horizon")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:scan_environment, _from, state) do
    # Perform environmental scan
    scan_result = perform_environmental_scan(state)
    
    # Detect patterns in the scan
    patterns = detect_patterns(scan_result, state)
    
    # Store significant patterns
    significant_patterns = Enum.filter(patterns, fn p -> 
      p.confidence > @pattern_confidence_threshold 
    end)
    
    Enum.each(significant_patterns, fn pattern ->
      VectorStore.store_pattern(state.vector_store, pattern, %{
        source: :environmental_scan,
        timestamp: DateTime.utc_now()
      })
    end)
    
    # Update environmental model
    new_model = update_environmental_model(state.environmental_model, scan_result, patterns)
    
    # Generate intelligence report
    report = generate_intelligence_report(new_model, patterns, state)
    
    # Send to S5
    send_intelligence_to_s5(report)
    
    new_state = %{state | 
      environmental_model: new_model,
      intelligence_reports: [report | state.intelligence_reports] |> Enum.take(100)
    }
    
    {:reply, {:ok, report}, new_state}
  end
  
  @impl true
  def handle_call({:model_scenario, parameters}, _from, state) do
    # Find similar historical patterns
    {:ok, similar_patterns} = VectorStore.find_similar_patterns(
      state.vector_store,
      parameters,
      5
    )
    
    # Model possible futures based on patterns
    scenarios = model_futures(parameters, similar_patterns, state)
    
    # Filter by probability
    likely_scenarios = Enum.filter(scenarios, fn s -> 
      s.probability > @scenario_probability_threshold 
    end)
    
    # Update metrics
    new_metrics = Map.update!(state.health_metrics, :scenarios_modeled, &(&1 + 1))
    
    {:reply, {:ok, likely_scenarios}, %{state | health_metrics: new_metrics}}
  end
  
  @impl true
  def handle_call(:get_intelligence, _from, state) do
    report = %{
      environmental_state: summarize_environment(state.environmental_model),
      detected_patterns: get_recent_patterns(state),
      future_scenarios: get_active_scenarios(state),
      recommendations: generate_recommendations(state)
    }
    
    {:reply, report, state}
  end
  
  @impl true
  def handle_cast({:learn, audit_data}, state) do
    # Queue learning data
    new_queue = :queue.in(audit_data, state.learning_queue)
    
    # Process if queue is getting full
    new_state = if :queue.len(new_queue) > 10 do
      process_learning_queue(%{state | learning_queue: new_queue})
    else
      %{state | learning_queue: new_queue}
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :s3_to_s4, audit_entry}, state) do
    # Learn from S3's decisions
    Logger.debug("S4 learning from S3 audit: #{inspect(audit_entry)}")
    
    # Extract patterns from audit data
    patterns = extract_patterns_from_audit(audit_entry)
    
    # Store patterns for future reference
    Enum.each(patterns, fn pattern ->
      VectorStore.store_pattern(state.vector_store, pattern, %{
        source: :s3_audit,
        decision_context: audit_entry[:decision_context]
      })
    end)
    
    # Update learning metrics
    new_state = update_learning_metrics(state, patterns)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:environmental_scan, state) do
    Process.send_after(self(), :environmental_scan, @environmental_scan_interval)
    
    # Regular environmental scan
    scan_result = perform_environmental_scan(state)
    patterns = detect_patterns(scan_result, state)
    
    # Check for significant changes
    if environmental_change_significant?(scan_result, state) do
      Logger.info("S4 detected significant environmental change")
      
      # Model new scenarios
      scenarios = model_futures(scan_result, [], state)
      
      # Alert S5 if critical
      if Enum.any?(scenarios, &(&1.severity == :critical)) do
        alert_s5_critical_scenario(scenarios, state)
      end
    end
    
    # Update model
    new_model = update_environmental_model(state.environmental_model, scan_result, patterns)
    
    # Update metrics
    new_metrics = update_health_metrics(state.health_metrics, new_model)
    
    {:noreply, %{state | 
      environmental_model: new_model,
      health_metrics: new_metrics
    }}
  end
  
  @impl true
  def handle_info(:report_health, state) do
    Process.send_after(self(), :report_health, 1000)
    
    health = calculate_health_score(state)
    EventBus.publish(:s4_health, %{health: health})
    
    # Report based on intelligence quality
    cond do
      health < 0.3 ->
        Algedonic.report_pain(:s4_intelligence, :blind, 1.0 - health)
        
      state.health_metrics.environmental_complexity > 0.9 ->
        Algedonic.report_pain(:s4_intelligence, :overwhelmed, 
          state.health_metrics.environmental_complexity)
        
      prediction_accuracy(state) < 0.5 ->
        Algedonic.report_pain(:s4_intelligence, :confused, 0.7)
        
      health > 0.9 && prediction_accuracy(state) > 0.8 ->
        Algedonic.report_pleasure(:s4_intelligence, :prescient, health)
        
      true ->
        :ok
    end
    
    {:noreply, state}
  end
  
  # Private Functions
  
  defp init_environmental_model do
    %{
      complexity: 0.5,
      volatility: 0.3,
      trends: [],
      threats: [],
      opportunities: [],
      last_scan: DateTime.utc_now()
    }
  end
  
  defp init_pattern_detector do
    %{
      algorithms: [:statistical, :temporal, :structural, :behavioral],
      sensitivity: 0.7,
      history_window: 100
    }
  end
  
  defp init_scenario_modeler do
    %{
      time_horizons: [:immediate, :short_term, :medium_term, :long_term],
      monte_carlo_runs: 100,
      confidence_intervals: [0.5, 0.75, 0.95]
    }
  end
  
  defp perform_environmental_scan(state) do
    # Gather data from various sources
    # In real implementation, would integrate with external systems
    
    %{
      timestamp: DateTime.utc_now(),
      metrics: gather_system_metrics(),
      external_signals: gather_external_signals(),
      internal_state: gather_internal_state(state),
      anomalies: detect_anomalies(state)
    }
  end
  
  defp detect_patterns(scan_result, state) do
    # Apply pattern detection algorithms
    state.pattern_detector.algorithms
    |> Enum.flat_map(fn algorithm ->
      detect_patterns_with_algorithm(algorithm, scan_result)
    end)
    |> Enum.filter(fn pattern ->
      pattern.confidence > 0.5
    end)
  end
  
  defp detect_patterns_with_algorithm(algorithm, scan_result) do
    case algorithm do
      :statistical ->
        detect_statistical_patterns(scan_result)
        
      :temporal ->
        detect_temporal_patterns(scan_result)
        
      :structural ->
        detect_structural_patterns(scan_result)
        
      :behavioral ->
        detect_behavioral_patterns(scan_result)
    end
  end
  
  defp detect_statistical_patterns(scan_result) do
    # Simplified statistical pattern detection
    metrics = scan_result.metrics
    
    patterns = []
    
    # Check for distribution changes
    if metrics[:variance] > 2.0 do
      patterns ++ [%{
        type: :statistical,
        subtype: :distribution,
        confidence: 0.8,
        description: "High variance detected",
        mean: metrics[:mean],
        variance: metrics[:variance]
      }]
    else
      patterns
    end
  end
  
  defp detect_temporal_patterns(scan_result) do
    # Simplified temporal pattern detection
    [
      %{
        type: :temporal,
        subtype: :trend,
        confidence: 0.7,
        description: "Upward trend detected",
        direction: :increasing,
        strength: 0.6
      }
    ]
  end
  
  defp detect_structural_patterns(_scan_result) do
    # Simplified structural pattern detection
    []
  end
  
  defp detect_behavioral_patterns(scan_result) do
    # Check for anomalies
    if length(scan_result.anomalies) > 0 do
      [%{
        type: :behavioral,
        subtype: :anomaly,
        confidence: 0.9,
        description: "Anomalous behavior detected",
        count: length(scan_result.anomalies),
        severity: :medium
      }]
    else
      []
    end
  end
  
  defp model_futures(parameters, similar_patterns, state) do
    # Monte Carlo simulation of possible futures
    1..state.scenario_modeler.monte_carlo_runs
    |> Enum.map(fn _run ->
      simulate_scenario(parameters, similar_patterns, state)
    end)
    |> aggregate_scenarios()
  end
  
  defp simulate_scenario(parameters, similar_patterns, _state) do
    # Simplified scenario simulation
    %{
      scenario: "Scenario based on #{inspect(parameters)}",
      probability: :rand.uniform(),
      impact: Enum.random([:low, :medium, :high]),
      time_horizon: Enum.random([:immediate, :short_term, :medium_term]),
      similar_patterns: length(similar_patterns)
    }
  end
  
  defp aggregate_scenarios(scenarios) do
    # Group and aggregate similar scenarios
    scenarios
    |> Enum.group_by(& &1.impact)
    |> Enum.map(fn {impact, group} ->
      %{
        impact: impact,
        probability: Enum.sum(Enum.map(group, & &1.probability)) / length(group),
        count: length(group),
        severity: impact_to_severity(impact)
      }
    end)
  end
  
  defp generate_intelligence_report(model, patterns, _state) do
    %{
      timestamp: DateTime.utc_now(),
      environmental_model: model,
      patterns: patterns,
      assessment: assess_situation(model, patterns),
      recommendations: generate_tactical_recommendations(model, patterns)
    }
  end
  
  defp send_intelligence_to_s5(report) do
    VarietyChannel.transmit(:s4_to_s5, %{
      intelligence_report: report,
      urgency: report.assessment.urgency
    })
    
    EventBus.publish(:s4_intelligence, report)
  end
  
  defp update_environmental_model(current_model, scan_result, patterns) do
    %{current_model |
      complexity: calculate_complexity(scan_result, patterns),
      volatility: calculate_volatility(scan_result, current_model),
      trends: update_trends(current_model.trends, patterns),
      last_scan: scan_result.timestamp
    }
  end
  
  defp environmental_change_significant?(scan_result, state) do
    current_complexity = calculate_complexity(scan_result, [])
    complexity_change = abs(current_complexity - state.environmental_model.complexity)
    
    complexity_change > 0.2 || length(scan_result.anomalies) > 3
  end
  
  defp alert_s5_critical_scenario(scenarios, _state) do
    EventBus.publish(:s5_policy, {:critical_scenario, scenarios})
  end
  
  defp process_learning_queue(state) do
    # Process all queued learning data
    queue_list = :queue.to_list(state.learning_queue)
    
    patterns = Enum.flat_map(queue_list, &extract_patterns_from_audit/1)
    
    # Update prediction accuracy based on outcomes
    new_metrics = Enum.reduce(patterns, state.health_metrics, fn pattern, metrics ->
      if pattern[:outcome] do
        %{metrics |
          predictions_total: metrics.predictions_total + 1,
          predictions_accurate: metrics.predictions_accurate + 
            (if pattern.outcome == :success, do: 1, else: 0)
        }
      else
        metrics
      end
    end)
    
    %{state | 
      learning_queue: :queue.new(),
      health_metrics: new_metrics
    }
  end
  
  defp extract_patterns_from_audit(audit_entry) do
    # Extract learnable patterns from audit data
    [
      %{
        type: :behavioral,
        subtype: :decision,
        decision_type: audit_entry[:type],
        outcome: audit_entry[:outcome],
        confidence: 0.8
      }
    ]
  end
  
  defp update_learning_metrics(state, patterns) do
    new_metrics = Map.update!(state.health_metrics, :patterns_detected, 
      &(&1 + length(patterns)))
    
    %{state | health_metrics: new_metrics}
  end
  
  defp calculate_health_score(state) do
    metrics = state.health_metrics
    
    # Base health on prediction accuracy and pattern detection
    prediction_score = prediction_accuracy(state)
    pattern_score = min(1.0, metrics.patterns_detected / 100)
    complexity_penalty = metrics.environmental_complexity * 0.2
    
    max(0.0, (prediction_score * 0.6 + pattern_score * 0.4) - complexity_penalty)
  end
  
  defp prediction_accuracy(state) do
    metrics = state.health_metrics
    
    if metrics.predictions_total > 0 do
      metrics.predictions_accurate / metrics.predictions_total
    else
      0.5  # No predictions yet, assume average
    end
  end
  
  defp update_health_metrics(metrics, model) do
    %{metrics |
      environmental_complexity: model.complexity
    }
  end
  
  # Utility functions
  
  defp gather_system_metrics do
    %{
      cpu: :rand.uniform(),
      memory: :rand.uniform(),
      throughput: :rand.uniform() * 1000,
      mean: :rand.uniform() * 10,
      variance: :rand.uniform() * 5
    }
  end
  
  defp gather_external_signals do
    # In real implementation, would connect to external data sources
    []
  end
  
  defp gather_internal_state(_state) do
    %{
      subsystems_active: 5,
      variety_flow: :normal
    }
  end
  
  defp detect_anomalies(_state) do
    # Simplified anomaly detection
    if :rand.uniform() > 0.8 do
      [%{type: :performance, severity: :low}]
    else
      []
    end
  end
  
  defp summarize_environment(model) do
    %{
      complexity: model.complexity,
      volatility: model.volatility,
      trend_count: length(model.trends)
    }
  end
  
  defp get_recent_patterns(state) do
    # Get patterns from recent intelligence reports
    state.intelligence_reports
    |> Enum.take(5)
    |> Enum.flat_map(& &1.patterns)
  end
  
  defp get_active_scenarios(_state) do
    # Return currently modeled scenarios
    []
  end
  
  defp generate_recommendations(state) do
    if state.environmental_model.volatility > 0.7 do
      ["Increase monitoring frequency", "Prepare contingency plans"]
    else
      ["Maintain current operations"]
    end
  end
  
  defp assess_situation(model, patterns) do
    urgency = if model.volatility > 0.8 || length(patterns) > 5 do
      :high
    else
      :normal
    end
    
    %{
      urgency: urgency,
      stability: 1.0 - model.volatility,
      pattern_count: length(patterns)
    }
  end
  
  defp generate_tactical_recommendations(_model, patterns) do
    patterns
    |> Enum.map(fn pattern ->
      case pattern.type do
        :statistical -> "Adjust resource allocation"
        :temporal -> "Monitor trend development"
        :behavioral -> "Investigate anomaly source"
        _ -> "Continue monitoring"
      end
    end)
    |> Enum.uniq()
  end
  
  defp calculate_complexity(_scan_result, patterns) do
    # Complexity based on pattern diversity
    min(1.0, length(patterns) * 0.1 + :rand.uniform() * 0.3)
  end
  
  defp calculate_volatility(scan_result, current_model) do
    # Rate of change
    time_delta = DateTime.diff(scan_result.timestamp, current_model.last_scan)
    
    if time_delta > 0 do
      min(1.0, length(scan_result.anomalies) * 0.2)
    else
      current_model.volatility
    end
  end
  
  defp update_trends(current_trends, new_patterns) do
    temporal_patterns = Enum.filter(new_patterns, & &1.type == :temporal)
    
    (current_trends ++ temporal_patterns)
    |> Enum.take(-20)  # Keep last 20 trends
  end
  
  defp impact_to_severity(impact) do
    case impact do
      :high -> :critical
      :medium -> :medium
      :low -> :low
    end
  end
end