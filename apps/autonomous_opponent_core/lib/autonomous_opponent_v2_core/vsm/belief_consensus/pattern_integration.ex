defmodule AutonomousOpponentV2Core.VSM.BeliefConsensus.PatternIntegration do
  @moduledoc """
  Integrates pattern detection flow (Issue #92) with belief consensus (Issue #93).
  
  This module bridges the gap between detected patterns and belief formation:
  - Converts high-confidence patterns into beliefs
  - Aggregates pattern-based beliefs for consensus
  - Feeds consensus beliefs back to S4 Intelligence
  - Enables learning from pattern-belief correlations
  
  Flow: Pattern Detection → Belief Generation → Consensus → S4 Learning
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.BeliefConsensus
  alias AutonomousOpponentV2Core.VSM.S4.Intelligence
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator
  
  # Pattern to belief conversion thresholds
  @pattern_confidence_threshold 0.7    # Min confidence to create belief
  @pattern_recurrence_threshold 3      # Min occurrences before belief
  @belief_weight_factor 0.8           # Pattern confidence → belief weight
  @correlation_threshold 0.6          # Min correlation for belief merging
  @learning_feedback_interval 60_000   # 1 minute
  
  defstruct [
    :pattern_history,        # Recent patterns for correlation
    :belief_mappings,        # Pattern ID → Belief ID mappings
    :correlation_matrix,     # Pattern-belief correlations
    :learning_state,         # S4 feedback state
    :metrics,               # Performance metrics
    :config                 # Configuration overrides
  ]
  
  # Pattern belief structure
  defmodule PatternBelief do
    @enforce_keys [:pattern_id, :belief_content, :confidence, :evidence]
    defstruct [
      :pattern_id,
      :belief_content,     # Semantic interpretation of pattern
      :confidence,         # Derived from pattern confidence
      :evidence,          # Pattern occurrences
      :source_level,      # Which VSM level detected it
      :timestamp,
      :correlations       # Related patterns
    ]
  end
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Process a detected pattern and potentially generate a belief.
  """
  def process_pattern(pattern_data) do
    GenServer.cast(__MODULE__, {:process_pattern, pattern_data})
  end
  
  @doc """
  Get belief-pattern correlations.
  """
  def get_correlations do
    GenServer.call(__MODULE__, :get_correlations)
  end
  
  @doc """
  Force pattern analysis for belief generation.
  """
  def analyze_patterns_for_beliefs do
    GenServer.call(__MODULE__, :analyze_patterns)
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    # Subscribe to pattern detection events
    EventBus.subscribe(:pattern_detected)
    EventBus.subscribe(:pattern_correlation_found)
    EventBus.subscribe(:pattern_anomaly_detected)
    EventBus.subscribe(:belief_consensus_reached)
    
    # Start learning feedback timer
    schedule_learning_feedback()
    
    state = %__MODULE__{
      pattern_history: :queue.new(),
      belief_mappings: %{},
      correlation_matrix: %{},
      learning_state: init_learning_state(),
      metrics: init_metrics(),
      config: Keyword.get(opts, :config, default_config())
    }
    
    Logger.info("🔗 Pattern-Belief Integration initialized")
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:process_pattern, pattern_data}, state) do
    # Add to history
    new_history = update_pattern_history(state.pattern_history, pattern_data)
    
    # Check if pattern warrants belief generation
    new_state = if should_generate_belief?(pattern_data, state) do
      generate_and_propose_belief(pattern_data, %{state | pattern_history: new_history})
    else
      %{state | pattern_history: new_history}
    end
    
    # Update correlations
    new_state = update_pattern_correlations(pattern_data, new_state)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call(:get_correlations, _from, state) do
    correlations = format_correlations(state.correlation_matrix)
    {:reply, {:ok, correlations}, state}
  end
  
  @impl true
  def handle_call(:analyze_patterns, _from, state) do
    # Analyze pattern history for belief opportunities
    analysis = analyze_pattern_history(state)
    
    # Generate beliefs from strong patterns
    new_state = Enum.reduce(analysis.strong_patterns, state, fn pattern, acc ->
      generate_and_propose_belief(pattern, acc)
    end)
    
    {:reply, {:ok, analysis}, new_state}
  end
  
  @impl true
  def handle_info(:learning_feedback, state) do
    # Send belief-pattern correlations to S4
    send_learning_feedback(state)
    
    # Schedule next feedback
    schedule_learning_feedback()
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, event}, state) do
    handle_info({:event, event.type, event.data}, state)
  end
  
  @impl true
  def handle_info({:event, :pattern_detected, pattern}, state) do
    # Process detected pattern
    handle_cast({:process_pattern, pattern}, state)
  end
  
  @impl true
  def handle_info({:event, :pattern_correlation_found, correlation}, state) do
    # Multiple correlated patterns strengthen belief
    new_state = process_pattern_correlation(correlation, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :pattern_anomaly_detected, anomaly}, state) do
    # Anomalies create high-urgency beliefs
    new_state = process_pattern_anomaly(anomaly, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :belief_consensus_reached, consensus}, state) do
    # Update mappings when consensus is reached
    new_state = update_belief_consensus(consensus, state)
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp default_config do
    %{
      pattern_confidence_threshold: @pattern_confidence_threshold,
      pattern_recurrence_threshold: @pattern_recurrence_threshold,
      belief_weight_factor: @belief_weight_factor,
      correlation_threshold: @correlation_threshold,
      max_history_size: 1000,
      pattern_ttl: 3_600_000  # 1 hour
    }
  end
  
  defp init_learning_state do
    %{
      feedback_count: 0,
      successful_predictions: 0,
      failed_predictions: 0,
      learning_rate: 0.1
    }
  end
  
  defp init_metrics do
    %{
      patterns_processed: 0,
      beliefs_generated: 0,
      correlations_found: 0,
      anomalies_converted: 0,
      consensus_feedback: 0
    }
  end
  
  defp update_pattern_history(history, pattern_data) do
    # Add pattern with timestamp
    timestamped_pattern = Map.put(pattern_data, :received_at, DateTime.utc_now())
    
    new_queue = :queue.in(timestamped_pattern, history)
    
    # Limit history size
    if :queue.len(new_queue) > 1000 do
      {_, trimmed} = :queue.out(new_queue)
      trimmed
    else
      new_queue
    end
  end
  
  defp should_generate_belief?(pattern_data, state) do
    config = state.config
    
    # Check confidence threshold
    confidence_ok = pattern_data[:confidence] >= config.pattern_confidence_threshold
    
    # Check recurrence
    recurrence = count_pattern_recurrence(pattern_data, state.pattern_history)
    recurrence_ok = recurrence >= config.pattern_recurrence_threshold
    
    # Check if we already have a belief for this pattern
    not_duplicate = not Map.has_key?(state.belief_mappings, pattern_data[:id])
    
    confidence_ok && recurrence_ok && not_duplicate
  end
  
  defp count_pattern_recurrence(pattern, history) do
    history
    |> :queue.to_list()
    |> Enum.count(fn p ->
      patterns_similar?(p, pattern)
    end)
  end
  
  defp patterns_similar?(pattern1, pattern2) do
    # Compare pattern types and key attributes
    pattern1[:type] == pattern2[:type] &&
    calculate_pattern_similarity(pattern1, pattern2) > 0.8
  end
  
  defp calculate_pattern_similarity(p1, p2) do
    # Simple similarity based on common attributes
    common_attrs = [:category, :source, :severity, :subsystem]
    
    matches = Enum.count(common_attrs, fn attr ->
      Map.get(p1, attr) == Map.get(p2, attr)
    end)
    
    matches / length(common_attrs)
  end
  
  defp generate_and_propose_belief(pattern_data, state) do
    # Generate belief content from pattern
    belief_content = generate_belief_content(pattern_data)
    
    # Determine VSM level based on pattern source
    vsm_level = determine_vsm_level(pattern_data)
    
    # Create belief with appropriate metadata
    metadata = %{
      source: "pattern_integration",
      weight: pattern_data[:confidence] * state.config.belief_weight_factor,
      confidence: pattern_data[:confidence],
      evidence: [
        %{
          type: :pattern,
          pattern_id: pattern_data[:id],
          pattern_type: pattern_data[:type],
          occurrences: count_pattern_recurrence(pattern_data, state.pattern_history)
        }
      ]
    }
    
    # Propose belief
    case BeliefConsensus.propose_belief(vsm_level, belief_content, metadata) do
      {:ok, belief_id} ->
        # Update mappings
        new_mappings = Map.put(state.belief_mappings, pattern_data[:id], belief_id)
        
        # Update metrics
        new_metrics = %{state.metrics | beliefs_generated: state.metrics.beliefs_generated + 1}
        
        Logger.info("✨ Generated belief #{belief_id} from pattern #{pattern_data[:id]}")
        
        %{state | 
          belief_mappings: new_mappings,
          metrics: new_metrics
        }
        
      {:error, reason} ->
        Logger.warning("Failed to generate belief from pattern: #{inspect(reason)}")
        state
    end
  end
  
  defp generate_belief_content(pattern_data) do
    # Convert pattern data into semantic belief
    case pattern_data[:type] do
      :performance_degradation ->
        "System performance is degrading in #{pattern_data[:component] || "unknown component"}"
        
      :resource_exhaustion ->
        "Resource #{pattern_data[:resource] || "unknown"} is approaching exhaustion"
        
      :security_anomaly ->
        "Security anomaly detected: #{pattern_data[:description] || "unusual behavior pattern"}"
        
      :coordination_failure ->
        "Coordination failing between #{pattern_data[:units] || "subsystems"}"
        
      :emergence_detected ->
        "Emergent behavior detected: #{pattern_data[:behavior] || "unexpected pattern"}"
        
      :pattern_cluster ->
        "Recurring pattern cluster indicates: #{pattern_data[:cluster_meaning] || "systematic issue"}"
        
      _ ->
        "Pattern #{pattern_data[:type]} detected with confidence #{pattern_data[:confidence]}"
    end
  end
  
  defp determine_vsm_level(pattern_data) do
    # Map pattern sources to VSM levels
    case pattern_data[:source] do
      source when source in [:operations, :s1_operations, :performance] -> :s1
      source when source in [:coordination, :s2_coordination, :conflict] -> :s2
      source when source in [:control, :s3_control, :resource] -> :s3
      source when source in [:intelligence, :s4_intelligence, :prediction] -> :s4
      source when source in [:policy, :s5_policy, :governance] -> :s5
      _ -> :s4  # Default to intelligence level
    end
  end
  
  defp update_pattern_correlations(pattern_data, state) do
    # Find correlated patterns in history
    correlated = find_correlated_patterns(pattern_data, state.pattern_history)
    
    if length(correlated) > 0 do
      # Update correlation matrix
      new_matrix = Enum.reduce(correlated, state.correlation_matrix, fn corr_pattern, matrix ->
        update_correlation_matrix(matrix, pattern_data[:id], corr_pattern[:id])
      end)
      
      %{state | 
        correlation_matrix: new_matrix,
        metrics: %{state.metrics | correlations_found: state.metrics.correlations_found + length(correlated)}
      }
    else
      state
    end
  end
  
  defp find_correlated_patterns(pattern, history) do
    history
    |> :queue.to_list()
    |> Enum.filter(fn p ->
      p[:id] != pattern[:id] && 
      temporal_correlation?(p, pattern) &&
      semantic_correlation?(p, pattern)
    end)
  end
  
  defp temporal_correlation?(p1, p2) do
    # Patterns within 5 minutes of each other
    if p1[:timestamp] && p2[:timestamp] do
      diff = abs(DateTime.diff(p1[:timestamp], p2[:timestamp], :second))
      diff < 300
    else
      false
    end
  end
  
  defp semantic_correlation?(p1, p2) do
    # Patterns affecting same subsystem or resource
    (p1[:subsystem] && p1[:subsystem] == p2[:subsystem]) ||
    (p1[:resource] && p1[:resource] == p2[:resource]) ||
    (p1[:component] && p1[:component] == p2[:component])
  end
  
  defp update_correlation_matrix(matrix, id1, id2) do
    # Symmetric matrix update
    key1 = correlation_key(id1, id2)
    key2 = correlation_key(id2, id1)
    
    current = Map.get(matrix, key1, 0)
    
    matrix
    |> Map.put(key1, current + 1)
    |> Map.put(key2, current + 1)
  end
  
  defp correlation_key(id1, id2) do
    {id1, id2}
  end
  
  defp process_pattern_correlation(correlation_data, state) do
    # Strong correlations create compound beliefs
    if correlation_data[:strength] > state.config.correlation_threshold do
      # Generate compound belief
      compound_belief = generate_compound_belief(correlation_data, state)
      
      # Propose with higher weight
      metadata = %{
        source: "pattern_correlation",
        weight: correlation_data[:strength],
        confidence: correlation_data[:confidence],
        evidence: correlation_data[:patterns]
      }
      
      vsm_level = determine_correlation_level(correlation_data)
      
      case BeliefConsensus.propose_belief(vsm_level, compound_belief, metadata) do
        {:ok, _belief_id} ->
          %{state | metrics: %{state.metrics | correlations_found: state.metrics.correlations_found + 1}}
        _ ->
          state
      end
    else
      state
    end
  end
  
  defp generate_compound_belief(correlation_data, _state) do
    patterns = correlation_data[:patterns] || []
    
    "Correlated patterns suggest: #{summarize_correlation(patterns, correlation_data[:correlation_type])}"
  end
  
  defp summarize_correlation(patterns, correlation_type) do
    case correlation_type do
      :cascade -> "cascading failure across #{length(patterns)} components"
      :synchronous -> "synchronized behavior indicating common cause"
      :alternating -> "oscillating behavior between subsystems"
      :progressive -> "progressive degradation spreading through system"
      _ -> "complex interaction between #{length(patterns)} patterns"
    end
  end
  
  defp determine_correlation_level(correlation_data) do
    # Multi-pattern correlations go to higher levels
    pattern_count = length(correlation_data[:patterns] || [])
    
    cond do
      pattern_count >= 5 -> :s5  # System-wide
      pattern_count >= 3 -> :s4  # Intelligence level
      pattern_count >= 2 -> :s3  # Control level
      true -> :s2              # Coordination level
    end
  end
  
  defp process_pattern_anomaly(anomaly_data, state) do
    # Anomalies create urgent beliefs
    Logger.warning("🚨 Pattern anomaly detected: #{inspect(anomaly_data[:type])}")
    
    belief_content = "ANOMALY: #{anomaly_data[:description] || "Unexpected pattern behavior"}"
    
    # High urgency for anomalies
    metadata = %{
      source: "pattern_anomaly",
      weight: 0.9,
      confidence: anomaly_data[:confidence] || 0.8,
      evidence: [anomaly_data],
      urgency: 0.95  # Triggers algedonic bypass
    }
    
    # Anomalies go to S4 for intelligence assessment
    case BeliefConsensus.propose_belief(:s4, belief_content, metadata) do
      {:ok, _belief_id} ->
        %{state | metrics: %{state.metrics | anomalies_converted: state.metrics.anomalies_converted + 1}}
      _ ->
        state
    end
  end
  
  defp update_belief_consensus(consensus_data, state) do
    # Track which beliefs reached consensus
    belief_ids = Enum.map(consensus_data[:beliefs] || [], & &1[:id])
    
    # Find patterns that generated these beliefs
    pattern_ids = state.belief_mappings
    |> Enum.filter(fn {_pattern_id, belief_id} ->
      belief_id in belief_ids
    end)
    |> Enum.map(fn {pattern_id, _} -> pattern_id end)
    
    # Update learning state
    new_learning = if length(pattern_ids) > 0 do
      %{state.learning_state | 
        successful_predictions: state.learning_state.successful_predictions + length(pattern_ids)
      }
    else
      state.learning_state
    end
    
    %{state | 
      learning_state: new_learning,
      metrics: %{state.metrics | consensus_feedback: state.metrics.consensus_feedback + 1}
    }
  end
  
  defp send_learning_feedback(state) do
    # Prepare feedback for S4 Intelligence
    feedback = %{
      pattern_belief_mappings: state.belief_mappings,
      correlation_matrix: state.correlation_matrix,
      success_rate: calculate_success_rate(state.learning_state),
      strong_correlations: get_strong_correlations(state),
      timestamp: DateTime.utc_now()
    }
    
    # Send to S4 for learning
    Intelligence.process_learning_feedback(feedback)
    
    # Update metrics
    %{state | 
      learning_state: %{state.learning_state | feedback_count: state.learning_state.feedback_count + 1}
    }
  end
  
  defp calculate_success_rate(learning_state) do
    total = learning_state.successful_predictions + learning_state.failed_predictions
    
    if total > 0 do
      learning_state.successful_predictions / total
    else
      0.0
    end
  end
  
  defp get_strong_correlations(state) do
    state.correlation_matrix
    |> Enum.filter(fn {_key, count} -> count >= 5 end)
    |> Enum.map(fn {{id1, id2}, count} -> 
      %{pattern1: id1, pattern2: id2, correlation_strength: count}
    end)
  end
  
  defp analyze_pattern_history(state) do
    patterns = :queue.to_list(state.pattern_history)
    
    # Group by pattern type
    grouped = Enum.group_by(patterns, & &1[:type])
    
    # Find strong patterns
    strong_patterns = grouped
    |> Enum.flat_map(fn {_type, patterns} ->
      patterns
      |> Enum.filter(fn p ->
        p[:confidence] >= state.config.pattern_confidence_threshold &&
        count_pattern_recurrence(p, state.pattern_history) >= state.config.pattern_recurrence_threshold
      end)
    end)
    |> Enum.uniq_by(& &1[:id])
    
    %{
      total_patterns: length(patterns),
      pattern_types: Map.keys(grouped),
      strong_patterns: strong_patterns,
      correlation_candidates: find_correlation_candidates(patterns)
    }
  end
  
  defp find_correlation_candidates(patterns) do
    # Find patterns that occur together frequently
    patterns
    |> Enum.combination(2)
    |> Enum.filter(fn [p1, p2] ->
      temporal_correlation?(p1, p2) && semantic_correlation?(p1, p2)
    end)
    |> Enum.take(10)  # Limit results
  end
  
  defp format_correlations(correlation_matrix) do
    correlation_matrix
    |> Enum.map(fn {{id1, id2}, count} ->
      %{
        pattern1: id1,
        pattern2: id2,
        occurrences: count,
        strength: min(1.0, count / 10.0)  # Normalize to 0-1
      }
    end)
    |> Enum.sort_by(& &1.occurrences, :desc)
  end
  
  defp schedule_learning_feedback do
    Process.send_after(self(), :learning_feedback, @learning_feedback_interval)
  end
end