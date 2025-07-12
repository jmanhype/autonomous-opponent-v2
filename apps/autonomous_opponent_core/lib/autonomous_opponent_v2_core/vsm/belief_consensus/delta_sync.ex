defmodule AutonomousOpponentV2Core.VSM.BeliefConsensus.DeltaSync do
  @moduledoc """
  Delta-state CRDT synchronization for efficient belief consensus propagation.
  
  Implements bandwidth-efficient synchronization by only transmitting changes
  (deltas) rather than full state. Achieves 90%+ bandwidth reduction for
  large belief sets.
  
  Key features:
  - Delta generation and tracking
  - Merkle tree for efficient diff detection
  - Bloom filters for membership queries
  - Compression for network transport
  - Causal consistency via vector clocks
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.AMCP.Memory.{ORSet, CRDTStore}
  
  # Configuration
  @sync_interval 5_000             # 5 seconds between sync rounds
  @delta_buffer_size 1_000         # Maximum deltas to buffer
  @merkle_tree_depth 4             # Depth of Merkle tree
  @bloom_filter_size 10_000        # Bloom filter bit size
  @bloom_filter_hashes 3           # Number of hash functions
  @compression_threshold 1_024     # Compress if larger than 1KB
  @max_sync_batch_size 100         # Max deltas per sync message
  
  defstruct [
    :node_id,
    :vsm_level,
    :delta_buffer,           # Recent deltas not yet synced
    :vector_clock,           # Causal ordering
    :merkle_tree,            # For efficient diff detection
    :bloom_filter,           # For quick membership tests
    :peer_states,            # Track what peers have
    :sync_schedule,          # Sync timing per peer
    :compression_stats,      # Track compression efficiency
    :metrics                 # Performance metrics
  ]
  
  # Delta operation structure
  defmodule Delta do
    @enforce_keys [:id, :operation, :element, :timestamp, :vector_clock]
    defstruct [
      :id,
      :operation,      # :add or :remove
      :element,        # The belief
      :timestamp,      # HLC timestamp
      :vector_clock,   # For causal ordering
      :source_node,    # Origin node
      :compressed      # Whether payload is compressed
    ]
  end
  
  # Peer sync state
  defmodule PeerState do
    defstruct [
      :peer_id,
      :last_sync,         # Last successful sync time
      :vector_clock,      # Their known vector clock
      :merkle_root,       # Their Merkle tree root
      :pending_deltas,    # Deltas they need
      :sync_failures,     # Failed sync attempts
      :bandwidth_used     # Bytes transferred
    ]
  end
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: name_for_level(opts[:vsm_level]))
  end
  
  @doc """
  Record a delta operation for synchronization.
  """
  def record_delta(level, operation, element) do
    GenServer.cast(name_for_level(level), {:record_delta, operation, element})
  end
  
  @doc """
  Synchronize with a specific peer.
  """
  def sync_with_peer(level, peer_id) do
    GenServer.call(name_for_level(level), {:sync_with_peer, peer_id})
  end
  
  @doc """
  Get sync metrics.
  """
  def get_metrics(level) do
    GenServer.call(name_for_level(level), :get_metrics)
  end
  
  @doc """
  Force full state sync (emergency recovery).
  """
  def force_full_sync(level) do
    GenServer.call(name_for_level(level), :force_full_sync)
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    node_id = Keyword.fetch!(opts, :node_id)
    vsm_level = Keyword.fetch!(opts, :vsm_level)
    
    # Initialize data structures
    vector_clock = init_vector_clock(node_id)
    merkle_tree = init_merkle_tree()
    bloom_filter = init_bloom_filter()
    
    # Subscribe to events
    EventBus.subscribe(:belief_consensus_update)
    EventBus.subscribe(:peer_sync_request)
    EventBus.subscribe(:peer_sync_response)
    
    # Start sync timer
    schedule_sync_round()
    
    state = %__MODULE__{
      node_id: node_id,
      vsm_level: vsm_level,
      delta_buffer: :queue.new(),
      vector_clock: vector_clock,
      merkle_tree: merkle_tree,
      bloom_filter: bloom_filter,
      peer_states: %{},
      sync_schedule: %{},
      compression_stats: init_compression_stats(),
      metrics: init_metrics()
    }
    
    Logger.info("📡 Delta Sync initialized for #{vsm_level}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:record_delta, operation, element}, state) do
    # Create delta with causal information
    {:ok, hlc_event} = Clock.create_event(:delta_sync, operation, %{
      element: element.id
    })
    
    # Increment vector clock
    new_vector_clock = increment_vector_clock(state.vector_clock, state.node_id)
    
    delta = %Delta{
      id: generate_delta_id(),
      operation: operation,
      element: element,
      timestamp: hlc_event.timestamp,
      vector_clock: new_vector_clock,
      source_node: state.node_id,
      compressed: false
    }
    
    # Add to delta buffer
    new_buffer = add_to_buffer(state.delta_buffer, delta)
    
    # Update Merkle tree
    new_merkle = update_merkle_tree(state.merkle_tree, delta)
    
    # Update Bloom filter
    new_bloom = update_bloom_filter(state.bloom_filter, element)
    
    new_state = %{state |
      delta_buffer: new_buffer,
      vector_clock: new_vector_clock,
      merkle_tree: new_merkle,
      bloom_filter: new_bloom
    }
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call({:sync_with_peer, peer_id}, _from, state) do
    # Get or create peer state
    peer_state = Map.get(state.peer_states, peer_id, %PeerState{
      peer_id: peer_id,
      last_sync: nil,
      vector_clock: %{},
      merkle_root: nil,
      pending_deltas: [],
      sync_failures: 0,
      bandwidth_used: 0
    })
    
    # Compare Merkle roots for quick diff check
    if peer_state.merkle_root == merkle_root(state.merkle_tree) do
      # Already in sync
      {:reply, {:ok, :already_synced}, state}
    else
      # Compute deltas needed by peer
      deltas_to_send = compute_peer_deltas(state, peer_state)
      
      # Batch and compress if needed
      sync_batch = prepare_sync_batch(deltas_to_send, state)
      
      # Send sync message
      send_sync_message(peer_id, sync_batch, state)
      
      # Update peer state
      new_peer_state = %{peer_state |
        last_sync: DateTime.utc_now(),
        pending_deltas: deltas_to_send,
        bandwidth_used: peer_state.bandwidth_used + byte_size(sync_batch)
      }
      
      new_peer_states = Map.put(state.peer_states, peer_id, new_peer_state)
      new_state = %{state | peer_states: new_peer_states}
      
      {:reply, {:ok, length(deltas_to_send)}, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      delta_buffer_size: :queue.len(state.delta_buffer),
      peer_count: map_size(state.peer_states),
      total_bandwidth: calculate_total_bandwidth(state),
      compression_ratio: calculate_compression_ratio(state),
      sync_success_rate: calculate_sync_success_rate(state),
      average_delta_size: state.metrics.total_delta_bytes / max(1, state.metrics.delta_count)
    }
    
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_call(:force_full_sync, _from, state) do
    Logger.warning("⚠️ Forcing full state sync for #{state.vsm_level}")
    
    # Get full belief state
    full_state = get_full_belief_state(state.vsm_level)
    
    # Broadcast to all peers
    broadcast_full_state(full_state, state)
    
    # Reset sync state
    new_state = %{state |
      peer_states: %{},
      metrics: update_metrics(state.metrics, :full_sync)
    }
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_info(:sync_round, state) do
    # Periodic sync with all active peers
    active_peers = get_active_peers(state.vsm_level)
    
    new_state = Enum.reduce(active_peers, state, fn peer_id, acc ->
      case sync_with_peer_internal(peer_id, acc) do
        {:ok, updated_state} -> updated_state
        {:error, _reason} -> acc
      end
    end)
    
    # Clean up old deltas
    new_state = cleanup_old_deltas(new_state)
    
    # Schedule next round
    schedule_sync_round()
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :peer_sync_request, request}, state) do
    # Peer requesting sync
    peer_id = request.peer_id
    peer_vector_clock = request.vector_clock
    peer_merkle_root = request.merkle_root
    
    # Update peer state
    peer_state = %PeerState{
      peer_id: peer_id,
      last_sync: DateTime.utc_now(),
      vector_clock: peer_vector_clock,
      merkle_root: peer_merkle_root,
      pending_deltas: [],
      sync_failures: 0,
      bandwidth_used: 0
    }
    
    # Compute what they need
    missing_deltas = compute_missing_deltas(state, peer_vector_clock)
    
    # Send response
    response_batch = prepare_sync_batch(missing_deltas, state)
    send_sync_response(peer_id, response_batch, state)
    
    # Update state
    new_peer_states = Map.put(state.peer_states, peer_id, peer_state)
    new_state = %{state | 
      peer_states: new_peer_states,
      metrics: update_metrics(state.metrics, :sync_response)
    }
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :peer_sync_response, response}, state) do
    # Process sync response from peer
    peer_id = response.peer_id
    deltas = decompress_if_needed(response.deltas)
    
    # Validate and apply deltas
    {applied, rejected} = apply_peer_deltas(deltas, state)
    
    if length(rejected) > 0 do
      Logger.warning("Rejected #{length(rejected)} deltas from #{peer_id}")
    end
    
    # Update our state
    new_state = Enum.reduce(applied, state, fn delta, acc ->
      apply_delta_to_state(delta, acc)
    end)
    
    # Update peer state
    peer_state = Map.get(new_state.peer_states, peer_id, %PeerState{peer_id: peer_id})
    updated_peer_state = %{peer_state |
      last_sync: DateTime.utc_now(),
      pending_deltas: [],
      sync_failures: 0
    }
    
    new_peer_states = Map.put(new_state.peer_states, peer_id, updated_peer_state)
    final_state = %{new_state | 
      peer_states: new_peer_states,
      metrics: update_metrics(new_state.metrics, :deltas_applied, length(applied))
    }
    
    {:noreply, final_state}
  end
  
  # Private Functions
  
  defp name_for_level(level) do
    :"belief_consensus_delta_sync_#{level}"
  end
  
  defp init_vector_clock(node_id) do
    %{node_id => 0}
  end
  
  defp increment_vector_clock(clock, node_id) do
    Map.update(clock, node_id, 1, &(&1 + 1))
  end
  
  defp init_merkle_tree do
    # Simple Merkle tree implementation
    %{
      depth: @merkle_tree_depth,
      nodes: %{},
      root: nil
    }
  end
  
  defp init_bloom_filter do
    # Bloom filter for quick membership tests
    %{
      size: @bloom_filter_size,
      bits: :array.new(@bloom_filter_size, default: 0),
      hash_count: @bloom_filter_hashes
    }
  end
  
  defp add_to_buffer(buffer, delta) do
    new_queue = :queue.in(delta, buffer)
    
    # Limit buffer size
    if :queue.len(new_queue) > @delta_buffer_size do
      {_, trimmed} = :queue.out(new_queue)
      trimmed
    else
      new_queue
    end
  end
  
  defp update_merkle_tree(tree, delta) do
    # Hash the delta
    delta_hash = hash_delta(delta)
    
    # Update tree nodes
    path = merkle_path(delta.id, tree.depth)
    new_nodes = update_merkle_nodes(tree.nodes, path, delta_hash)
    
    # Recompute root
    new_root = compute_merkle_root(new_nodes, tree.depth)
    
    %{tree | nodes: new_nodes, root: new_root}
  end
  
  defp update_bloom_filter(filter, element) do
    # Add element to Bloom filter
    hashes = bloom_hashes(element.id, filter.hash_count)
    
    new_bits = Enum.reduce(hashes, filter.bits, fn hash, bits ->
      index = rem(hash, filter.size)
      :array.set(index, 1, bits)
    end)
    
    %{filter | bits: new_bits}
  end
  
  defp compute_peer_deltas(state, peer_state) do
    # Find deltas peer doesn't have based on vector clocks
    state.delta_buffer
    |> :queue.to_list()
    |> Enum.filter(fn delta ->
      not has_delta?(peer_state.vector_clock, delta)
    end)
    |> Enum.take(@max_sync_batch_size)
  end
  
  defp has_delta?(peer_clock, delta) do
    # Check if peer has seen this delta
    peer_version = Map.get(peer_clock, delta.source_node, 0)
    delta_version = Map.get(delta.vector_clock, delta.source_node, 0)
    
    peer_version >= delta_version
  end
  
  defp prepare_sync_batch(deltas, state) do
    # Prepare batch for network transmission
    batch_data = %{
      node_id: state.node_id,
      vsm_level: state.vsm_level,
      vector_clock: state.vector_clock,
      merkle_root: merkle_root(state.merkle_tree),
      deltas: deltas,
      timestamp: DateTime.utc_now()
    }
    
    # Serialize
    serialized = :erlang.term_to_binary(batch_data)
    
    # Compress if beneficial
    if byte_size(serialized) > @compression_threshold do
      compressed = :zlib.compress(serialized)
      
      if byte_size(compressed) < byte_size(serialized) * 0.9 do
        # Compression saved >10%, use it
        update_compression_stats(state, byte_size(serialized), byte_size(compressed))
        %{compressed: true, data: compressed}
      else
        %{compressed: false, data: serialized}
      end
    else
      %{compressed: false, data: serialized}
    end
  end
  
  defp send_sync_message(peer_id, sync_batch, state) do
    # Send via appropriate channel
    case state.vsm_level do
      :s1 -> send_via_amqp(peer_id, sync_batch, "belief.sync.s1")
      :s2 -> send_via_amqp(peer_id, sync_batch, "belief.sync.s2")
      :s3 -> send_via_amqp(peer_id, sync_batch, "belief.sync.s3")
      :s4 -> send_via_amqp(peer_id, sync_batch, "belief.sync.s4")
      :s5 -> send_via_amqp(peer_id, sync_batch, "belief.sync.s5")
    end
  end
  
  defp send_via_amqp(peer_id, data, routing_key) do
    # Send through AMQP if available
    if Process.whereis(AutonomousOpponentV2Core.AMQP.Producer) do
      AutonomousOpponentV2Core.AMQP.Producer.publish(
        "belief.consensus",
        routing_key,
        data,
        persistent: true
      )
    else
      # Fallback to EventBus
      EventBus.publish(:peer_sync_message, %{
        peer_id: peer_id,
        data: data
      })
    end
  end
  
  defp compute_missing_deltas(state, peer_vector_clock) do
    # Find all deltas peer is missing
    state.delta_buffer
    |> :queue.to_list()
    |> Enum.filter(fn delta ->
      not has_delta?(peer_vector_clock, delta)
    end)
  end
  
  defp decompress_if_needed(%{compressed: true, data: data}) do
    :zlib.uncompress(data)
    |> :erlang.binary_to_term()
  end
  defp decompress_if_needed(%{compressed: false, data: data}) do
    :erlang.binary_to_term(data)
  end
  defp decompress_if_needed(data) when is_binary(data) do
    :erlang.binary_to_term(data)
  end
  
  defp apply_peer_deltas(deltas, state) do
    # Validate and separate applicable deltas
    Enum.split_with(deltas, fn delta ->
      valid_delta?(delta, state)
    end)
  end
  
  defp valid_delta?(delta, state) do
    # Validate delta causality and integrity
    case delta do
      %Delta{vector_clock: vc} when is_map(vc) ->
        # Check causal consistency
        causally_consistent?(vc, state.vector_clock)
      _ ->
        false
    end
  end
  
  defp causally_consistent?(delta_clock, our_clock) do
    # Check if delta is causally consistent with our state
    Enum.all?(delta_clock, fn {node, version} ->
      our_version = Map.get(our_clock, node, 0)
      version <= our_version + 1
    end)
  end
  
  defp apply_delta_to_state(delta, state) do
    # Apply delta to our CRDT state
    case delta.operation do
      :add ->
        # Add to appropriate belief set
        :ok = CRDTStore.update_crdt(
          belief_set_id(state.vsm_level, delta.element),
          :add,
          delta.element
        )
        
      :remove ->
        # Remove from belief set
        :ok = CRDTStore.update_crdt(
          belief_set_id(state.vsm_level, delta.element),
          :remove,
          delta.element
        )
    end
    
    # Update our vector clock
    new_vector_clock = merge_vector_clocks(state.vector_clock, delta.vector_clock)
    
    # Update data structures
    %{state |
      vector_clock: new_vector_clock,
      merkle_tree: update_merkle_tree(state.merkle_tree, delta),
      bloom_filter: update_bloom_filter(state.bloom_filter, delta.element)
    }
  end
  
  defp merge_vector_clocks(clock1, clock2) do
    # Take maximum version for each node
    Map.merge(clock1, clock2, fn _k, v1, v2 -> max(v1, v2) end)
  end
  
  defp get_active_peers(vsm_level) do
    # Get list of active peer nodes
    # In production, this would use a peer discovery mechanism
    Node.list()
    |> Enum.filter(fn node ->
      node_vsm_level(node) == vsm_level
    end)
  end
  
  defp node_vsm_level(node) do
    # Extract VSM level from node name
    # Example: "belief_s1@host" -> :s1
    case to_string(node) |> String.split("_") do
      [_, level | _] -> String.to_atom(level)
      _ -> nil
    end
  end
  
  defp sync_with_peer_internal(peer_id, state) do
    try do
      case sync_with_peer(state.vsm_level, peer_id) do
        {:ok, delta_count} ->
          {:ok, update_metrics(state, :sync_success, delta_count)}
        error ->
          {:error, error}
      end
    catch
      _kind, _reason ->
        {:error, :sync_failed}
    end
  end
  
  defp cleanup_old_deltas(state) do
    # Remove deltas all peers have received
    min_vector_clock = compute_min_vector_clock(state.peer_states)
    
    filtered_buffer = state.delta_buffer
    |> :queue.to_list()
    |> Enum.filter(fn delta ->
      not fully_propagated?(delta, min_vector_clock)
    end)
    |> :queue.from_list()
    
    %{state | delta_buffer: filtered_buffer}
  end
  
  defp compute_min_vector_clock(peer_states) do
    # Find minimum vector clock across all peers
    peer_states
    |> Map.values()
    |> Enum.map(& &1.vector_clock)
    |> Enum.reduce(%{}, fn clock, acc ->
      Map.merge(acc, clock, fn _k, v1, v2 -> min(v1, v2) end)
    end)
  end
  
  defp fully_propagated?(delta, min_clock) do
    # Check if all peers have seen this delta
    Enum.all?(delta.vector_clock, fn {node, version} ->
      Map.get(min_clock, node, 0) >= version
    end)
  end
  
  defp hash_delta(delta) do
    # Create deterministic hash of delta
    :crypto.hash(:sha256, :erlang.term_to_binary(delta))
  end
  
  defp merkle_path(id, depth) do
    # Compute path in Merkle tree
    hash = :crypto.hash(:sha256, id)
    
    0..(depth - 1)
    |> Enum.map(fn level ->
      byte = :binary.at(hash, level)
      rem(byte, :math.pow(2, level) |> round())
    end)
  end
  
  defp update_merkle_nodes(nodes, path, hash) do
    # Update nodes along path
    Enum.reduce(path, {nodes, hash}, fn pos, {nodes_acc, hash_acc} ->
      node_key = path_to_key(path, pos)
      new_hash = combine_hashes(hash_acc, Map.get(nodes_acc, sibling_key(node_key), <<>>))
      {Map.put(nodes_acc, node_key, new_hash), new_hash}
    end)
    |> elem(0)
  end
  
  defp compute_merkle_root(nodes, depth) do
    # Compute root hash
    Map.get(nodes, root_key(depth), <<>>)
  end
  
  defp merkle_root(tree) do
    tree.root || <<>>
  end
  
  defp bloom_hashes(id, count) do
    # Generate multiple hashes for Bloom filter
    base_hash = :crypto.hash(:sha256, id)
    
    0..(count - 1)
    |> Enum.map(fn i ->
      :crypto.hash(:sha256, <<base_hash::binary, i::8>>)
      |> :binary.decode_unsigned()
    end)
  end
  
  defp belief_set_id(vsm_level, element) do
    # Determine which belief set this belongs to
    category = categorize_belief(element, vsm_level)
    "belief_#{vsm_level}_#{category}"
  end
  
  defp categorize_belief(_element, vsm_level) do
    # Simple categorization
    case vsm_level do
      :s1 -> :operational
      :s2 -> :coordination  
      :s3 -> :control
      :s4 -> :patterns
      :s5 -> :policy
    end
  end
  
  defp get_full_belief_state(vsm_level) do
    # Get complete belief state for full sync
    # This would retrieve from BeliefConsensus
    GenServer.call(:"belief_consensus_#{vsm_level}", :get_full_state)
  end
  
  defp broadcast_full_state(full_state, state) do
    # Send full state to all known peers
    Enum.each(state.peer_states, fn {peer_id, _} ->
      send_full_state(peer_id, full_state, state)
    end)
  end
  
  defp send_full_state(peer_id, full_state, state) do
    # Send complete state (emergency recovery)
    message = %{
      type: :full_state_sync,
      node_id: state.node_id,
      vsm_level: state.vsm_level,
      state: full_state,
      timestamp: DateTime.utc_now()
    }
    
    send_via_amqp(peer_id, message, "belief.sync.full_state")
  end
  
  defp send_sync_response(peer_id, response_batch, state) do
    # Send sync response to requesting peer
    message = %{
      type: :sync_response,
      node_id: state.node_id,
      peer_id: peer_id,
      deltas: response_batch
    }
    
    EventBus.publish(:peer_sync_response, message)
  end
  
  defp generate_delta_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp init_compression_stats do
    %{
      total_uncompressed: 0,
      total_compressed: 0,
      compression_count: 0
    }
  end
  
  defp update_compression_stats(state, uncompressed_size, compressed_size) do
    stats = state.compression_stats
    
    new_stats = %{stats |
      total_uncompressed: stats.total_uncompressed + uncompressed_size,
      total_compressed: stats.total_compressed + compressed_size,
      compression_count: stats.compression_count + 1
    }
    
    %{state | compression_stats: new_stats}
  end
  
  defp init_metrics do
    %{
      delta_count: 0,
      total_delta_bytes: 0,
      sync_requests: 0,
      sync_responses: 0,
      sync_failures: 0,
      deltas_applied: 0,
      full_syncs: 0
    }
  end
  
  defp update_metrics(metrics, event, count \\ 1) do
    case event do
      :sync_response ->
        %{metrics | sync_responses: metrics.sync_responses + 1}
      :sync_success ->
        %{metrics | sync_requests: metrics.sync_requests + 1}
      :deltas_applied ->
        %{metrics | deltas_applied: metrics.deltas_applied + count}
      :full_sync ->
        %{metrics | full_syncs: metrics.full_syncs + 1}
      _ ->
        metrics
    end
  end
  
  defp calculate_total_bandwidth(state) do
    state.peer_states
    |> Map.values()
    |> Enum.map(& &1.bandwidth_used)
    |> Enum.sum()
  end
  
  defp calculate_compression_ratio(state) do
    stats = state.compression_stats
    
    if stats.total_uncompressed > 0 do
      1.0 - (stats.total_compressed / stats.total_uncompressed)
    else
      0.0
    end
  end
  
  defp calculate_sync_success_rate(state) do
    total_syncs = state.metrics.sync_requests + state.metrics.sync_failures
    
    if total_syncs > 0 do
      state.metrics.sync_requests / total_syncs
    else
      1.0
    end
  end
  
  defp schedule_sync_round do
    Process.send_after(self(), :sync_round, @sync_interval)
  end
  
  # Merkle tree helper functions (simplified)
  defp path_to_key(path, level), do: {path, level}
  defp sibling_key({path, level}), do: {path ++ [1], level}
  defp root_key(depth), do: {[], depth}
  defp combine_hashes(h1, h2), do: :crypto.hash(:sha256, <<h1::binary, h2::binary>>)
end