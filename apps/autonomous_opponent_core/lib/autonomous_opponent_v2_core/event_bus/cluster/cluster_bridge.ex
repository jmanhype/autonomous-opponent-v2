defmodule AutonomousOpponentV2Core.EventBus.Cluster.ClusterBridge do
  @moduledoc """
  EventBus Cluster Bridge - The Nervous System of Distributed VSM
  
  This module implements the distributed nervous system for the Autonomous Opponent,
  enabling cross-node event propagation while maintaining cybernetic principles:
  
  1. **Variety Engineering**: Manages channel capacity to prevent overload
  2. **Algedonic Bypass**: Zero-latency pain signal propagation
  3. **Recursive Viability**: Each node maintains autonomy while contributing to the whole
  4. **Homeostatic Balance**: Self-regulating event flow based on system health
  
  ## Architecture
  
  The ClusterBridge acts as the synaptic junction between VSM nodes:
  - Local events are selectively forwarded based on variety constraints
  - Remote events are received and injected into local EventBus
  - Circuit breakers prevent cascade failures
  - Partition detection maintains split-brain awareness
  
  ## Cybernetic Principles
  
  Following Stafford Beer's VSM model:
  - S1-S5 channels have distinct variety quotas
  - Algedonic signals bypass all filters
  - Recursive structure enables fractal scaling
  - Variety absorption through semantic compression
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  # Use standard telemetry module
  alias AutonomousOpponentV2Core.Core.HybridLogicalClock, as: HLC
  alias AutonomousOpponentV2Core.Core.CircuitBreaker
  alias AutonomousOpponentV2Core.EventBus.Cluster.{VarietyManager, PartitionDetector, AlgedonicBroadcast}
  
  @type node_state :: :connected | :disconnected | :partitioned | :suspended
  @type event_class :: :algedonic | :s1_operational | :s2_coordination | 
                       :s3_control | :s4_intelligence | :s5_policy | :general
  
  defstruct [
    :node_id,
    :peers,
    :circuit_breakers,
    :variety_manager,
    :partition_detector,
    :event_buffer,
    :stats,
    :config
  ]
  
  # Cybernetic event classification
  @algedonic_events [
    :emergency_algedonic,
    :algedonic_pain,
    :algedonic_pleasure,
    :algedonic_intervention,
    :system_panic,
    :viability_threat
  ]
  
  @s5_policy_events [
    :policy_update,
    :governance_decision,
    :strategic_directive,
    :system_reconfiguration
  ]
  
  @s4_intelligence_events [
    :pattern_detected,
    :environment_scan,
    :threat_assessment,
    :opportunity_identified
  ]
  
  @s3_control_events [
    :resource_allocation,
    :optimization_directive,
    :performance_adjustment,
    :control_override
  ]
  
  @s2_coordination_events [
    :anti_oscillation,
    :synchronization,
    :conflict_resolution,
    :coordination_request
  ]
  
  @s1_operational_events [
    :task_execution,
    :operational_metric,
    :status_update,
    :routine_activity
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Get current cluster topology and health
  """
  def topology(server \\ __MODULE__) do
    GenServer.call(server, :get_topology)
  end
  
  @doc """
  Manually trigger partition detection
  """
  def check_partitions(server \\ __MODULE__) do
    GenServer.call(server, :check_partitions)
  end
  
  @doc """
  Get variety flow statistics
  """
  def variety_stats(server \\ __MODULE__) do
    GenServer.call(server, :variety_stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Set up process flags for resilience
    Process.flag(:trap_exit, true)
    
    # Initialize configuration
    config = build_config(opts)
    
    # Reference existing variety manager and partition detector started by supervisor
    variety_manager = VarietyManager
    partition_detector = PartitionDetector
    
    # Subscribe to local EventBus for outbound replication
    EventBus.subscribe(:all, self(), metadata: %{cluster_bridge: true})
    
    # Set up node monitoring
    :net_kernel.monitor_nodes(true, node_type: :all)
    
    # Initialize state
    state = %__MODULE__{
      node_id: node(),
      peers: %{},
      circuit_breakers: %{},
      variety_manager: variety_manager,
      partition_detector: partition_detector,
      event_buffer: :queue.new(),
      stats: init_stats(),
      config: config
    }
    
    # Schedule periodic tasks
    schedule_peer_discovery(config.peer_discovery_interval)
    schedule_health_check(config.health_check_interval)
    schedule_telemetry_report(config.telemetry_interval)
    
    # Discover initial peers
    {:ok, discover_peers(state)}
  end
  
  @impl true
  def handle_call(:get_topology, _from, state) do
    topology = %{
      node_id: state.node_id,
      peers: Map.keys(state.peers),
      peer_states: Map.new(state.peers, fn {node, peer_state} ->
        {node, %{
          state: peer_state.state,
          latency: peer_state.latency,
          last_seen: peer_state.last_seen,
          events_sent: peer_state.events_sent,
          events_received: peer_state.events_received
        }}
      end),
      partition_status: PartitionDetector.status(state.partition_detector),
      variety_pressure: VarietyManager.pressure(state.variety_manager)
    }
    
    {:reply, topology, state}
  end
  
  @impl true
  def handle_call(:check_partitions, _from, state) do
    partition_status = PartitionDetector.check(state.partition_detector, Map.keys(state.peers))
    
    new_state = case partition_status do
      {:partitioned, partitions} ->
        handle_partition_detected(partitions, state)
      :healthy ->
        state
    end
    
    {:reply, partition_status, new_state}
  end
  
  @impl true
  def handle_call(:variety_stats, _from, state) do
    stats = VarietyManager.get_stats(state.variety_manager)
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, event}, state) do
    # Handle local event for potential replication
    case should_replicate?(event, state) do
      {true, event_class} ->
        replicate_event(event, event_class, state)
      false ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:nodeup, node, _info}, state) do
    Logger.info("VSM Cluster: Node joined - #{node}")
    
    # Initialize peer connection
    new_state = add_peer(node, state)
    
    # Trigger S3 control sync for new node
    EventBus.publish(:cluster_node_joined, %{node: node})
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:nodedown, node, _info}, state) do
    Logger.warn("VSM Cluster: Node departed - #{node}")
    
    # Handle peer disconnection
    new_state = remove_peer(node, state)
    
    # Notify S3 for resource reallocation
    EventBus.publish(:cluster_node_departed, %{node: node})
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:remote_event, event, from_node}, state) do
    # Handle incoming remote event
    case validate_remote_event(event, from_node, state) do
      {:ok, validated_event} ->
        # Update stats
        new_state = update_peer_stats(from_node, :events_received, state)
        
        # Check for loops
        if not event_loop_detected?(validated_event, state) do
          # Inject into local EventBus
          inject_remote_event(validated_event)
          
          # Update variety metrics
          VarietyManager.record_inbound(state.variety_manager, classify_event(event))
        end
        
        {:noreply, new_state}
        
      {:error, reason} ->
        Logger.warn("VSM Cluster: Rejected remote event - #{reason}")
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:peer_discovery, state) do
    # Periodic peer discovery
    new_state = discover_peers(state)
    schedule_peer_discovery(state.config.peer_discovery_interval)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    # Check circuit breakers and peer health
    new_state = check_peer_health(state)
    
    # Check for partitions
    case PartitionDetector.check(state.partition_detector, Map.keys(state.peers)) do
      {:partitioned, partitions} ->
        handle_partition_detected(partitions, new_state)
      :healthy ->
        new_state
    end
    
    schedule_health_check(state.config.health_check_interval)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:telemetry_report, state) do
    # Report variety flow metrics
    report_telemetry(state)
    schedule_telemetry_report(state.config.telemetry_interval)
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    # Handle linked process crashes
    Logger.error("VSM Cluster: Linked process crashed - #{inspect(pid)}, reason: #{inspect(reason)}")
    {:noreply, state}
  end
  
  # Private Functions
  
  defp build_config(opts) do
    %{
      # Variety quotas per VSM channel (events/second)
      variety_quotas: opts[:variety_quotas] || %{
        algedonic: :unlimited,
        s5_policy: 50,
        s4_intelligence: 100,
        s3_control: 200,
        s2_coordination: 500,
        s1_operational: 1000,
        general: 100
      },
      
      # Semantic compression settings
      semantic_compression: opts[:semantic_compression] || %{
        enabled: true,
        similarity_threshold: 0.8,
        aggregation_window: 100  # ms
      },
      
      # Circuit breaker settings
      circuit_breaker: opts[:circuit_breaker] || %{
        failure_threshold: 5,
        recovery_time: 30_000,
        half_open_calls: 3
      },
      
      # Partition detection
      quorum_size: opts[:quorum_size] || :majority,
      partition_strategy: opts[:partition_strategy] || :static_quorum,
      partition_check_interval: opts[:partition_check_interval] || 5_000,
      
      # Discovery and health
      peer_discovery_interval: opts[:peer_discovery_interval] || 30_000,
      health_check_interval: opts[:health_check_interval] || 10_000,
      telemetry_interval: opts[:telemetry_interval] || 60_000,
      
      # Event settings
      event_ttl: opts[:event_ttl] || 300_000,  # 5 minutes
      max_hops: opts[:max_hops] || 3
    }
  end
  
  defp init_stats do
    %{
      events_sent: 0,
      events_received: 0,
      events_dropped: 0,
      variety_violations: 0,
      circuit_breaks: 0,
      partitions_detected: 0,
      start_time: System.monotonic_time(:millisecond)
    }
  end
  
  defp should_replicate?(event, state) do
    # Don't replicate cluster bridge events to avoid loops
    if event.metadata[:cluster_bridge] do
      false
    else
      event_class = classify_event(event)
      
      # Always replicate algedonic signals
      if event_class == :algedonic do
        {true, event_class}
      else
        # Check variety constraints
        case VarietyManager.check_outbound(state.variety_manager, event_class) do
          :allowed ->
            {true, event_class}
          :throttled ->
            # Apply semantic compression
            if state.config.semantic_compression.enabled do
              case VarietyManager.compress(state.variety_manager, event, event_class) do
                {:compressed, _compressed_event} ->
                  {true, event_class}
                :dropped ->
                  false
              end
            else
              false
            end
        end
      end
    end
  end
  
  defp classify_event(%{event_name: name}) do
    cond do
      name in @algedonic_events -> :algedonic
      name in @s5_policy_events -> :s5_policy
      name in @s4_intelligence_events -> :s4_intelligence
      name in @s3_control_events -> :s3_control
      name in @s2_coordination_events -> :s2_coordination
      name in @s1_operational_events -> :s1_operational
      true -> :general
    end
  end
  
  defp replicate_event(event, event_class, state) do
    # Add replication metadata
    replicated_event = prepare_for_replication(event, state)
    
    # Get active peers
    active_peers = get_active_peers(state)
    
    # Replicate based on event class
    case event_class do
      :algedonic ->
        # Broadcast to all peers immediately
        broadcast_algedonic(replicated_event, active_peers, state)
        
      _ ->
        # Normal replication with circuit breakers
        replicate_with_circuit_breakers(replicated_event, active_peers, state)
    end
    
    # Update stats
    new_stats = Map.update!(state.stats, :events_sent, &(&1 + length(active_peers)))
    {:noreply, %{state | stats: new_stats}}
  end
  
  defp prepare_for_replication(event, state) do
    %{event |
      cluster_metadata: %{
        source_node: state.node_id,
        hop_count: 0,
        max_hops: state.config.max_hops,
        replicated_at: System.monotonic_time(:microsecond),
        trace_path: [state.node_id]
      }
    }
  end
  
  defp broadcast_algedonic(event, peers, state) do
    # Algedonic signals bypass all controls
    Logger.warn("VSM Cluster: Broadcasting algedonic signal - #{event.event_name}")
    
    # Use multiple communication methods for reliability
    Enum.each(peers, fn {node, _peer_state} ->
      # Primary path
      send({ClusterBridge, node}, {:remote_event, event, state.node_id})
      
      # Backup path via direct RPC
      Task.start(fn ->
        :rpc.cast(node, EventBus, :publish, [event.event_name, event.data])
      end)
    end)
    
    # Record algedonic broadcast
    :telemetry.execute(
      [:vsm, :cluster, :algedonic_broadcast],
      %{count: map_size(peers)},
      %{event: event.event_name}
    )
  end
  
  defp replicate_with_circuit_breakers(event, peers, state) do
    Enum.reduce(peers, state, fn {node, _peer_state}, acc_state ->
      circuit_breaker = get_circuit_breaker(node, acc_state)
      
      case CircuitBreaker.call(circuit_breaker, fn ->
        send({ClusterBridge, node}, {:remote_event, event, acc_state.node_id})
        :ok
      end) do
        {:ok, :ok} ->
          update_peer_stats(node, :events_sent, acc_state)
          
        {:error, :circuit_open} ->
          Logger.debug("VSM Cluster: Circuit open for node #{node}")
          Map.update!(acc_state, :stats, fn stats ->
            Map.update!(stats, :circuit_breaks, &(&1 + 1))
          end)
          
        {:error, reason} ->
          Logger.warn("VSM Cluster: Failed to replicate to #{node} - #{inspect(reason)}")
          acc_state
      end
    end)
  end
  
  defp validate_remote_event(event, from_node, state) do
    with :ok <- validate_event_structure(event),
         :ok <- validate_hop_count(event),
         :ok <- validate_ttl(event),
         {:ok, _} <- validate_hlc_timestamp(event) do
      {:ok, event}
    else
      error -> error
    end
  end
  
  defp validate_event_structure(event) do
    required_fields = [:event_name, :data, :timestamp, :cluster_metadata]
    
    if Enum.all?(required_fields, &Map.has_key?(event, &1)) do
      :ok
    else
      {:error, :invalid_structure}
    end
  end
  
  defp validate_hop_count(%{cluster_metadata: %{hop_count: hops, max_hops: max}}) do
    if hops < max do
      :ok
    else
      {:error, :max_hops_exceeded}
    end
  end
  
  defp validate_ttl(%{cluster_metadata: %{replicated_at: replicated_at}} = event) do
    age = System.monotonic_time(:microsecond) - replicated_at
    ttl = event[:ttl] || 300_000_000  # 5 minutes in microseconds
    
    if age < ttl do
      :ok
    else
      {:error, :event_expired}
    end
  end
  
  defp validate_hlc_timestamp(%{timestamp: timestamp}) do
    case HLC.validate_timestamp(timestamp) do
      :ok -> {:ok, timestamp}
      error -> error
    end
  end
  
  defp event_loop_detected?(%{cluster_metadata: %{trace_path: path}} = event, state) do
    state.node_id in path
  end
  
  defp inject_remote_event(event) do
    # Remove cluster metadata to prevent re-replication
    local_event = Map.delete(event, :cluster_metadata)
    |> Map.put(:metadata, Map.put(event[:metadata] || %{}, :cluster_bridge, true))
    
    # Publish to local EventBus
    EventBus.publish(event.event_name, event.data, local_event.metadata)
  end
  
  defp discover_peers(state) do
    # Use multiple discovery methods
    discovered_nodes = Node.list(:known)
    
    # Add newly discovered peers
    Enum.reduce(discovered_nodes, state, fn node, acc_state ->
      if not Map.has_key?(acc_state.peers, node) do
        add_peer(node, acc_state)
      else
        acc_state
      end
    end)
  end
  
  defp add_peer(node, state) do
    peer_state = %{
      node: node,
      state: :connected,
      latency: nil,
      last_seen: System.monotonic_time(:millisecond),
      events_sent: 0,
      events_received: 0,
      circuit_breaker: start_circuit_breaker(node, state.config.circuit_breaker)
    }
    
    new_peers = Map.put(state.peers, node, peer_state)
    
    # Notify partition detector
    PartitionDetector.node_added(state.partition_detector, node)
    
    %{state | peers: new_peers}
  end
  
  defp remove_peer(node, state) do
    new_peers = Map.delete(state.peers, node)
    
    # Clean up circuit breaker
    if breaker = get_in(state.peers, [node, :circuit_breaker]) do
      Process.exit(breaker, :shutdown)
    end
    
    # Notify partition detector
    PartitionDetector.node_removed(state.partition_detector, node)
    
    %{state | peers: new_peers}
  end
  
  defp get_active_peers(state) do
    Map.filter(state.peers, fn {_node, peer_state} ->
      peer_state.state == :connected
    end)
  end
  
  defp update_peer_stats(node, stat, state) do
    case Map.get(state.peers, node) do
      nil ->
        state
      peer_state ->
        updated_peer = Map.update!(peer_state, stat, &(&1 + 1))
        |> Map.put(:last_seen, System.monotonic_time(:millisecond))
        
        %{state | peers: Map.put(state.peers, node, updated_peer)}
    end
  end
  
  defp get_circuit_breaker(node, state) do
    get_in(state.peers, [node, :circuit_breaker])
  end
  
  defp start_circuit_breaker(node, config) do
    {:ok, breaker} = CircuitBreaker.start_link(
      name: :"cluster_breaker_#{node}",
      failure_threshold: config.failure_threshold,
      recovery_time_ms: config.recovery_time,
      half_open_calls: config.half_open_calls
    )
    breaker
  end
  
  defp check_peer_health(state) do
    now = System.monotonic_time(:millisecond)
    timeout = 60_000  # 1 minute
    
    Enum.reduce(state.peers, state, fn {node, peer_state}, acc_state ->
      if now - peer_state.last_seen > timeout do
        Logger.warn("VSM Cluster: Peer #{node} appears unhealthy")
        
        updated_peer = %{peer_state | state: :disconnected}
        %{acc_state | peers: Map.put(acc_state.peers, node, updated_peer)}
      else
        acc_state
      end
    end)
  end
  
  defp handle_partition_detected(partitions, state) do
    Logger.error("VSM Cluster: Network partition detected! Partitions: #{inspect(partitions)}")
    
    # Update stats
    new_stats = Map.update!(state.stats, :partitions_detected, &(&1 + 1))
    
    # Notify VSM S5 (Policy) of partition
    EventBus.publish(:network_partition_detected, %{
      partitions: partitions,
      node: state.node_id,
      timestamp: DateTime.utc_now()
    })
    
    # Enter degraded mode for cross-partition peers
    updated_peers = Enum.reduce(state.peers, %{}, fn {node, peer_state}, acc ->
      if partition_contains_node?(partitions, state.node_id, node) do
        Map.put(acc, node, peer_state)
      else
        Map.put(acc, node, %{peer_state | state: :partitioned})
      end
    end)
    
    %{state | peers: updated_peers, stats: new_stats}
  end
  
  defp partition_contains_node?(partitions, node1, node2) do
    Enum.any?(partitions, fn partition ->
      node1 in partition and node2 in partition
    end)
  end
  
  defp report_telemetry(state) do
    uptime = System.monotonic_time(:millisecond) - state.stats.start_time
    
    :telemetry.execute(
      [:vsm, :cluster, :bridge],
      %{
        events_sent: state.stats.events_sent,
        events_received: state.stats.events_received,
        events_dropped: state.stats.events_dropped,
        variety_violations: state.stats.variety_violations,
        circuit_breaks: state.stats.circuit_breaks,
        partitions_detected: state.stats.partitions_detected,
        active_peers: count_active_peers(state),
        uptime_ms: uptime
      },
      %{
        node: state.node_id,
        variety_pressure: VarietyManager.pressure(state.variety_manager)
      }
    )
  end
  
  defp count_active_peers(state) do
    Enum.count(state.peers, fn {_node, peer_state} ->
      peer_state.state == :connected
    end)
  end
  
  defp schedule_peer_discovery(interval) do
    Process.send_after(self(), :peer_discovery, interval)
  end
  
  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end
  
  defp schedule_telemetry_report(interval) do
    Process.send_after(self(), :telemetry_report, interval)
  end
end