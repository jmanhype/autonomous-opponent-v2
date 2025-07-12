defmodule AutonomousOpponentV2Core.VSM.BeliefConsensus.ByzantineDetector do
  @moduledoc """
  Byzantine fault detection for CRDT Belief Consensus using VSM S2 oscillation patterns.
  
  Detects malicious or faulty nodes through behavioral analysis:
  - Double voting on contradictory beliefs
  - Inconsistent state propagation
  - Message flooding attacks
  - Selective forwarding
  - Oscillation pattern analysis
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S2.Coordination
  
  # Byzantine detection thresholds
  @double_vote_threshold 3         # Number of contradictions before flagging
  @flooding_threshold 100          # Messages per minute
  @inconsistency_threshold 0.3     # State divergence ratio
  @reputation_decay_rate 0.95      # Reputation decay per hour
  @min_reputation 0.1              # Minimum reputation score
  @byzantine_pattern_threshold 0.7 # Confidence threshold for Byzantine detection
  
  defstruct [
    :node_behaviors,      # Map of node_id -> behavior history
    :reputation_scores,   # Map of node_id -> reputation (0.0-1.0)
    :byzantine_nodes,     # Set of identified Byzantine nodes
    :detection_rules,     # Configurable detection rules
    :oscillation_monitor, # Integration with S2 coordination
    :metrics             # Detection metrics
  ]
  
  # Behavior tracking structure
  defmodule NodeBehavior do
    defstruct [
      :node_id,
      :vote_history,        # Recent votes cast
      :message_rate,        # Messages per minute
      :state_consistency,   # Consistency with network state
      :forwarding_ratio,    # Ratio of messages forwarded
      :oscillation_score,   # From S2 analysis
      :contradictions,      # Detected contradictions
      :last_activity,       # Last seen timestamp
      :suspicious_patterns  # List of detected patterns
    ]
  end
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Record a belief vote from a node.
  """
  def record_vote(node_id, belief_id, vote) do
    GenServer.cast(__MODULE__, {:record_vote, node_id, belief_id, vote})
  end
  
  @doc """
  Record message activity from a node.
  """
  def record_message(node_id, message_type, size) do
    GenServer.cast(__MODULE__, {:record_message, node_id, message_type, size})
  end
  
  @doc """
  Check if a node is Byzantine.
  """
  def is_byzantine?(node_id) do
    GenServer.call(__MODULE__, {:is_byzantine, node_id})
  end
  
  @doc """
  Get reputation score for a node.
  """
  def get_reputation(node_id) do
    GenServer.call(__MODULE__, {:get_reputation, node_id})
  end
  
  @doc """
  Get all Byzantine nodes.
  """
  def get_byzantine_nodes do
    GenServer.call(__MODULE__, :get_byzantine_nodes)
  end

  @doc """
  Get detected patterns for a specific node.
  """
  def get_node_patterns(node_id) do
    GenServer.call(__MODULE__, {:get_node_patterns, node_id})
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    # Subscribe to relevant events
    EventBus.subscribe(:belief_vote)
    EventBus.subscribe(:crdt_sync)
    EventBus.subscribe(:node_message)
    EventBus.subscribe(:s2_oscillation_detected)
    
    # Initialize detection rules
    rules = init_detection_rules(opts)
    
    # Start periodic cleanup
    schedule_reputation_decay()
    schedule_behavior_analysis()
    
    state = %__MODULE__{
      node_behaviors: %{},
      reputation_scores: %{},
      byzantine_nodes: MapSet.new(),
      detection_rules: rules,
      oscillation_monitor: connect_to_s2_coordination(),
      metrics: init_metrics()
    }
    
    Logger.info("🛡️ Byzantine Detector initialized")
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:record_vote, node_id, belief_id, vote}, state) do
    # Update node behavior
    behavior = get_or_create_behavior(node_id, state)
    
    # Check for double voting
    updated_behavior = detect_double_voting(behavior, belief_id, vote)
    
    # Update state
    new_state = update_node_behavior(state, node_id, updated_behavior)
    
    # Check if this triggers Byzantine detection
    new_state = check_byzantine_patterns(node_id, new_state)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_message, node_id, message_type, size}, state) do
    # Update message rate
    behavior = get_or_create_behavior(node_id, state)
    
    # Update message statistics
    updated_behavior = update_message_stats(behavior, message_type, size)
    
    # Check for flooding
    updated_behavior = detect_flooding(updated_behavior)
    
    # Update state
    new_state = update_node_behavior(state, node_id, updated_behavior)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call({:is_byzantine, node_id}, _from, state) do
    {:reply, MapSet.member?(state.byzantine_nodes, node_id), state}
  end
  
  @impl true
  def handle_call({:get_reputation, node_id}, _from, state) do
    reputation = Map.get(state.reputation_scores, node_id, 1.0)
    {:reply, reputation, state}
  end
  
  @impl true
  def handle_call(:get_byzantine_nodes, _from, state) do
    {:reply, MapSet.to_list(state.byzantine_nodes), state}
  end

  @impl true
  def handle_call({:get_node_patterns, node_id}, _from, state) do
    patterns = case Map.get(state.node_behaviors, node_id) do
      nil -> []
      behavior -> behavior.suspicious_patterns
    end
    {:reply, patterns, state}
  end
  
  @impl true
  def handle_info(:decay_reputation, state) do
    # Decay reputation scores over time
    new_scores = state.reputation_scores
    |> Enum.map(fn {node_id, score} ->
      # Don't decay Byzantine nodes further
      if MapSet.member?(state.byzantine_nodes, node_id) do
        {node_id, @min_reputation}
      else
        {node_id, max(@min_reputation, score * @reputation_decay_rate)}
      end
    end)
    |> Map.new()
    
    # Schedule next decay
    schedule_reputation_decay()
    
    {:noreply, %{state | reputation_scores: new_scores}}
  end
  
  @impl true
  def handle_info(:analyze_behaviors, state) do
    # Periodic comprehensive behavior analysis
    new_state = analyze_all_behaviors(state)
    
    # Schedule next analysis
    schedule_behavior_analysis()
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :s2_oscillation_detected, data}, state) do
    # S2 detected oscillation patterns
    affected_nodes = extract_nodes_from_oscillation(data)
    
    # Update oscillation scores
    new_state = Enum.reduce(affected_nodes, state, fn {node_id, score}, acc ->
      behavior = get_or_create_behavior(node_id, acc)
      updated = %{behavior | oscillation_score: score}
      update_node_behavior(acc, node_id, updated)
    end)
    
    # Check if oscillation indicates Byzantine behavior
    new_state = Enum.reduce(affected_nodes, new_state, fn {node_id, _}, acc ->
      check_byzantine_patterns(node_id, acc)
    end)
    
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp init_detection_rules(opts) do
    %{
      double_vote_enabled: Keyword.get(opts, :double_vote_detection, true),
      flooding_enabled: Keyword.get(opts, :flooding_detection, true),
      inconsistency_enabled: Keyword.get(opts, :inconsistency_detection, true),
      oscillation_enabled: Keyword.get(opts, :oscillation_detection, true),
      custom_rules: Keyword.get(opts, :custom_rules, [])
    }
  end
  
  defp get_or_create_behavior(node_id, state) do
    Map.get(state.node_behaviors, node_id, %NodeBehavior{
      node_id: node_id,
      vote_history: [],
      message_rate: 0.0,
      state_consistency: 1.0,
      forwarding_ratio: 1.0,
      oscillation_score: 0.0,
      contradictions: [],
      last_activity: DateTime.utc_now(),
      suspicious_patterns: []
    })
  end
  
  defp detect_double_voting(behavior, belief_id, vote) do
    # Check vote history for contradictions
    contradiction = Enum.find(behavior.vote_history, fn {bid, v, _time} ->
      bid == belief_id && v != vote
    end)
    
    updated_history = [{belief_id, vote, DateTime.utc_now()} | behavior.vote_history]
    |> Enum.take(100)  # Keep last 100 votes
    
    if contradiction do
      Logger.warning("🚨 Double vote detected from #{behavior.node_id} on belief #{belief_id}")
      
      %{behavior | 
        vote_history: updated_history,
        contradictions: [contradiction | behavior.contradictions],
        suspicious_patterns: [:double_vote | behavior.suspicious_patterns]
      }
    else
      %{behavior | vote_history: updated_history}
    end
  end
  
  defp update_message_stats(behavior, message_type, size) do
    # Simple exponential moving average for message rate
    alpha = 0.1
    current_rate = behavior.message_rate
    new_rate = current_rate * (1 - alpha) + alpha
    
    %{behavior | 
      message_rate: new_rate,
      last_activity: DateTime.utc_now()
    }
  end
  
  defp detect_flooding(behavior) do
    if behavior.message_rate > @flooding_threshold do
      Logger.warning("🚨 Message flooding detected from #{behavior.node_id}: #{behavior.message_rate} msg/min")
      
      %{behavior | 
        suspicious_patterns: [:flooding | behavior.suspicious_patterns]
      }
    else
      behavior
    end
  end
  
  defp check_byzantine_patterns(node_id, state) do
    behavior = Map.get(state.node_behaviors, node_id)
    
    if behavior do
      # Calculate Byzantine score
      byzantine_score = calculate_byzantine_score(behavior)
      
      if byzantine_score > @byzantine_pattern_threshold do
        # Mark as Byzantine
        Logger.error("🚨 Byzantine node detected: #{node_id} (score: #{byzantine_score})")
        
        # Update Byzantine set
        new_byzantine = MapSet.put(state.byzantine_nodes, node_id)
        
        # Set reputation to minimum
        new_reputation = Map.put(state.reputation_scores, node_id, @min_reputation)
        
        # Publish Byzantine detection event
        EventBus.publish(:byzantine_node_detected, %{
          node_id: node_id,
          score: byzantine_score,
          patterns: behavior.suspicious_patterns,
          timestamp: DateTime.utc_now()
        })
        
        # Report to S2 coordination for network-wide damping
        Coordination.report_conflict(:byzantine_behavior, node_id, :network_trust)
        
        %{state | 
          byzantine_nodes: new_byzantine,
          reputation_scores: new_reputation,
          metrics: update_metrics(state.metrics, :byzantine_detected)
        }
      else
        # Update reputation based on behavior
        new_reputation = calculate_reputation(behavior, byzantine_score)
        new_scores = Map.put(state.reputation_scores, node_id, new_reputation)
        
        %{state | reputation_scores: new_scores}
      end
    else
      state
    end
  end
  
  defp calculate_byzantine_score(behavior) do
    # Weighted scoring of suspicious patterns
    pattern_scores = %{
      double_vote: 0.4,
      flooding: 0.3,
      inconsistent_state: 0.3,
      selective_forwarding: 0.2,
      high_oscillation: 0.3
    }
    
    base_score = behavior.suspicious_patterns
    |> Enum.uniq()
    |> Enum.map(&Map.get(pattern_scores, &1, 0.1))
    |> Enum.sum()
    
    # Factor in contradiction count
    contradiction_factor = min(1.0, length(behavior.contradictions) / @double_vote_threshold)
    
    # Factor in oscillation score from S2
    oscillation_factor = if behavior.oscillation_score > 0.5, do: 0.3, else: 0.0
    
    # Factor in message flooding
    flooding_factor = if behavior.message_rate > @flooding_threshold, do: 0.2, else: 0.0
    
    min(1.0, base_score + contradiction_factor * 0.3 + oscillation_factor + flooding_factor)
  end
  
  defp calculate_reputation(behavior, byzantine_score) do
    # Start with perfect reputation
    base_reputation = 1.0
    
    # Deduct for Byzantine score
    reputation = base_reputation - (byzantine_score * 0.5)
    
    # Deduct for suspicious patterns
    pattern_penalty = length(behavior.suspicious_patterns) * 0.1
    reputation = reputation - pattern_penalty
    
    # Bonus for consistent good behavior
    consistency_bonus = if behavior.state_consistency > 0.9, do: 0.1, else: 0.0
    reputation = reputation + consistency_bonus
    
    # Clamp to valid range
    max(@min_reputation, min(1.0, reputation))
  end
  
  defp update_node_behavior(state, node_id, behavior) do
    new_behaviors = Map.put(state.node_behaviors, node_id, behavior)
    %{state | node_behaviors: new_behaviors}
  end
  
  defp analyze_all_behaviors(state) do
    # Comprehensive analysis of all node behaviors
    state.node_behaviors
    |> Enum.reduce(state, fn {node_id, behavior}, acc ->
      # Check for stale nodes
      if stale_node?(behavior) do
        # Remove stale node data
        remove_node_data(acc, node_id)
      else
        # Re-evaluate Byzantine status
        check_byzantine_patterns(node_id, acc)
      end
    end)
  end
  
  defp stale_node?(behavior) do
    # Node is stale if no activity for 1 hour
    DateTime.diff(DateTime.utc_now(), behavior.last_activity, :second) > 3600
  end
  
  defp remove_node_data(state, node_id) do
    %{state |
      node_behaviors: Map.delete(state.node_behaviors, node_id),
      reputation_scores: Map.delete(state.reputation_scores, node_id)
    }
  end
  
  defp connect_to_s2_coordination do
    # Establish connection to S2 for oscillation data
    Process.whereis(AutonomousOpponentV2Core.VSM.S2.Coordination)
  end
  
  defp extract_nodes_from_oscillation(oscillation_data) do
    # Extract node IDs and scores from S2 oscillation data
    oscillation_data[:affected_units]
    |> Enum.map(fn unit ->
      # Assume unit ID contains node ID
      node_id = extract_node_id(unit)
      score = oscillation_data[:severity] || 0.5
      {node_id, score}
    end)
    |> Enum.filter(fn {node_id, _} -> node_id != nil end)
  end
  
  defp extract_node_id(unit_identifier) do
    # Extract node ID from unit identifier
    # Format: "belief_consensus_s1_node123" -> "node123"
    case String.split(unit_identifier, "_") do
      [_, _, _, node_id] -> node_id
      _ -> nil
    end
  end
  
  defp init_metrics do
    %{
      nodes_monitored: 0,
      byzantine_detected: 0,
      double_votes_detected: 0,
      flooding_detected: 0,
      reputation_updates: 0,
      last_analysis: DateTime.utc_now()
    }
  end
  
  defp update_metrics(metrics, event) do
    case event do
      :byzantine_detected ->
        %{metrics | byzantine_detected: metrics.byzantine_detected + 1}
      :double_vote ->
        %{metrics | double_votes_detected: metrics.double_votes_detected + 1}
      :flooding ->
        %{metrics | flooding_detected: metrics.flooding_detected + 1}
      _ ->
        metrics
    end
  end
  
  defp schedule_reputation_decay do
    # Decay reputation every hour
    Process.send_after(self(), :decay_reputation, :timer.hours(1))
  end
  
  defp schedule_behavior_analysis do
    # Analyze behaviors every 5 minutes
    Process.send_after(self(), :analyze_behaviors, :timer.minutes(5))
  end
end