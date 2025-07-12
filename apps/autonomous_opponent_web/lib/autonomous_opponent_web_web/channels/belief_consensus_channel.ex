defmodule AutonomousOpponentWebWeb.Channels.BeliefConsensusChannel do
  @moduledoc """
  Phoenix Channel for real-time belief consensus with algedonic bypass.
  
  Provides WebSocket interface for:
  - Real-time belief voting and consensus updates
  - Sub-50ms algedonic bypass for critical beliefs
  - Byzantine node detection alerts
  - Consensus visualization data
  - Reputation-based voting weights
  
  This channel integrates with the VSM belief consensus system to provide
  low-latency updates to connected clients while respecting VSM principles.
  """
  
  use AutonomousOpponentWebWeb, :channel
  require Logger
  
  alias AutonomousOpponentV2Core.VSM.BeliefConsensus
  alias AutonomousOpponentV2Core.VSM.BeliefConsensus.{ByzantineDetector, DeltaSync}
  alias AutonomousOpponentV2Core.VSM.S2.Coordination
  alias AutonomousOpponentV2Core.EventBus
  alias Phoenix.Socket
  
  # Channel configuration
  @algedonic_threshold 0.9    # Urgency threshold for bypass
  @vote_timeout 30_000        # 30 seconds to vote
  @max_beliefs_per_min 100    # Rate limiting
  @consensus_update_interval 1_000  # Update every second
  
  # Track channel state
  defmodule ChannelState do
    defstruct [
      :node_id,
      :vsm_level,
      :reputation,
      :vote_count,
      :last_vote_time,
      :subscriptions,
      :algedonic_enabled,
      :consensus_timer
    ]
  end
  
  @impl true
  def join("beliefs:consensus:" <> level, payload, socket) do
    if authorized?(payload) do
      vsm_level = String.to_atom(level)
      node_id = generate_node_id(socket)
      
      # Get initial reputation
      reputation = ByzantineDetector.get_reputation(node_id)
      
      # Subscribe to relevant events
      EventBus.subscribe(:belief_consensus_update)
      EventBus.subscribe(:byzantine_node_detected)
      EventBus.subscribe(:algedonic_pain)
      EventBus.subscribe(:algedonic_pleasure)
      
      # Start consensus update timer
      timer_ref = schedule_consensus_update()
      
      # Initialize channel state
      state = %ChannelState{
        node_id: node_id,
        vsm_level: vsm_level,
        reputation: reputation,
        vote_count: 0,
        last_vote_time: nil,
        subscriptions: MapSet.new([vsm_level]),
        algedonic_enabled: true,
        consensus_timer: timer_ref
      }
      
      # Send initial state
      send(self(), :send_initial_state)
      
      socket = assign(socket, :channel_state, state)
      
      {:ok, %{node_id: node_id, reputation: reputation}, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end
  
  @impl true
  def join("beliefs:consensus", _payload, _socket) do
    {:error, %{reason: "must specify VSM level"}}
  end
  
  # Handle incoming messages
  
  @impl true
  def handle_in("propose_belief", %{"content" => content} = params, socket) do
    state = socket.assigns.channel_state
    
    # Rate limiting check
    if rate_limit_ok?(state) do
      # Check for algedonic bypass
      urgency = Map.get(params, "urgency", 0.5)
      
      result = if urgency >= @algedonic_threshold do
        handle_algedonic_belief(content, urgency, params, state)
      else
        handle_normal_belief(content, params, state)
      end
      
      case result do
        {:ok, belief_id} ->
          # Update state
          new_state = %{state | 
            vote_count: state.vote_count + 1,
            last_vote_time: DateTime.utc_now()
          }
          
          socket = assign(socket, :channel_state, new_state)
          
          {:reply, {:ok, %{belief_id: belief_id}}, socket}
          
        {:error, reason} ->
          {:reply, {:error, %{reason: reason}}, socket}
      end
    else
      {:reply, {:error, %{reason: "rate_limit_exceeded"}}, socket}
    end
  end
  
  @impl true
  def handle_in("vote_belief", %{"belief_id" => belief_id, "vote" => vote}, socket) do
    state = socket.assigns.channel_state
    
    # Record vote with Byzantine detection
    ByzantineDetector.record_vote(state.node_id, belief_id, vote)
    
    # Apply reputation weight
    weighted_vote = vote * state.reputation
    
    # Submit weighted vote
    case BeliefConsensus.vote_on_belief(state.vsm_level, belief_id, weighted_vote) do
      :ok ->
        {:reply, {:ok, %{weighted_vote: weighted_vote}}, socket}
      error ->
        {:reply, {:error, %{reason: inspect(error)}}, socket}
    end
  end
  
  @impl true
  def handle_in("get_consensus", _params, socket) do
    state = socket.assigns.channel_state
    
    case BeliefConsensus.get_consensus(state.vsm_level) do
      {:ok, consensus} ->
        {:reply, {:ok, format_consensus(consensus)}, socket}
      error ->
        {:reply, {:error, %{reason: inspect(error)}}, socket}
    end
  end
  
  @impl true
  def handle_in("subscribe_level", %{"level" => level}, socket) do
    state = socket.assigns.channel_state
    vsm_level = String.to_atom(level)
    
    # Add to subscriptions
    new_subscriptions = MapSet.put(state.subscriptions, vsm_level)
    new_state = %{state | subscriptions: new_subscriptions}
    
    socket = assign(socket, :channel_state, new_state)
    
    {:reply, :ok, socket}
  end
  
  @impl true
  def handle_in("get_metrics", _params, socket) do
    state = socket.assigns.channel_state
    
    metrics = %{
      node_metrics: get_node_metrics(state),
      consensus_metrics: get_consensus_metrics(state.vsm_level),
      sync_metrics: DeltaSync.get_metrics(state.vsm_level)
    }
    
    {:reply, {:ok, metrics}, socket}
  end
  
  # Handle outgoing messages
  
  @impl true
  def handle_info(:send_initial_state, socket) do
    state = socket.assigns.channel_state
    
    # Get current consensus
    {:ok, consensus} = BeliefConsensus.get_consensus(state.vsm_level)
    
    # Get metrics
    metrics = BeliefConsensus.get_metrics(state.vsm_level)
    
    # Get Byzantine nodes
    byzantine_nodes = ByzantineDetector.get_byzantine_nodes()
    
    push(socket, "initial_state", %{
      consensus: format_consensus(consensus),
      metrics: metrics,
      byzantine_nodes: byzantine_nodes,
      node_count: get_active_node_count(),
      your_reputation: state.reputation
    })
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(:update_consensus, socket) do
    state = socket.assigns.channel_state
    
    # Get consensus for all subscribed levels
    updates = Enum.map(state.subscriptions, fn level ->
      case BeliefConsensus.get_consensus(level) do
        {:ok, consensus} -> {level, format_consensus(consensus)}
        _ -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    |> Map.new()
    
    # Push updates
    push(socket, "consensus_update", %{
      levels: updates,
      timestamp: DateTime.utc_now()
    })
    
    # Schedule next update
    timer_ref = schedule_consensus_update()
    new_state = %{state | consensus_timer: timer_ref}
    socket = assign(socket, :channel_state, new_state)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, event}, socket) do
    handle_info({:event, event.type, event.data}, socket)
  end
  
  @impl true
  def handle_info({:event, :belief_consensus_update, data}, socket) do
    state = socket.assigns.channel_state
    
    # Check if update is for a subscribed level
    if MapSet.member?(state.subscriptions, data.level) do
      push(socket, "belief_update", %{
        level: data.level,
        belief: format_belief(data.belief),
        consensus_change: data.consensus_change
      })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event, :byzantine_node_detected, data}, socket) do
    state = socket.assigns.channel_state
    
    # Check if it's us!
    if data.node_id == state.node_id do
      Logger.error("🚨 We've been marked as Byzantine! #{inspect(data.patterns)}")
      
      # Update our reputation
      new_state = %{state | reputation: 0.1}
      socket = assign(socket, :channel_state, new_state)
      
      push(socket, "byzantine_self", %{
        patterns: data.patterns,
        score: data.score
      })
    else
      # Notify about other Byzantine nodes
      push(socket, "byzantine_detected", %{
        node_id: data.node_id,
        patterns: data.patterns,
        score: data.score
      })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event, :algedonic_pain, pain_signal}, socket) do
    state = socket.assigns.channel_state
    
    if state.algedonic_enabled do
      # Emergency broadcast
      push(socket, "algedonic_pain", %{
        signal: pain_signal,
        level: pain_signal.level,
        source: pain_signal.source,
        urgency: pain_signal.urgency || 1.0
      })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:event, :algedonic_pleasure, pleasure_signal}, socket) do
    state = socket.assigns.channel_state
    
    if state.algedonic_enabled do
      push(socket, "algedonic_pleasure", %{
        signal: pleasure_signal,
        level: pleasure_signal.level,
        source: pleasure_signal.source
      })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def terminate(_reason, socket) do
    state = socket.assigns[:channel_state]
    
    if state && state.consensus_timer do
      Process.cancel_timer(state.consensus_timer)
    end
    
    :ok
  end
  
  # Private functions
  
  defp authorized?(payload) do
    # In production, implement proper authorization
    # For now, check for valid token
    Map.has_key?(payload, "token")
  end
  
  defp generate_node_id(socket) do
    # Generate unique node ID for this connection
    transport_pid = socket.transport_pid
    "ws_node_#{:erlang.phash2(transport_pid)}_#{System.unique_integer([:positive])}"
  end
  
  defp rate_limit_ok?(state) do
    case state.last_vote_time do
      nil -> true
      last_time ->
        # Check if enough time has passed
        diff = DateTime.diff(DateTime.utc_now(), last_time, :millisecond)
        
        # Allow burst of 10, then limit to configured rate
        if state.vote_count < 10 do
          true
        else
          diff > (60_000 / @max_beliefs_per_min)
        end
    end
  end
  
  defp handle_algedonic_belief(content, urgency, params, state) do
    Logger.warning("⚡ Algedonic bypass activated for belief: #{inspect(content)}")
    
    # Report to S2 coordination immediately
    Coordination.report_conflict(:algedonic_belief, state.node_id, content)
    
    # Create high-priority belief
    metadata = %{
      source: state.node_id,
      weight: 1.0,  # Maximum weight
      confidence: urgency,
      evidence: Map.get(params, "evidence", []),
      algedonic: true
    }
    
    # Bypass normal channels
    BeliefConsensus.propose_belief(state.vsm_level, content, metadata)
  end
  
  defp handle_normal_belief(content, params, state) do
    metadata = %{
      source: state.node_id,
      weight: Map.get(params, "weight", 0.5) * state.reputation,
      confidence: Map.get(params, "confidence", 0.7),
      evidence: Map.get(params, "evidence", [])
    }
    
    BeliefConsensus.propose_belief(state.vsm_level, content, metadata)
  end
  
  defp format_consensus(consensus) do
    %{
      beliefs: Enum.map(consensus.beliefs, &format_belief/1),
      strength: consensus.strength,
      timestamp: consensus.timestamp,
      participant_count: get_participant_count(consensus)
    }
  end
  
  defp format_belief(belief) do
    %{
      id: belief.id,
      content: belief.content,
      weight: belief.weight,
      confidence: belief.confidence,
      source: belief.source,
      timestamp: belief.timestamp,
      ttl_remaining: calculate_ttl_remaining(belief),
      validation_status: belief.validation_status
    }
  end
  
  defp calculate_ttl_remaining(belief) do
    if belief.timestamp && belief.ttl do
      elapsed = DateTime.diff(DateTime.utc_now(), belief.timestamp, :millisecond)
      max(0, belief.ttl - elapsed)
    else
      0
    end
  end
  
  defp get_participant_count(consensus) do
    # In production, this would track actual participants
    consensus.beliefs
    |> Enum.map(& &1.source)
    |> Enum.uniq()
    |> length()
  end
  
  defp get_node_metrics(state) do
    %{
      node_id: state.node_id,
      reputation: state.reputation,
      vote_count: state.vote_count,
      uptime: calculate_uptime(state),
      is_byzantine: ByzantineDetector.is_byzantine?(state.node_id)
    }
  end
  
  defp get_consensus_metrics(vsm_level) do
    BeliefConsensus.get_metrics(vsm_level)
  end
  
  defp get_active_node_count do
    # In production, track active WebSocket connections
    # For now, return Node.list() count + 1
    length(Node.list()) + 1
  end
  
  defp calculate_uptime(_state) do
    # In production, track connection time
    0
  end
  
  defp schedule_consensus_update do
    Process.send_after(self(), :update_consensus, @consensus_update_interval)
  end
end