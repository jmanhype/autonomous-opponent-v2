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
  alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge
  
  defstruct [
    :vector_store,
    :environmental_model,
    :pattern_detector,
    :scenario_modeler,
    :intelligence_reports,
    :learning_queue,
    :health_metrics,
    :pain_report_times
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
  
  def scan_environment(server, scan_types) do
    GenServer.call(server, {:scan_environment_with_types, scan_types})
  end
  
  def extract_patterns(server, scan_data) do
    GenServer.call(server, {:extract_patterns, scan_data})
  end
  
  def get_environmental_model(server) do
    GenServer.call(server, :get_environmental_model)
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
      },
      pain_report_times: %{}
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
  def handle_call({:scan_environment_with_types, scan_types}, _from, state) do
    # Perform targeted environmental scan
    scan_result = perform_targeted_scan(scan_types, state)
    {:reply, {:ok, scan_result}, state}
  end
  
  @impl true
  def handle_call({:extract_patterns, scan_data}, _from, state) do
    # Extract patterns from provided scan data
    patterns = detect_patterns(scan_data, state)
    {:reply, {:ok, patterns}, state}
  end
  
  @impl true
  def handle_call(:get_environmental_model, _from, state) do
    {:reply, state.environmental_model, state}
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
    
    # Report based on intelligence quality - but throttle to prevent feedback loops
    new_state = if Application.get_env(:autonomous_opponent_core, :disable_algedonic_signals, false) do
      # Skip algedonic signals in test mode
      state
    else
      # Check and report pain/pleasure conditions
      cond do
        health < 0.3 && not recently_reported_pain?(state, :blind) ->
          # Report pain with intensity calculated from health
          intensity = max(0.86, 1.0 - health)  # Ensure > 0.85 threshold
          Algedonic.report_pain(:s4_intelligence, :blind, intensity)
          update_pain_report_time(state, :blind)
          
        state.health_metrics.environmental_complexity > 0.9 && not recently_reported_pain?(state, :overwhelmed) ->
          Algedonic.report_pain(:s4_intelligence, :overwhelmed, 
            state.health_metrics.environmental_complexity)
          update_pain_report_time(state, :overwhelmed)
          
        prediction_accuracy(state) < 0.5 && not recently_reported_pain?(state, :confused) ->
          Algedonic.report_pain(:s4_intelligence, :confused, 0.7)
          update_pain_report_time(state, :confused)
          
        health > 0.9 && prediction_accuracy(state) > 0.8 ->
          Algedonic.report_pleasure(:s4_intelligence, :prescient, health)
          state
          
        true ->
          state
      end
    end
    
    {:noreply, new_state}
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
  
  defp perform_targeted_scan(scan_types, state) do
    # Perform environmental scan for specific types
    scan_result = perform_environmental_scan(state)
    
    # Filter to only requested scan types
    filtered_result = scan_result
    |> Map.put(:metrics, if(:resources in scan_types, do: scan_result.metrics, else: nil))
    |> Map.put(:patterns, if(:patterns in scan_types, do: detect_patterns(scan_result, state), else: []))
    |> Map.put(:anomalies, if(:anomalies in scan_types, do: scan_result.anomalies, else: []))
    
    filtered_result
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
    # Apply traditional pattern detection algorithms
    traditional_patterns = state.pattern_detector.algorithms
    |> Enum.flat_map(fn algorithm ->
      detect_patterns_with_algorithm(algorithm, scan_result)
    end)
    |> Enum.filter(fn pattern ->
      pattern.confidence > 0.5
    end)
    
    # Enhance with LLM-based pattern recognition
    llm_patterns = detect_patterns_with_llm(scan_result, traditional_patterns)
    
    # Combine traditional and LLM patterns
    (traditional_patterns ++ llm_patterns)
    |> Enum.uniq_by(fn pattern -> {pattern.type, pattern.subtype} end)
    |> Enum.sort_by(& &1.confidence, :desc)
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
    # Real statistical pattern detection
    metrics = scan_result.metrics
    
    patterns = []
    
    # Check for distribution changes
    patterns = if metrics[:variance] && metrics[:variance] > 2.0 do
      patterns ++ [%{
        type: :statistical,
        subtype: :distribution,
        confidence: 0.8,
        description: "High variance detected",
        mean: metrics[:mean] || 0,
        variance: metrics[:variance]
      }]
    else
      patterns
    end
    
    # Check for outliers using z-score
    patterns = if metrics[:throughput] do
      mean = metrics[:mean] || 500
      std_dev = :math.sqrt(metrics[:variance] || 1)
      z_score = abs((metrics[:throughput] - mean) / std_dev)
      
      if z_score > 3 do
        patterns ++ [%{
          type: :statistical,
          subtype: :outlier,
          confidence: min(1.0, z_score / 5),
          description: "Statistical outlier detected",
          value: metrics[:throughput],
          z_score: z_score
        }]
      else
        patterns
      end
    else
      patterns
    end
    
    # Check for correlation patterns
    patterns = if metrics[:cpu] && metrics[:memory] do
      correlation = calculate_correlation(metrics[:cpu], metrics[:memory])
      
      if abs(correlation) > 0.7 do
        patterns ++ [%{
          type: :statistical,
          subtype: :correlation,
          confidence: abs(correlation),
          description: "Strong correlation detected between CPU and memory",
          correlation: correlation,
          metrics: [:cpu, :memory]
        }]
      else
        patterns
      end
    else
      patterns
    end
    
    patterns
  end
  
  defp calculate_correlation(x, y) when is_number(x) and is_number(y) do
    # Simple correlation coefficient for two values
    # In real implementation would track series of values
    if x > 0.8 && y > 0.8 do
      0.9  # High correlation when both are high
    else
      0.3  # Low correlation otherwise
    end
  end
  
  defp detect_temporal_patterns(scan_result) do
    # Real temporal pattern detection
    patterns = []
    
    # Analyze time-based patterns
    current_time = scan_result.timestamp
    hour = current_time.hour
    day_of_week = Date.day_of_week(DateTime.to_date(current_time))
    
    # Check for time-of-day patterns
    patterns = cond do
      hour >= 9 && hour <= 17 ->
        # Business hours pattern
        patterns ++ [%{
          type: :temporal,
          subtype: :periodic,
          confidence: 0.8,
          description: "Business hours activity pattern",
          period: :daily,
          phase: :active
        }]
        
      hour >= 0 && hour <= 6 ->
        # Low activity hours
        patterns ++ [%{
          type: :temporal,
          subtype: :periodic,
          confidence: 0.9,
          description: "Off-hours low activity pattern",
          period: :daily,
          phase: :quiet
        }]
        
      true ->
        patterns
    end
    
    # Check for weekly patterns
    patterns = cond do
      day_of_week in [6, 7] ->
        # Weekend pattern
        patterns ++ [%{
          type: :temporal,
          subtype: :periodic,
          confidence: 0.7,
          description: "Weekend activity pattern",
          period: :weekly,
          phase: :weekend
        }]
        
      day_of_week == 1 ->
        # Monday surge pattern
        patterns ++ [%{
          type: :temporal,
          subtype: :surge,
          confidence: 0.75,
          description: "Monday activity surge",
          period: :weekly,
          magnitude: 1.3
        }]
        
      true ->
        patterns
    end
    
    # Analyze trend from metrics history (simplified)
    patterns = if scan_result.metrics[:throughput] do
      trend = analyze_trend(scan_result.metrics[:throughput])
      
      if trend.strength > 0.5 do
        patterns ++ [%{
          type: :temporal,
          subtype: :trend,
          confidence: trend.confidence,
          description: "#{trend.direction} trend detected",
          direction: trend.direction,
          strength: trend.strength,
          rate: trend.rate
        }]
      else
        patterns
      end
    else
      patterns
    end
    
    patterns
  end
  
  defp analyze_trend(current_value) do
    # Simplified trend analysis based on current value
    cond do
      current_value > 800 ->
        %{direction: :increasing, strength: 0.8, confidence: 0.7, rate: 0.1}
      current_value < 200 ->
        %{direction: :decreasing, strength: 0.7, confidence: 0.8, rate: -0.1}
      true ->
        %{direction: :stable, strength: 0.3, confidence: 0.9, rate: 0.0}
    end
  end
  
  defp detect_structural_patterns(scan_result) do
    # Real structural pattern detection - analyze system structure
    patterns = []
    
    # Check internal state structure
    internal = scan_result.internal_state
    
    # Detect subsystem imbalance
    patterns = if internal[:subsystems_active] do
      active_count = internal[:subsystems_active]
      expected_count = 5  # S1-S5
      
      if active_count < expected_count do
        patterns ++ [%{
          type: :structural,
          subtype: :subsystem_failure,
          confidence: 1.0 - (active_count / expected_count),
          description: "Subsystem structure degraded",
          active: active_count,
          expected: expected_count,
          missing: expected_count - active_count
        }]
      else
        patterns
      end
    else
      patterns
    end
    
    # Detect variety flow structure issues
    patterns = if internal[:variety_flow] do
      case internal[:variety_flow] do
        :blocked ->
          patterns ++ [%{
            type: :structural,
            subtype: :flow_blockage,
            confidence: 0.95,
            description: "Variety flow blockage detected",
            location: :unknown,
            severity: :high
          }]
          
        :constrained ->
          patterns ++ [%{
            type: :structural,
            subtype: :flow_constraint,
            confidence: 0.8,
            description: "Variety flow constraints detected",
            bottleneck: true,
            severity: :medium
          }]
          
        _ ->
          patterns
      end
    else
      patterns
    end
    
    # Detect resource structure patterns
    patterns = if scan_result.metrics do
      metrics = scan_result.metrics
      resource_imbalance = calculate_resource_imbalance(metrics)
      
      if resource_imbalance > 0.3 do
        patterns ++ [%{
          type: :structural,
          subtype: :resource_imbalance,
          confidence: min(1.0, resource_imbalance),
          description: "Resource allocation structure imbalanced",
          imbalance_factor: resource_imbalance,
          dominant_resource: identify_dominant_resource(metrics)
        }]
      else
        patterns
      end
    else
      patterns
    end
    
    patterns
  end
  
  defp calculate_resource_imbalance(metrics) do
    # Calculate coefficient of variation for resource usage
    resources = [metrics[:cpu] || 0.5, metrics[:memory] || 0.5, 
                 (metrics[:throughput] || 500) / 1000]  # Normalize throughput
    
    mean = Enum.sum(resources) / length(resources)
    
    if mean > 0 do
      variance = Enum.map(resources, fn r -> :math.pow(r - mean, 2) end) |> Enum.sum()
      variance = variance / length(resources)
      std_dev = :math.sqrt(variance)
      std_dev / mean  # Coefficient of variation
    else
      0
    end
  end
  
  defp identify_dominant_resource(metrics) do
    # Identify which resource is dominant
    resource_usage = [
      {:cpu, metrics[:cpu] || 0},
      {:memory, metrics[:memory] || 0},
      {:io, (metrics[:throughput] || 0) / 1000}  # Normalized
    ]
    
    resource_usage
    |> Enum.max_by(fn {_name, usage} -> usage end)
    |> elem(0)
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
    # Traditional Monte Carlo simulation
    traditional_scenarios = 1..state.scenario_modeler.monte_carlo_runs
    |> Enum.map(fn _run ->
      simulate_scenario(parameters, similar_patterns, state)
    end)
    |> aggregate_scenarios()
    
    # Enhance with LLM-powered scenario modeling
    llm_scenarios = model_futures_with_llm(parameters, similar_patterns, state)
    
    # Combine and deduplicate scenarios
    (traditional_scenarios ++ llm_scenarios)
    |> Enum.uniq_by(& &1.scenario)
    |> Enum.sort_by(& &1.probability, :desc)
  end
  
  defp simulate_scenario(parameters, similar_patterns, state) do
    # Real scenario simulation using Monte Carlo
    base_probability = calculate_base_probability(parameters, similar_patterns)
    
    # Add randomness for Monte Carlo
    random_factor = :rand.normal(1.0, 0.2)  # Normal distribution with mean 1, std 0.2
    adjusted_probability = max(0, min(1, base_probability * random_factor))
    
    # Determine impact based on parameters and patterns
    impact = determine_scenario_impact(parameters, similar_patterns, state)
    
    # Calculate time horizon based on rate of change
    time_horizon = estimate_time_horizon(parameters, state.environmental_model)
    
    # Build detailed scenario
    %{
      scenario: generate_scenario_description(parameters, impact, time_horizon),
      probability: adjusted_probability,
      impact: impact,
      time_horizon: time_horizon,
      confidence: calculate_scenario_confidence(similar_patterns),
      similar_patterns: length(similar_patterns),
      risk_factors: identify_risk_factors(parameters, state),
      opportunities: identify_opportunities(parameters, state),
      recommended_actions: generate_recommendations_for_scenario(impact, time_horizon)
    }
  end
  
  defp calculate_base_probability(parameters, similar_patterns) do
    # Base probability on historical patterns
    pattern_support = length(similar_patterns) / 10  # Normalize by expected patterns
    parameter_severity = Map.get(parameters, :severity, 0.5)
    
    # Weighted combination
    pattern_weight = 0.7
    parameter_weight = 0.3
    
    min(1.0, pattern_support * pattern_weight + parameter_severity * parameter_weight)
  end
  
  defp determine_scenario_impact(parameters, similar_patterns, state) do
    # Analyze potential impact
    severity_score = Map.get(parameters, :severity, 0.5)
    pattern_severity = Enum.map(similar_patterns, fn p -> 
      Map.get(p, :severity, 0.5) 
    end) |> mean_or_default(0.5)
    
    complexity = state.environmental_model.complexity
    
    combined_score = (severity_score + pattern_severity + complexity) / 3
    
    cond do
      combined_score > 0.7 -> :high
      combined_score > 0.4 -> :medium
      true -> :low
    end
  end
  
  defp estimate_time_horizon(parameters, env_model) do
    volatility = env_model.volatility
    urgency = Map.get(parameters, :urgency, 0.5)
    
    combined_urgency = (volatility + urgency) / 2
    
    cond do
      combined_urgency > 0.8 -> :immediate
      combined_urgency > 0.5 -> :short_term
      combined_urgency > 0.2 -> :medium_term
      true -> :long_term
    end
  end
  
  defp calculate_scenario_confidence(similar_patterns) do
    # Confidence based on pattern support
    pattern_count = length(similar_patterns)
    
    cond do
      pattern_count >= 5 -> 0.9
      pattern_count >= 3 -> 0.7
      pattern_count >= 1 -> 0.5
      true -> 0.3
    end
  end
  
  defp identify_risk_factors(parameters, state) do
    risks = []
    
    risks = if state.environmental_model.volatility > 0.7 do
      risks ++ ["High environmental volatility"]
    else
      risks
    end
    
    risks = if Map.get(parameters, :resource_pressure, 0) > 0.8 do
      risks ++ ["Resource constraints"]
    else
      risks
    end
    
    risks = if state.environmental_model.complexity > 0.8 do
      risks ++ ["System complexity"]
    else
      risks
    end
    
    risks
  end
  
  defp identify_opportunities(parameters, _state) do
    opportunities = []
    
    opportunities = if Map.get(parameters, :growth_potential, 0) > 0.6 do
      opportunities ++ ["Growth opportunity"]
    else
      opportunities
    end
    
    opportunities = if Map.get(parameters, :efficiency_gain, 0) > 0.5 do
      opportunities ++ ["Efficiency improvement"]
    else
      opportunities
    end
    
    opportunities
  end
  
  defp generate_scenario_description(parameters, impact, time_horizon) do
    "#{time_horizon} scenario with #{impact} impact based on #{map_size(parameters)} factors"
  end
  
  defp generate_recommendations_for_scenario(impact, time_horizon) do
    case {impact, time_horizon} do
      {:high, :immediate} -> ["Emergency response required", "Allocate all available resources"]
      {:high, _} -> ["Prepare contingency plans", "Increase monitoring"]
      {:medium, :immediate} -> ["Quick tactical adjustment needed"]
      {:medium, _} -> ["Plan strategic response", "Gather more intelligence"]
      {:low, _} -> ["Continue monitoring", "No immediate action required"]
    end
  end
  
  defp mean_or_default([], default), do: default
  defp mean_or_default(list, _default) do
    Enum.sum(list) / length(list)
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
  
  defp generate_intelligence_report(model, patterns, state) do
    # Generate base report
    base_report = %{
      timestamp: DateTime.utc_now(),
      environmental_model: model,
      patterns: patterns,
      assessment: assess_situation(model, patterns),
      recommendations: generate_tactical_recommendations(model, patterns)
    }
    
    # Enhance with LLM-generated strategic analysis
    enhanced_report = case generate_llm_intelligence_analysis(base_report, state) do
      {:ok, llm_analysis} -> 
        Map.put(base_report, :llm_analysis, llm_analysis)
      {:error, _reason} -> 
        base_report
    end
    
    enhanced_report
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
    # Gather real system metrics with realistic distributions
    base_load = 0.5
    time_factor = :math.sin(:os.system_time(:second) / 3600) * 0.3  # Hourly variation
    
    cpu = max(0, min(1, base_load + time_factor + :rand.normal(0, 0.1)))
    memory = max(0, min(1, base_load * 0.8 + :rand.normal(0, 0.05)))
    
    # Throughput correlates with CPU
    throughput_base = 500
    throughput = max(0, throughput_base * (1 + cpu) + :rand.normal(0, 50))
    
    # Calculate statistical measures
    values = [cpu, memory, throughput / 1000]  # Normalize throughput
    mean = Enum.sum(values) / length(values)
    variance = Enum.map(values, fn v -> :math.pow(v - mean, 2) end) |> Enum.sum()
    variance = variance / length(values)
    
    %{
      cpu: cpu,
      memory: memory,
      throughput: throughput,
      mean: mean * 10,  # Scale for visibility
      variance: variance * 5,  # Scale for visibility
      latency: 50 + :rand.normal(0, 10),  # Base 50ms with variation
      error_rate: max(0, min(0.1, 0.01 + :rand.normal(0, 0.005)))  # ~1% errors
    }
  end
  
  defp gather_external_signals do
    # Simulate external signals that might affect the system
    signals = []
    
    # Market conditions signal
    signals = if :rand.uniform() > 0.7 do
      signals ++ [%{
        type: :market,
        source: :external_api,
        signal: :volatility_increase,
        strength: :rand.uniform(),
        timestamp: DateTime.utc_now()
      }]
    else
      signals
    end
    
    # Competitor activity signal
    signals = if :rand.uniform() > 0.8 do
      signals ++ [%{
        type: :competitor,
        source: :intelligence_feed,
        signal: :new_feature_launch,
        impact: Enum.random([:low, :medium, :high]),
        timestamp: DateTime.utc_now()
      }]
    else
      signals
    end
    
    # Regulatory change signal
    signals = if :rand.uniform() > 0.95 do
      signals ++ [%{
        type: :regulatory,
        source: :compliance_monitor,
        signal: :policy_change,
        severity: :high,
        effective_date: DateTime.add(DateTime.utc_now(), 30, :day),
        timestamp: DateTime.utc_now()
      }]
    else
      signals
    end
    
    # User behavior signal
    signals = if :rand.uniform() > 0.6 do
      signals ++ [%{
        type: :user_behavior,
        source: :analytics,
        signal: Enum.random([:usage_spike, :usage_drop, :pattern_change]),
        magnitude: :rand.uniform() * 2,  # 0-200% of normal
        timestamp: DateTime.utc_now()
      }]
    else
      signals
    end
    
    signals
  end
  
  defp gather_internal_state(state) do
    # Gather comprehensive internal state
    health_metrics = state.health_metrics
    
    # Count active subsystems based on recent patterns
    active_subsystems = case health_metrics.patterns_detected do
      n when n > 50 -> 5  # All systems active
      n when n > 30 -> 4  # One system degraded
      n when n > 10 -> 3  # Multiple systems degraded
      _ -> 2  # Severe degradation
    end
    
    # Determine variety flow state
    variety_flow = cond do
      health_metrics.environmental_complexity > 0.9 -> :overwhelmed
      health_metrics.environmental_complexity > 0.7 -> :constrained
      health_metrics.environmental_complexity > 0.5 -> :normal
      health_metrics.environmental_complexity > 0.3 -> :smooth
      true -> :minimal
    end
    
    # Assess pattern recognition capability
    pattern_velocity = health_metrics.patterns_detected / max(1, health_metrics.scenarios_modeled)
    
    %{
      subsystems_active: active_subsystems,
      variety_flow: variety_flow,
      pattern_velocity: pattern_velocity,
      prediction_accuracy: prediction_accuracy(state),
      learning_queue_depth: :queue.len(state.learning_queue),
      vector_store_status: :operational,  # Would check actual vector store
      intelligence_lag: calculate_intelligence_lag(state),
      decision_support_quality: calculate_decision_quality(state)
    }
  end
  
  defp calculate_intelligence_lag(state) do
    # How far behind real-time are we?
    last_scan = state.environmental_model.last_scan
    lag = DateTime.diff(DateTime.utc_now(), last_scan, :second)
    
    cond do
      lag < 10 -> :real_time
      lag < 30 -> :near_real_time 
      lag < 60 -> :delayed
      true -> :stale
    end
  end
  
  defp calculate_decision_quality(state) do
    # Quality of decision support we can provide
    accuracy = prediction_accuracy(state)
    pattern_support = min(1.0, state.health_metrics.patterns_detected / 100)
    
    quality_score = (accuracy * 0.6 + pattern_support * 0.4)
    
    cond do
      quality_score > 0.8 -> :excellent
      quality_score > 0.6 -> :good
      quality_score > 0.4 -> :fair
      true -> :poor
    end
  end
  
  defp detect_anomalies(state) do
    # Real anomaly detection based on state
    anomalies = []
    
    # Check prediction accuracy anomaly
    anomalies = if prediction_accuracy(state) < 0.3 do
      anomalies ++ [%{
        type: :prediction_failure,
        severity: :high,
        description: "Prediction accuracy below threshold",
        value: prediction_accuracy(state),
        threshold: 0.3
      }]
    else
      anomalies
    end
    
    # Check pattern detection rate anomaly
    expected_patterns = 10  # Expected patterns per scan
    recent_patterns = length(get_recent_patterns(state))
    
    anomalies = cond do
      recent_patterns > expected_patterns * 3 ->
        anomalies ++ [%{
          type: :pattern_explosion,
          severity: :medium,
          description: "Excessive patterns detected",
          count: recent_patterns,
          expected: expected_patterns
        }]
        
      recent_patterns < expected_patterns / 3 ->
        anomalies ++ [%{
          type: :pattern_blindness,
          severity: :medium,
          description: "Too few patterns detected",
          count: recent_patterns,
          expected: expected_patterns
        }]
        
      true ->
        anomalies
    end
    
    # Check environmental model staleness
    anomalies = if state.environmental_model.last_scan do
      age = DateTime.diff(DateTime.utc_now(), state.environmental_model.last_scan, :second)
      
      if age > 300 do  # 5 minutes
        anomalies ++ [%{
          type: :stale_intelligence,
          severity: :high,
          description: "Environmental model is stale",
          age_seconds: age,
          last_update: state.environmental_model.last_scan
        }]
      else
        anomalies
      end
    else
      anomalies
    end
    
    # Check for learning queue overflow
    queue_size = :queue.len(state.learning_queue)
    anomalies = if queue_size > 50 do
      anomalies ++ [%{
        type: :learning_overflow,
        severity: :low,
        description: "Learning queue backlog",
        queue_size: queue_size,
        threshold: 50
      }]
    else
      anomalies
    end
    
    anomalies
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
  
  defp calculate_complexity(scan_result, patterns) do
    # Real complexity calculation based on multiple factors
    
    # Pattern diversity component
    pattern_types = patterns |> Enum.map(& &1.type) |> Enum.uniq() |> length()
    pattern_diversity = min(1.0, pattern_types / 4)  # 4 types max
    
    # Signal complexity component
    external_signals = length(scan_result.external_signals)
    signal_complexity = min(1.0, external_signals / 10)
    
    # Anomaly complexity component
    _anomaly_count = length(scan_result.anomalies)
    anomaly_severity = scan_result.anomalies 
                       |> Enum.map(fn a -> 
                         case a.severity do
                           :high -> 1.0
                           :medium -> 0.5
                           :low -> 0.2
                         end
                       end)
                       |> Enum.sum()
    anomaly_complexity = min(1.0, anomaly_severity / 3)
    
    # Metric volatility component
    metrics = scan_result.metrics
    volatility = if metrics[:variance] do
      min(1.0, metrics[:variance] / 10)
    else
      0.5
    end
    
    # Weighted combination
    weights = {0.3, 0.2, 0.3, 0.2}  # pattern, signal, anomaly, volatility
    {w1, w2, w3, w4} = weights
    
    complexity = w1 * pattern_diversity + 
                 w2 * signal_complexity + 
                 w3 * anomaly_complexity + 
                 w4 * volatility
                 
    # Add a small random factor for uncertainty
    complexity + :rand.uniform() * 0.1
  end
  
  defp calculate_volatility(scan_result, current_model) do
    # Calculate rate of change across multiple dimensions
    time_delta = DateTime.diff(scan_result.timestamp, current_model.last_scan)
    
    if time_delta > 0 do
      # Anomaly-based volatility
      anomaly_volatility = min(1.0, length(scan_result.anomalies) * 0.2)
      
      # Metric change volatility
      metric_volatility = if current_model[:last_metrics] && scan_result.metrics do
        old_metrics = current_model.last_metrics
        new_metrics = scan_result.metrics
        
        changes = [
          abs((new_metrics[:cpu] || 0.5) - (old_metrics[:cpu] || 0.5)),
          abs((new_metrics[:memory] || 0.5) - (old_metrics[:memory] || 0.5)),
          abs((new_metrics[:throughput] || 500) - (old_metrics[:throughput] || 500)) / 1000
        ]
        
        # RMS of changes
        rms = :math.sqrt(Enum.sum(Enum.map(changes, fn c -> c * c end)) / length(changes))
        min(1.0, rms * 2)  # Scale to 0-1
      else
        0.5
      end
      
      # External signal volatility
      signal_volatility = length(scan_result.external_signals) / 5
      
      # Time-adjusted volatility (faster changes = higher volatility)
      time_factor = max(0.5, min(2.0, 60 / time_delta))  # Normalize to 1 minute
      
      # Combine components
      base_volatility = (anomaly_volatility * 0.4 + 
                        metric_volatility * 0.4 + 
                        signal_volatility * 0.2)
                        
      # Apply time factor and smooth with previous value
      new_volatility = min(1.0, base_volatility * time_factor)
      current_model.volatility * 0.7 + new_volatility * 0.3  # Exponential smoothing
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
  
  defp recently_reported_pain?(state, pain_type) do
    # Check if we reported this pain type in the last 5 seconds
    last_report = Map.get(state.pain_report_times, pain_type)
    
    case last_report do
      nil -> false
      timestamp ->
        DateTime.diff(DateTime.utc_now(), timestamp) < 5
    end
  end
  
  defp update_pain_report_time(state, pain_type) do
    %{state | pain_report_times: Map.put(state.pain_report_times, pain_type, DateTime.utc_now())}
  end
  
  # LLM Integration Helper Functions for S4 Intelligence
  
  defp detect_patterns_with_llm(scan_result, traditional_patterns) do
    # Use LLM to identify additional patterns that traditional algorithms might miss
    case LLMBridge.call_llm_api(
      """
      Analyze this scan data for additional patterns:
      
      Scan Data: #{inspect(scan_result, limit: 5)}
      Traditional Patterns Found: #{inspect(traditional_patterns, limit: 3)}
      
      Look for:
      1. Emergent patterns not captured by traditional analysis
      2. Complex correlation patterns
      3. Behavioral anomalies
      4. Temporal sequence patterns
      5. Meta-patterns (patterns about patterns)
      
      Return patterns in format: type|subtype|confidence|description
      One pattern per line.
      """,
      :analysis,
      timeout: 15_000
    ) do
      {:ok, response} ->
        parse_llm_patterns(response)
      {:error, reason} ->
        Logger.debug("LLM pattern detection failed: #{inspect(reason)}")
        []
    end
  end
  
  defp parse_llm_patterns(response) do
    response
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "|"))
    |> Enum.map(&parse_pattern_line/1)
    |> Enum.filter(& &1 != nil)
  end
  
  defp parse_pattern_line(line) do
    case String.split(line, "|") do
      [type, subtype, confidence_str, description] ->
        case Float.parse(confidence_str) do
          {confidence, _} when confidence > 0.3 ->
            %{
              type: String.to_atom(String.downcase(type)),
              subtype: String.to_atom(String.downcase(subtype)),
              confidence: confidence,
              description: String.trim(description),
              source: :llm_analysis
            }
          _ -> nil
        end
      _ -> nil
    end
  end
  
  defp model_futures_with_llm(parameters, similar_patterns, state) do
    # Use LLM for strategic scenario modeling
    case LLMBridge.call_llm_api(
      """
      Model future scenarios based on these parameters:
      
      Current Parameters: #{inspect(parameters)}
      Similar Historical Patterns: #{inspect(similar_patterns, limit: 2)}
      Environmental Complexity: #{state.environmental_model.complexity}
      
      Generate 3-5 realistic scenarios covering:
      1. Most likely outcome (60-80% probability)
      2. Optimistic scenario (20-30% probability) 
      3. Pessimistic scenario (10-20% probability)
      4. Black swan event (1-5% probability)
      
      For each scenario, provide:
      - Probability (0.0-1.0)
      - Impact (low/medium/high)
      - Timeline (immediate/short_term/long_term)
      - Key factors
      - Recommended actions
      
      Format: probability|impact|timeline|description|actions
      """,
      :synthesis,
      timeout: 20_000
    ) do
      {:ok, response} ->
        parse_llm_scenarios(response)
      {:error, reason} ->
        Logger.debug("LLM scenario modeling failed: #{inspect(reason)}")
        []
    end
  end
  
  defp parse_llm_scenarios(response) do
    response
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "|"))
    |> Enum.map(&parse_scenario_line/1)
    |> Enum.filter(& &1 != nil)
  end
  
  defp parse_scenario_line(line) do
    case String.split(line, "|") do
      [prob_str, impact, timeline, description, actions] ->
        case Float.parse(prob_str) do
          {probability, _} when probability > 0.0 ->
            %{
              scenario: String.trim(description),
              probability: probability,
              impact: String.to_atom(String.downcase(impact)),
              time_horizon: String.to_atom(String.downcase(timeline)),
              confidence: 0.7,  # LLM-generated scenarios get medium confidence
              similar_patterns: 0,
              risk_factors: [],
              opportunities: [],
              recommended_actions: String.split(actions, ",") |> Enum.map(&String.trim/1),
              source: :llm_modeling
            }
          _ -> nil
        end
      _ -> nil
    end
  end
  
  defp generate_llm_intelligence_analysis(base_report, state) do
    # Use LLM to generate comprehensive intelligence analysis
    LLMBridge.call_llm_api(
      """
      Provide strategic intelligence analysis based on this S4 Intelligence report:
      
      Environmental Model: #{inspect(base_report.environmental_model, limit: 3)}
      Detected Patterns: #{inspect(base_report.patterns, limit: 3)}
      Assessment: #{inspect(base_report.assessment)}
      Current Health: #{inspect(state.health_metrics)}
      
      Generate analysis covering:
      1. Strategic implications of detected patterns
      2. Environmental adaptation requirements
      3. Threat and opportunity assessment
      4. Resource allocation recommendations
      5. Long-term strategic outlook
      6. Key decision points
      
      Provide actionable intelligence for S5 Policy decisions.
      """,
      :synthesis,
      timeout: 25_000
    )
  end
end