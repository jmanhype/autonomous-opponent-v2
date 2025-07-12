defmodule AutonomousOpponentV2Core.VSM.BeliefConsensus do
  @moduledoc """
  VSM-aligned CRDT Belief Consensus implementation for Issue #93.
  
  This module implements distributed belief consensus using OR-Set CRDTs
  while maintaining strict adherence to Stafford Beer's VSM principles:
  
  1. Variety Management - Controls belief variety at each VSM level
  2. Requisite Variety - Ensures sufficient variety to match environment
  3. Recursive Structure - Beliefs exist at multiple system levels
  4. Algedonic Bypass - Emergency belief changes bypass hierarchy
  5. Homeostatic Regulation - Maintains belief system stability
  
  The implementation uses OR-Set CRDTs for their natural conflict resolution
  and variety handling capabilities.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: Algedonic
  alias AutonomousOpponentV2Core.VSM.Channels.VarietyChannel
  
  # Belief consensus thresholds
  @consensus_threshold 0.66        # 2/3 majority for consensus
  @critical_belief_threshold 0.95  # Triggers algedonic bypass
  @oscillation_threshold 3         # Number of flips before damping
  @belief_ttl_ms 3_600_000        # 1 hour belief TTL
  @max_belief_variety 100         # Maximum beliefs per level
  
  # Variety management parameters
  @attenuation_factor 0.7         # Reduces variety by 30%
  @amplification_factor 1.3       # Increases variety by 30%
  @damping_factor 0.3            # Oscillation damping
  
  defstruct [
    :node_id,
    :vsm_level,                   # S1, S2, S3, S4, or S5
    :belief_sets,                 # Map of belief set IDs
    :consensus_state,             # Current consensus
    :variety_state,               # Variety management state
    :oscillation_tracker,         # Tracks belief oscillations
    :algedonic_monitor,          # Monitors critical beliefs
    :recursive_links,            # Links to other levels
    :metrics,                    # Performance metrics
    :constraints                 # Policy constraints from S5
  ]
  
  # Belief structure
  defmodule Belief do
    @enforce_keys [:id, :content, :source, :weight, :timestamp]
    defstruct [
      :id,
      :content,              # The actual belief
      :source,              # Which subsystem generated it
      :weight,              # Belief strength (0.0 - 1.0)
      :confidence,          # Confidence level
      :evidence,            # Supporting evidence
      :timestamp,           # When created
      :hlc_timestamp,       # HLC timestamp for causal ordering
      :ttl,                # Time to live
      :contradictions,      # Known contradictions
      :validation_status    # Environmental validation
    ]
  end
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: name_for_level(opts[:vsm_level]))
  end
  
  @doc """
  Propose a new belief to the consensus system.
  """
  def propose_belief(level, belief_content, metadata \\ %{}) do
    GenServer.call(name_for_level(level), {:propose_belief, belief_content, metadata})
  end
  
  @doc """
  Get current belief consensus for a VSM level.
  """
  def get_consensus(level) do
    GenServer.call(name_for_level(level), :get_consensus)
  end
  
  @doc """
  Force belief consensus (S3 control intervention).
  """
  def force_consensus(level, beliefs) do
    GenServer.call(name_for_level(level), {:force_consensus, beliefs})
  end
  
  @doc """
  Get belief system metrics.
  """
  def get_metrics(level) do
    GenServer.call(name_for_level(level), :get_metrics)
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    vsm_level = Keyword.fetch!(opts, :vsm_level)
    node_id = Keyword.get(opts, :node_id, generate_node_id())
    
    # Create belief sets for this level
    belief_sets = initialize_belief_sets(vsm_level, node_id)
    
    # Subscribe to relevant events
    subscribe_to_events(vsm_level)
    
    # Initialize variety management
    variety_state = init_variety_management(vsm_level)
    
    # Start monitoring timers
    schedule_consensus_check()
    schedule_belief_cleanup()
    schedule_metrics_update()
    
    state = %__MODULE__{
      node_id: node_id,
      vsm_level: vsm_level,
      belief_sets: belief_sets,
      consensus_state: %{
        current: MapSet.new(),
        pending: MapSet.new(),
        history: []
      },
      variety_state: variety_state,
      oscillation_tracker: %{},
      algedonic_monitor: init_algedonic_monitor(vsm_level),
      recursive_links: establish_recursive_links(vsm_level),
      metrics: init_metrics(),
      constraints: %{}
    }
    
    Logger.info("🧠 VSM Belief Consensus initialized for level #{vsm_level}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:propose_belief, content, metadata}, _from, state) do
    # Create belief with HLC timestamp
    {:ok, hlc_event} = Clock.create_event(:belief_consensus, :belief_proposed, %{
      level: state.vsm_level,
      content: content
    })
    
    belief = %Belief{
      id: generate_belief_id(),
      content: content,
      source: metadata[:source] || state.node_id,
      weight: metadata[:weight] || 0.5,
      confidence: metadata[:confidence] || 0.7,
      evidence: metadata[:evidence] || [],
      timestamp: DateTime.utc_now(),
      hlc_timestamp: hlc_event.timestamp,
      ttl: @belief_ttl_ms,
      contradictions: [],
      validation_status: :pending
    }
    
    # Check variety constraints
    case check_variety_constraints(belief, state) do
      :ok ->
        # Add to appropriate belief set
        new_state = add_belief_to_set(belief, state)
        
        # Check if this triggers algedonic response
        check_algedonic_trigger(belief, new_state)
        
        # Propagate through variety channels
        propagate_belief(belief, new_state)
        
        {:reply, {:ok, belief.id}, new_state}
        
      {:error, :variety_exceeded} ->
        # Apply attenuation
        attenuated_state = attenuate_beliefs(state)
        
        # Try again with reduced variety
        new_state = add_belief_to_set(belief, attenuated_state)
        {:reply, {:ok, belief.id}, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_consensus, _from, state) do
    consensus = calculate_current_consensus(state)
    {:reply, {:ok, consensus}, state}
  end
  
  @impl true
  def handle_call({:force_consensus, beliefs}, _from, state) do
    # S3 control intervention - bypass normal consensus
    Logger.warning("⚡ Forced consensus from S3 Control for #{state.vsm_level}")
    
    new_consensus = MapSet.new(beliefs)
    
    # Update consensus state
    new_state = %{state |
      consensus_state: %{
        current: new_consensus,
        pending: MapSet.new(),
        history: [state.consensus_state.current | state.consensus_state.history]
      }
    }
    
    # Notify other levels
    broadcast_consensus_change(new_consensus, new_state)
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      belief_count: count_total_beliefs(state),
      consensus_size: MapSet.size(state.consensus_state.current),
      variety_ratio: calculate_variety_ratio(state),
      oscillation_count: map_size(state.oscillation_tracker),
      algedonic_triggers: state.metrics.algedonic_triggers,
      consensus_quality: calculate_consensus_quality(state)
    }
    
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_info(:check_consensus, state) do
    # Periodic consensus recalculation
    new_state = recalculate_consensus(state)
    
    # Check for oscillations
    new_state = detect_and_damp_oscillations(new_state)
    
    # Schedule next check
    schedule_consensus_check()
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:cleanup_beliefs, state) do
    # Remove expired beliefs
    new_state = cleanup_expired_beliefs(state)
    
    # Schedule next cleanup
    schedule_belief_cleanup()
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:update_metrics, state) do
    # Calculate and publish metrics
    metrics = calculate_detailed_metrics(state)
    
    EventBus.publish(:belief_consensus_metrics, %{
      level: state.vsm_level,
      metrics: metrics,
      timestamp: DateTime.utc_now()
    })
    
    # Schedule next update
    schedule_metrics_update()
    
    {:noreply, update_metrics(state, metrics)}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, event}, state) do
    # Handle HLC-ordered events
    handle_info({:event, event.type, event.data}, state)
  end
  
  @impl true
  def handle_info({:event, :belief_proposed, data}, state) do
    # Handle beliefs from other subsystems
    case data.level do
      level when level < state.vsm_level ->
        # Belief from lower level - aggregate
        handle_lower_level_belief(data, state)
        
      level when level > state.vsm_level ->
        # Belief from higher level - constrain
        handle_higher_level_belief(data, state)
        
      _ ->
        # Same level - coordinate
        handle_peer_belief(data, state)
    end
  end
  
  @impl true
  def handle_info({:event, :s5_belief_constraint, constraint}, state) do
    # Policy constraints from S5
    new_constraints = Map.put(state.constraints, constraint.id, constraint)
    
    # Re-evaluate current beliefs against new constraints
    new_state = apply_policy_constraints(%{state | constraints: new_constraints})
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :algedonic_pain, pain_signal}, state) do
    # Emergency belief adjustment
    Logger.error("🚨 Algedonic pain signal received by belief consensus: #{inspect(pain_signal)}")
    
    # Identify problematic beliefs
    problematic_beliefs = identify_pain_causing_beliefs(pain_signal, state)
    
    # Emergency belief revision
    new_state = emergency_belief_revision(problematic_beliefs, state)
    
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp initialize_belief_sets(vsm_level, node_id) do
    # Create OR-Set CRDTs for different belief categories
    categories = case vsm_level do
      :s1 -> [:operational, :environmental, :performance]
      :s2 -> [:coordination, :conflict_resolution, :harmony]
      :s3 -> [:control, :resource, :intervention]
      :s4 -> [:patterns, :predictions, :learning]
      :s5 -> [:identity, :policy, :ethics]
    end
    
    Enum.map(categories, fn category ->
      set_id = "belief_#{vsm_level}_#{category}_#{node_id}"
      {:ok, _} = CRDTStore.create_crdt(set_id, :or_set)
      {category, set_id}
    end)
    |> Map.new()
  end
  
  defp subscribe_to_events(vsm_level) do
    # Subscribe to belief-related events
    EventBus.subscribe(:belief_proposed)
    EventBus.subscribe(:belief_validated)
    EventBus.subscribe(:belief_contradiction)
    
    # Level-specific subscriptions
    case vsm_level do
      :s1 -> 
        EventBus.subscribe(:operational_event)
        EventBus.subscribe(:environmental_change)
        
      :s2 ->
        EventBus.subscribe(:coordination_required)
        EventBus.subscribe(:conflict_detected)
        
      :s3 ->
        EventBus.subscribe(:resource_constraint)
        EventBus.subscribe(:intervention_needed)
        
      :s4 ->
        EventBus.subscribe(:pattern_detected)
        EventBus.subscribe(:prediction_made)
        
      :s5 ->
        EventBus.subscribe(:policy_violation)
        EventBus.subscribe(:ethical_concern)
    end
    
    # Always subscribe to algedonic signals
    EventBus.subscribe(:algedonic_pain)
    EventBus.subscribe(:algedonic_pleasure)
  end
  
  defp init_variety_management(vsm_level) do
    # Level-specific variety parameters
    channel_capacity = case vsm_level do
      :s1 -> 50   # High variety at operational level
      :s2 -> 40   # Moderate variety for coordination
      :s3 -> 30   # Controlled variety for management
      :s4 -> 35   # Moderate variety for intelligence
      :s5 -> 20   # Low variety for policy
    end
    
    %{
      channel_capacity: channel_capacity,
      current_variety: 0,
      attenuation_active: false,
      amplification_active: false,
      variety_history: []
    }
  end
  
  defp check_variety_constraints(belief, state) do
    current_variety = calculate_current_variety(state)
    
    if current_variety >= state.variety_state.channel_capacity do
      {:error, :variety_exceeded}
    else
      :ok
    end
  end
  
  defp calculate_current_variety(state) do
    # Count unique belief patterns
    all_beliefs = get_all_beliefs(state)
    
    all_beliefs
    |> Enum.map(&hash_belief_content/1)
    |> Enum.uniq()
    |> length()
  end
  
  defp attenuate_beliefs(state) do
    Logger.info("📉 Attenuating belief variety for #{state.vsm_level}")
    
    # Group similar beliefs
    clustered = cluster_similar_beliefs(state)
    
    # Keep only representative beliefs
    representative_beliefs = select_representatives(clustered)
    
    # Update belief sets
    update_belief_sets(representative_beliefs, state)
  end
  
  defp add_belief_to_set(belief, state) do
    # Determine appropriate set based on belief content
    category = categorize_belief(belief, state.vsm_level)
    set_id = state.belief_sets[category]
    
    # Add to CRDT
    :ok = CRDTStore.update_crdt(set_id, :add, belief)
    
    # Update metrics
    update_belief_metrics(belief, state)
  end
  
  defp check_algedonic_trigger(belief, state) do
    urgency = calculate_belief_urgency(belief)
    
    if urgency > @critical_belief_threshold do
      # Trigger algedonic bypass
      Algedonic.emergency_scream(
        :belief_consensus,
        "CRITICAL BELIEF: #{inspect(belief.content)}"
      )
      
      # Force immediate consensus
      force_immediate_consensus(belief, state)
    end
  end
  
  defp calculate_belief_urgency(belief) do
    base_urgency = belief.weight
    
    # Adjust for evidence strength
    evidence_factor = min(1.0, length(belief.evidence) / 10.0)
    
    # Adjust for contradictions
    contradiction_factor = 1.0 + (length(belief.contradictions) * 0.1)
    
    # Adjust for source credibility
    source_factor = get_source_credibility(belief.source)
    
    min(1.0, base_urgency * evidence_factor * contradiction_factor * source_factor)
  end
  
  defp propagate_belief(belief, state) do
    # Propagate through appropriate variety channels
    case state.vsm_level do
      :s1 -> VarietyChannel.send_message(:s1_to_s2, wrap_belief(belief))
      :s2 -> VarietyChannel.send_message(:s2_to_s3, wrap_belief(belief))
      :s3 -> VarietyChannel.send_message(:s3_to_s4, wrap_belief(belief))
      :s4 -> VarietyChannel.send_message(:s4_to_s5, wrap_belief(belief))
      :s5 -> VarietyChannel.send_message(:s5_to_all, wrap_belief(belief))
    end
  end
  
  defp calculate_current_consensus(state) do
    # Get all beliefs from all sets
    all_beliefs = get_all_beliefs(state)
    
    # Group by content similarity
    belief_groups = group_by_similarity(all_beliefs)
    
    # Calculate support for each group
    consensus_beliefs = belief_groups
    |> Enum.filter(fn group ->
      calculate_group_support(group) >= @consensus_threshold
    end)
    |> Enum.map(&select_group_representative/1)
    
    %{
      beliefs: consensus_beliefs,
      strength: calculate_consensus_strength(consensus_beliefs),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp recalculate_consensus(state) do
    # Get current consensus
    new_consensus = calculate_current_consensus(state)
    
    # Check if consensus changed
    if consensus_changed?(state.consensus_state.current, new_consensus) do
      # Update state
      new_state = %{state |
        consensus_state: %{
          current: new_consensus,
          pending: state.consensus_state.current,
          history: [state.consensus_state.current | state.consensus_state.history]
        }
      }
      
      # Broadcast change
      broadcast_consensus_change(new_consensus, new_state)
      
      new_state
    else
      state
    end
  end
  
  defp detect_and_damp_oscillations(state) do
    # Check belief history for oscillations
    oscillating_beliefs = detect_oscillating_beliefs(state.consensus_state.history)
    
    if Enum.any?(oscillating_beliefs) do
      Logger.warning("🔄 Belief oscillation detected in #{state.vsm_level}")
      
      # Apply damping
      damped_beliefs = apply_damping(oscillating_beliefs, @damping_factor)
      
      # Update tracker
      new_tracker = update_oscillation_tracker(state.oscillation_tracker, oscillating_beliefs)
      
      %{state | oscillation_tracker: new_tracker}
      |> update_damped_beliefs(damped_beliefs)
    else
      state
    end
  end
  
  defp handle_lower_level_belief(belief_data, state) do
    # Aggregate beliefs from lower levels
    aggregated = aggregate_lower_belief(belief_data, state)
    
    # Check if this changes our consensus
    new_state = add_belief_to_set(aggregated, state)
    
    {:noreply, new_state}
  end
  
  defp handle_higher_level_belief(belief_data, state) do
    # Apply constraints from higher levels
    constrained_state = apply_higher_level_constraint(belief_data, state)
    
    {:noreply, constrained_state}
  end
  
  defp handle_peer_belief(belief_data, state) do
    # Coordinate with peer beliefs
    coordinated_state = coordinate_peer_belief(belief_data, state)
    
    {:noreply, coordinated_state}
  end
  
  defp apply_policy_constraints(state) do
    # Get all current beliefs
    all_beliefs = get_all_beliefs(state)
    
    # Filter out policy violations
    compliant_beliefs = Enum.filter(all_beliefs, fn belief ->
      Enum.all?(state.constraints, fn {_id, constraint} ->
        evaluate_constraint(belief, constraint)
      end)
    end)
    
    # Update belief sets with compliant beliefs
    update_belief_sets(compliant_beliefs, state)
  end
  
  defp emergency_belief_revision(problematic_beliefs, state) do
    Logger.error("🚨 Emergency belief revision for #{length(problematic_beliefs)} beliefs")
    
    # Remove problematic beliefs
    cleaned_state = remove_beliefs(problematic_beliefs, state)
    
    # Generate corrective beliefs
    corrective_beliefs = generate_corrective_beliefs(problematic_beliefs, state)
    
    # Add corrective beliefs with high priority
    Enum.reduce(corrective_beliefs, cleaned_state, fn belief, acc ->
      add_belief_to_set(%{belief | weight: 1.0}, acc)
    end)
  end
  
  # Helper functions
  
  defp name_for_level(level) do
    :"belief_consensus_#{level}"
  end
  
  defp generate_node_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp generate_belief_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp schedule_consensus_check do
    Process.send_after(self(), :check_consensus, 5_000)
  end
  
  defp schedule_belief_cleanup do
    Process.send_after(self(), :cleanup_beliefs, 60_000)
  end
  
  defp schedule_metrics_update do
    Process.send_after(self(), :update_metrics, 10_000)
  end
  
  defp init_metrics do
    %{
      beliefs_proposed: 0,
      beliefs_accepted: 0,
      beliefs_rejected: 0,
      consensus_changes: 0,
      oscillations_damped: 0,
      algedonic_triggers: 0,
      variety_attenuations: 0,
      variety_amplifications: 0
    }
  end
  
  defp init_algedonic_monitor(vsm_level) do
    %{
      threshold: @critical_belief_threshold,
      recent_triggers: [],
      monitoring_active: true
    }
  end
  
  defp establish_recursive_links(vsm_level) do
    # Define hierarchical relationships
    %{
      parent: parent_level(vsm_level),
      children: child_levels(vsm_level),
      peers: peer_levels(vsm_level)
    }
  end
  
  defp parent_level(:s1), do: :s2
  defp parent_level(:s2), do: :s3
  defp parent_level(:s3), do: :s4
  defp parent_level(:s4), do: :s5
  defp parent_level(:s5), do: nil
  
  defp child_levels(:s5), do: [:s1, :s2, :s3, :s4]
  defp child_levels(:s4), do: [:s3]
  defp child_levels(:s3), do: [:s2]
  defp child_levels(:s2), do: [:s1]
  defp child_levels(:s1), do: []
  
  defp peer_levels(level) do
    # For now, no peer relationships
    []
  end
  
  defp categorize_belief(belief, vsm_level) do
    # Simple categorization based on content analysis
    # In production, this would use NLP or pattern matching
    case vsm_level do
      :s1 -> :operational
      :s2 -> :coordination
      :s3 -> :control
      :s4 -> :patterns
      :s5 -> :policy
    end
  end
  
  defp get_all_beliefs(state) do
    Enum.flat_map(state.belief_sets, fn {_category, set_id} ->
      case CRDTStore.get_crdt(set_id) do
        {:ok, beliefs} -> beliefs
        _ -> []
      end
    end)
  end
  
  defp hash_belief_content(belief) do
    :crypto.hash(:sha256, :erlang.term_to_binary(belief.content))
    |> Base.encode16()
  end
  
  defp wrap_belief(belief) do
    %{
      belief: belief,
      source_level: belief.source,
      timestamp: belief.timestamp,
      hlc_timestamp: belief.hlc_timestamp
    }
  end
  
  defp calculate_consensus_quality(state) do
    # Quality factors
    total_beliefs = count_total_beliefs(state)
    consensus_size = MapSet.size(state.consensus_state.current)
    
    if total_beliefs == 0 do
      0.0
    else
      # Ratio of consensus to total beliefs
      coverage = consensus_size / total_beliefs
      
      # Penalty for oscillations
      oscillation_penalty = min(0.3, map_size(state.oscillation_tracker) * 0.05)
      
      # Bonus for stability
      stability_bonus = if length(state.consensus_state.history) > 5 do
        0.1
      else
        0.0
      end
      
      max(0.0, min(1.0, coverage - oscillation_penalty + stability_bonus))
    end
  end
  
  defp count_total_beliefs(state) do
    get_all_beliefs(state) |> length()
  end
  
  defp get_source_credibility(source) do
    # In production, this would track source reliability
    0.8
  end
  
  # Reputation-based voting functions
  
  @doc """
  Vote on a belief with reputation weighting.
  """
  def vote_on_belief(level, belief_id, vote) do
    GenServer.call(name_for_level(level), {:vote_on_belief, belief_id, vote})
  end
  
  @doc """
  Get voting results for a belief.
  """
  def get_belief_votes(level, belief_id) do
    GenServer.call(name_for_level(level), {:get_belief_votes, belief_id})
  end
  
  @impl true
  def handle_call({:vote_on_belief, belief_id, vote}, {from_pid, _}, state) do
    # Get voter node ID (from Byzantine detector tracking)
    voter_id = get_voter_id(from_pid)
    
    # Get reputation from Byzantine detector
    reputation = ByzantineDetector.get_reputation(voter_id)
    
    # Apply reputation weighting
    weighted_vote = vote * reputation
    
    # Record vote
    new_state = record_belief_vote(state, belief_id, voter_id, weighted_vote)
    
    # Check if consensus threshold reached
    case check_vote_consensus(new_state, belief_id) do
      {:consensus_reached, belief} ->
        # Update consensus state
        new_consensus_state = add_to_consensus(state.consensus_state, belief)
        final_state = %{new_state | consensus_state: new_consensus_state}
        
        # Broadcast consensus achievement
        EventBus.publish(:belief_consensus_reached, %{
          level: state.vsm_level,
          belief: belief,
          vote_count: get_vote_count(final_state, belief_id),
          timestamp: DateTime.utc_now()
        })
        
        {:reply, {:ok, :consensus_reached}, final_state}
        
      :more_votes_needed ->
        {:reply, {:ok, :vote_recorded}, new_state}
    end
  end
  
  @impl true
  def handle_call({:get_belief_votes, belief_id}, _from, state) do
    votes = get_belief_vote_details(state, belief_id)
    {:reply, {:ok, votes}, state}
  end
  
  @impl true
  def handle_call(:get_full_state, _from, state) do
    # For delta sync full state recovery
    full_state = %{
      beliefs: get_all_beliefs(state),
      consensus: state.consensus_state.current,
      vector_clock: get_vector_clock(state),
      node_id: state.node_id
    }
    
    {:reply, {:ok, full_state}, state}
  end
  
  # Voting helper functions
  
  defp get_voter_id(from_pid) do
    # In production, map PID to registered node ID
    # For now, generate based on PID
    "voter_#{:erlang.phash2(from_pid)}"
  end
  
  defp record_belief_vote(state, belief_id, voter_id, weighted_vote) do
    # Initialize vote tracking if needed
    votes = Map.get(state, :belief_votes, %{})
    belief_votes = Map.get(votes, belief_id, %{
      votes: %{},
      total_weight: 0.0,
      first_vote_time: DateTime.utc_now()
    })
    
    # Record this vote
    updated_votes = %{belief_votes |
      votes: Map.put(belief_votes.votes, voter_id, weighted_vote),
      total_weight: belief_votes.total_weight + weighted_vote
    }
    
    # Update state
    new_votes = Map.put(votes, belief_id, updated_votes)
    Map.put(state, :belief_votes, new_votes)
  end
  
  defp check_vote_consensus(state, belief_id) do
    votes = Map.get(state, :belief_votes, %{})
    belief_votes = Map.get(votes, belief_id)
    
    if belief_votes do
      # Get the actual belief
      belief = find_belief_by_id(state, belief_id)
      
      if belief do
        # Check if we have enough weighted votes
        vote_ratio = belief_votes.total_weight / get_required_vote_weight(state)
        
        if vote_ratio >= @consensus_threshold do
          {:consensus_reached, belief}
        else
          :more_votes_needed
        end
      else
        :more_votes_needed
      end
    else
      :more_votes_needed
    end
  end
  
  defp find_belief_by_id(state, belief_id) do
    get_all_beliefs(state)
    |> Enum.find(fn belief -> belief.id == belief_id end)
  end
  
  defp get_required_vote_weight(state) do
    # In production, this would be based on active node count
    # For now, assume 3 nodes with average reputation 0.8
    case state.vsm_level do
      :s5 -> 2.0  # Higher threshold for policy
      :s4 -> 1.8  # High threshold for intelligence
      :s3 -> 1.6  # Moderate for control
      :s2 -> 1.4  # Lower for coordination
      :s1 -> 1.2  # Lowest for operations
    end
  end
  
  defp add_to_consensus(consensus_state, belief) do
    %{consensus_state |
      current: MapSet.put(consensus_state.current, belief),
      pending: MapSet.delete(consensus_state.pending, belief),
      history: [consensus_state.current | Enum.take(consensus_state.history, 9)]
    }
  end
  
  defp get_vote_count(state, belief_id) do
    case Map.get(state.belief_votes || %{}, belief_id) do
      nil -> 0
      belief_votes -> map_size(belief_votes.votes)
    end
  end
  
  defp get_belief_vote_details(state, belief_id) do
    case Map.get(state.belief_votes || %{}, belief_id) do
      nil -> 
        %{found: false}
        
      belief_votes ->
        %{
          found: true,
          votes: belief_votes.votes,
          total_weight: belief_votes.total_weight,
          vote_count: map_size(belief_votes.votes),
          consensus_threshold: @consensus_threshold * get_required_vote_weight(state),
          first_vote_time: belief_votes.first_vote_time,
          consensus_reached: belief_votes.total_weight >= (@consensus_threshold * get_required_vote_weight(state))
        }
    end
  end
  
  defp get_vector_clock(state) do
    # For delta sync - return current vector clock
    Map.get(state, :vector_clock, %{state.node_id => 0})
  end
  
  # Add Byzantine detector alias
  alias AutonomousOpponentV2Core.VSM.BeliefConsensus.ByzantineDetector
  
  # ===== MISSING FUNCTION IMPLEMENTATIONS =====
  
  # Core Consensus Functions
  
  defp group_by_similarity(beliefs) do
    # Group beliefs by semantic content similarity using first 3 words
    beliefs
    |> Enum.group_by(fn belief ->
      belief.content
      |> String.downcase()
      |> String.replace(~r/[^\w\s]/, "")  # Remove punctuation
      |> String.split()
      |> Enum.take(3)  # First 3 words as grouping key
      |> Enum.join(" ")
    end)
    |> Map.values()  # Return list of groups
  end
  
  defp calculate_group_support(group) do
    # Calculate weighted support for a group of beliefs
    if Enum.empty?(group) do
      0.0
    else
      total_weight = Enum.sum(Enum.map(group, & &1.weight))
      avg_confidence = Enum.sum(Enum.map(group, & &1.confidence)) / length(group)
      # Support is average of weight and confidence
      (total_weight / length(group) + avg_confidence) / 2
    end
  end
  
  defp select_group_representative(group) do
    # Pick the belief with highest weight * confidence score
    Enum.max_by(group, fn belief ->
      belief.weight * belief.confidence
    end, fn -> hd(group) end)
  end
  
  defp calculate_consensus_strength(beliefs) do
    if Enum.empty?(beliefs) do
      0.0
    else
      # Calculate strength based on agreement and confidence
      avg_confidence = beliefs |> Enum.map(& &1.confidence) |> Enum.sum() |> Kernel./(length(beliefs))
      avg_weight = beliefs |> Enum.map(& &1.weight) |> Enum.sum() |> Kernel./(length(beliefs))
      belief_diversity = calculate_belief_diversity(beliefs)
      
      # Higher diversity slightly reduces strength (indicates less agreement)
      base_strength = (avg_confidence + avg_weight) / 2
      base_strength * (1 - belief_diversity * 0.2)
    end
  end
  
  defp calculate_belief_diversity(beliefs) do
    # Calculate diversity as ratio of unique content to total beliefs
    unique_content = beliefs |> Enum.map(& &1.content) |> Enum.uniq() |> length()
    total_beliefs = length(beliefs)
    
    if total_beliefs > 0 do
      unique_content / total_beliefs
    else
      0.0
    end
  end
  
  defp consensus_changed?(old_consensus, new_consensus) do
    case {old_consensus, new_consensus} do
      {%MapSet{} = old, %MapSet{} = new} -> 
        MapSet.size(MapSet.symmetric_difference(old, new)) > 0
      {old, new} when is_map(old) and is_map(new) ->
        old_beliefs = Map.get(old, :beliefs, []) |> Enum.map(& &1.id) |> MapSet.new()
        new_beliefs = Map.get(new, :beliefs, []) |> Enum.map(& &1.id) |> MapSet.new()
        MapSet.size(MapSet.symmetric_difference(old_beliefs, new_beliefs)) > 0
      _ -> 
        true  # Different types = changed
    end
  end
  
  defp broadcast_consensus_change(consensus, state) do
    EventBus.publish(:belief_consensus_update, %{
      level: state.vsm_level,
      consensus: consensus,
      node_id: state.node_id,
      timestamp: DateTime.utc_now(),
      strength: Map.get(consensus, :strength, 0.0),
      belief_count: length(Map.get(consensus, :beliefs, []))
    })
  end
  
  # Oscillation Management Functions
  
  defp detect_oscillating_beliefs(history) do
    # Find beliefs that appear and disappear repeatedly in recent history
    recent_history = Enum.take(history, 10)
    
    # Extract all belief IDs from history
    all_belief_ids = recent_history
    |> Enum.flat_map(fn consensus ->
      case consensus do
        %MapSet{} = set -> MapSet.to_list(set) |> Enum.map(& &1.id)
        %{beliefs: beliefs} -> Enum.map(beliefs, & &1.id)
        _ -> []
      end
    end)
    
    # Count appearances and find oscillating ones
    all_belief_ids
    |> Enum.frequencies()
    |> Enum.filter(fn {_belief_id, count} -> 
      count >= @oscillation_threshold && count < length(recent_history)
    end)
    |> Enum.map(fn {belief_id, _count} -> belief_id end)
  end
  
  defp apply_damping(oscillating_beliefs, damping_factor) do
    # Reduce weight of oscillating beliefs to stabilize consensus
    Enum.map(oscillating_beliefs, fn belief_id ->
      # Find the actual belief and apply damping
      %{
        id: belief_id,
        damping_applied: true,
        damping_factor: damping_factor,
        timestamp: DateTime.utc_now()
      }
    end)
  end
  
  defp update_oscillation_tracker(tracker, oscillating_beliefs) do
    Enum.reduce(oscillating_beliefs, tracker, fn belief_id, acc ->
      Map.update(acc, belief_id, 1, &(&1 + 1))
    end)
  end
  
  defp update_damped_beliefs(state, damped_beliefs) do
    # Update state with information about damped beliefs
    damped_ids = Enum.map(damped_beliefs, & &1.id)
    
    # Add to metrics
    new_metrics = Map.update(state.metrics, :oscillations_damped, 0, &(&1 + length(damped_beliefs)))
    
    %{state | metrics: new_metrics}
  end
  
  # Belief Management Functions
  
  defp update_belief_sets(beliefs, state) do
    # Update all belief sets with new beliefs
    belief_categories = Enum.group_by(beliefs, fn belief ->
      categorize_belief(belief, state.vsm_level)
    end)
    
    # Update each category's CRDT set
    Enum.reduce(belief_categories, state, fn {category, category_beliefs}, acc ->
      set_id = Map.get(acc.belief_sets, category)
      
      if set_id do
        # Clear and repopulate the set
        Enum.each(category_beliefs, fn belief ->
          CRDTStore.update_crdt(set_id, :add, belief)
        end)
      end
      
      acc
    end)
  end
  
  defp cluster_similar_beliefs(state) do
    # Group similar beliefs for variety management
    all_beliefs = get_all_beliefs(state)
    
    belief_clusters = all_beliefs
    |> Enum.group_by(fn belief ->
      # Cluster by content similarity
      hash_belief_content(belief)
    end)
    
    # Return cluster representatives
    Map.values(belief_clusters)
    |> Enum.map(fn cluster ->
      # Pick representative with highest weight
      Enum.max_by(cluster, & &1.weight, fn -> hd(cluster) end)
    end)
  end
  
  defp select_representatives(clustered_beliefs) do
    # Already implemented in cluster_similar_beliefs
    clustered_beliefs
  end
  
  defp remove_beliefs(beliefs_to_remove, state) do
    # Remove beliefs from appropriate CRDT sets
    Enum.reduce(beliefs_to_remove, state, fn belief, acc ->
      category = categorize_belief(belief, acc.vsm_level)
      set_id = Map.get(acc.belief_sets, category)
      
      if set_id do
        CRDTStore.update_crdt(set_id, :remove, belief)
      end
      
      acc
    end)
  end
  
  defp cleanup_expired_beliefs(state) do
    # Remove beliefs past their TTL
    all_beliefs = get_all_beliefs(state)
    current_time = DateTime.utc_now()
    
    expired_beliefs = Enum.filter(all_beliefs, fn belief ->
      case belief.timestamp do
        nil -> false
        timestamp ->
          age_ms = DateTime.diff(current_time, timestamp, :millisecond)
          age_ms > @belief_ttl_ms
      end
    end)
    
    if Enum.any?(expired_beliefs) do
      Logger.info("🧹 Cleaning up #{length(expired_beliefs)} expired beliefs")
      remove_beliefs(expired_beliefs, state)
    else
      state
    end
  end
  
  # Emergency & Constraint Handling Functions
  
  defp force_immediate_consensus(belief, state) do
    # Force immediate consensus for critical beliefs (algedonic bypass)
    Logger.warning("⚡ Forcing immediate consensus for critical belief: #{belief.content}")
    
    # Create high-priority consensus
    emergency_consensus = %{
      beliefs: [belief],
      strength: 1.0,
      timestamp: DateTime.utc_now(),
      forced: true,
      algedonic_bypass: true
    }
    
    # Update state immediately
    new_consensus_state = %{state.consensus_state |
      current: emergency_consensus,
      history: [state.consensus_state.current | state.consensus_state.history]
    }
    
    # Broadcast emergency consensus
    EventBus.publish(:algedonic_consensus_forced, %{
      level: state.vsm_level,
      belief: belief,
      node_id: state.node_id
    })
    
    %{state | consensus_state: new_consensus_state}
  end
  
  defp generate_corrective_beliefs(problematic_beliefs, state) do
    # Generate corrective beliefs for problematic ones
    Enum.map(problematic_beliefs, fn belief ->
      %Belief{
        id: generate_belief_id(),
        content: "CORRECTIVE: Address issues with #{String.slice(belief.content, 0..50)}",
        source: "emergency_correction",
        weight: 1.0,
        confidence: 0.8,
        timestamp: DateTime.utc_now(),
        hlc_timestamp: nil,
        ttl: @belief_ttl_ms,
        contradictions: [belief.id],
        validation_status: :emergency
      }
    end)
  end
  
  defp identify_pain_causing_beliefs(pain_signal, state) do
    # Identify beliefs that might be causing system pain
    all_beliefs = get_all_beliefs(state)
    
    # Look for beliefs related to the pain signal
    related_beliefs = Enum.filter(all_beliefs, fn belief ->
      signal_keywords = extract_keywords(pain_signal.source || "")
      belief_keywords = extract_keywords(belief.content)
      
      # Check for keyword overlap
      overlap = MapSet.intersection(
        MapSet.new(signal_keywords),
        MapSet.new(belief_keywords)
      )
      
      MapSet.size(overlap) > 0
    end)
    
    # Sort by recency (newer beliefs more likely to cause current pain)
    Enum.sort_by(related_beliefs, & &1.timestamp, {:desc, DateTime})
  end
  
  defp extract_keywords(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 3))  # Filter short words
    |> Enum.take(5)  # Top 5 keywords
  end
  
  defp evaluate_constraint(belief, constraint) do
    # Evaluate if belief violates a policy constraint
    case constraint do
      %{type: :forbidden_content, pattern: pattern} ->
        not Regex.match?(pattern, belief.content)
        
      %{type: :weight_limit, max_weight: max_weight} ->
        belief.weight <= max_weight
        
      %{type: :source_restriction, allowed_sources: sources} ->
        belief.source in sources
        
      %{type: :confidence_threshold, min_confidence: min_conf} ->
        belief.confidence >= min_conf
        
      _ ->
        true  # Unknown constraint type, allow by default
    end
  end
  
  # Metrics & Monitoring Functions
  
  defp calculate_variety_ratio(state) do
    # Calculate current variety usage vs capacity
    current_variety = calculate_current_variety(state)
    max_variety = state.variety_state.channel_capacity
    
    if max_variety > 0 do
      current_variety / max_variety
    else
      0.0
    end
  end
  
  defp update_belief_metrics(belief, state) do
    # Update metrics when a belief is added
    new_metrics = state.metrics
    |> Map.update(:beliefs_proposed, 0, &(&1 + 1))
    |> Map.update(:total_belief_weight, 0.0, &(&1 + belief.weight))
    
    %{state | metrics: new_metrics}
  end
  
  defp update_metrics(state, metrics_update) do
    # Generic metrics update function
    new_metrics = Map.merge(state.metrics, metrics_update)
    %{state | metrics: new_metrics}
  end
  
  defp calculate_detailed_metrics(state) do
    # Calculate comprehensive metrics for reporting
    all_beliefs = get_all_beliefs(state)
    
    # Handle consensus_state.current which can be MapSet or map
    consensus_size = case state.consensus_state.current do
      %MapSet{} = set -> MapSet.size(set)
      %{beliefs: beliefs} -> length(beliefs)
      _ -> 0
    end
    
    %{
      belief_count: length(all_beliefs),
      consensus_size: consensus_size,
      variety_ratio: calculate_variety_ratio(state),
      oscillation_count: map_size(state.oscillation_tracker),
      algedonic_triggers: Map.get(state.metrics, :algedonic_triggers, 0),
      consensus_quality: calculate_consensus_quality(state),
      avg_belief_weight: calculate_avg_belief_weight(all_beliefs),
      avg_belief_confidence: calculate_avg_belief_confidence(all_beliefs),
      belief_age_distribution: calculate_belief_age_distribution(all_beliefs),
      source_distribution: calculate_source_distribution(all_beliefs)
    }
  end
  
  defp calculate_avg_belief_weight(beliefs) do
    if Enum.empty?(beliefs) do
      0.0
    else
      Enum.sum(Enum.map(beliefs, & &1.weight)) / length(beliefs)
    end
  end
  
  defp calculate_avg_belief_confidence(beliefs) do
    if Enum.empty?(beliefs) do
      0.0
    else
      Enum.sum(Enum.map(beliefs, & &1.confidence)) / length(beliefs)
    end
  end
  
  defp calculate_belief_age_distribution(beliefs) do
    now = DateTime.utc_now()
    
    age_buckets = beliefs
    |> Enum.map(fn belief ->
      case belief.timestamp do
        nil -> :unknown
        timestamp ->
          age_minutes = DateTime.diff(now, timestamp, :second) / 60
          cond do
            age_minutes < 5 -> :very_recent
            age_minutes < 30 -> :recent
            age_minutes < 120 -> :moderate
            true -> :old
          end
      end
    end)
    |> Enum.frequencies()
    
    Map.merge(%{very_recent: 0, recent: 0, moderate: 0, old: 0, unknown: 0}, age_buckets)
  end
  
  defp calculate_source_distribution(beliefs) do
    beliefs
    |> Enum.map(& &1.source)
    |> Enum.frequencies()
  end
  
  # VSM Level Integration Functions
  
  defp aggregate_lower_belief(belief_data, state) do
    # Aggregate belief from lower VSM level
    %Belief{
      id: generate_belief_id(),
      content: "AGGREGATED: #{belief_data.content}",
      source: "aggregated_from_#{belief_data.level}",
      weight: belief_data.weight * @attenuation_factor,  # Attenuate for higher level
      confidence: belief_data.confidence,
      timestamp: DateTime.utc_now(),
      hlc_timestamp: nil,
      ttl: @belief_ttl_ms,
      contradictions: [],
      validation_status: :aggregated
    }
  end
  
  defp apply_higher_level_constraint(belief_data, state) do
    # Apply constraints from higher VSM level
    constraint = %{
      type: :higher_level_override,
      source_level: belief_data.level,
      constraint_content: belief_data.content,
      applied_at: DateTime.utc_now()
    }
    
    # Add to constraints
    new_constraints = Map.put(state.constraints, constraint.source_level, constraint)
    
    # Re-evaluate current beliefs against new constraint
    %{state | constraints: new_constraints}
  end
  
  defp coordinate_peer_belief(belief_data, state) do
    # Coordinate with peer belief from same VSM level
    # For now, just add to our belief set with coordination marker
    coordinated_belief = %Belief{
      id: generate_belief_id(),
      content: belief_data.content,
      source: "coordinated_from_#{belief_data.source}",
      weight: belief_data.weight,
      confidence: belief_data.confidence * 0.9,  # Slight reduction for peer coordination
      timestamp: DateTime.utc_now(),
      hlc_timestamp: nil,
      ttl: @belief_ttl_ms,
      contradictions: [],
      validation_status: :peer_coordinated
    }
    
    add_belief_to_set(coordinated_belief, state)
  end
end