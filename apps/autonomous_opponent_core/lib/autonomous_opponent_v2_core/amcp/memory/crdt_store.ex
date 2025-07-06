defmodule AutonomousOpponentV2Core.AMCP.Memory.CRDTStore do
  @moduledoc """
  Conflict-free Replicated Data Type (CRDT) memory store for aMCP.
  
  Provides distributed, eventually consistent memory for:
  - Context graphs across multiple agents
  - Belief sets that can be updated concurrently
  - Event causality chains
  - Semantic knowledge bases
  
  Implements multiple CRDT types:
  - G-Set (Grow-only Set) for immutable facts
  - PN-Counter (Positive-Negative Counter) for metrics
  - LWW-Register (Last-Writer-Wins Register) for mutable values
  - OR-Set (Observed-Remove Set) for dynamic sets
  - CRDT-Map for complex nested structures
  
  No central coordination required - all operations are commutative,
  associative, and idempotent.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.AMCP.Memory.{GSet, PNCounter, LWWRegister, ORSet, CRDTMap}
  alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge
  
  defstruct [
    :node_id,
    :crdts,
    :vector_clock,
    :sync_peers,
    :merge_queue,
    :stats
  ]
  
  @type crdt_type :: :g_set | :pn_counter | :lww_register | :or_set | :crdt_map
  @type crdt_id :: String.t()
  @type node_id :: String.t()
  
  # Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Creates a new CRDT of the specified type.
  """
  def create_crdt(crdt_id, crdt_type, initial_value \\ nil) do
    GenServer.call(__MODULE__, {:create_crdt, crdt_id, crdt_type, initial_value})
  end
  
  @doc """
  Gets the current value of a CRDT.
  """
  def get_crdt(crdt_id) do
    GenServer.call(__MODULE__, {:get_crdt, crdt_id})
  end
  
  @doc """
  Updates a CRDT with an operation.
  """
  def update_crdt(crdt_id, operation, value) do
    GenServer.call(__MODULE__, {:update_crdt, crdt_id, operation, value})
  end
  
  @doc """
  Merges remote CRDT state with local state.
  """
  def merge_remote_state(crdt_id, remote_state) do
    GenServer.call(__MODULE__, {:merge_remote_state, crdt_id, remote_state})
  end
  
  @doc """
  Lists all CRDTs in the store.
  """
  def list_crdts do
    GenServer.call(__MODULE__, :list_crdts)
  end
  
  @doc """
  Gets the current vector clock for the node.
  """
  def get_vector_clock do
    GenServer.call(__MODULE__, :get_vector_clock)
  end
  
  @doc """
  Adds a sync peer for automatic state synchronization.
  """
  def add_sync_peer(peer_node_id) do
    GenServer.call(__MODULE__, {:add_sync_peer, peer_node_id})
  end
  
  @doc """
  Removes a sync peer.
  """
  def remove_sync_peer(peer_node_id) do
    GenServer.call(__MODULE__, {:remove_sync_peer, peer_node_id})
  end
  
  @doc """
  Forces synchronization with all peers.
  """
  def sync_with_peers do
    GenServer.cast(__MODULE__, :sync_with_peers)
  end
  
  @doc """
  Gets statistics about the CRDT store.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  # Context-specific convenience functions
  
  @doc """
  Creates a belief set for agent knowledge.
  """
  def create_belief_set(agent_id) do
    crdt_id = "belief_set:#{agent_id}"
    create_crdt(crdt_id, :or_set, [])
  end
  
  @doc """
  Adds a belief to an agent's belief set.
  """
  def add_belief(agent_id, belief) do
    crdt_id = "belief_set:#{agent_id}"
    update_crdt(crdt_id, :add, belief)
  end
  
  @doc """
  Removes a belief from an agent's belief set.
  """
  def remove_belief(agent_id, belief) do
    crdt_id = "belief_set:#{agent_id}"
    update_crdt(crdt_id, :remove, belief)
  end
  
  @doc """
  Creates a context graph for semantic relationships.
  """
  def create_context_graph(context_id) do
    crdt_id = "context_graph:#{context_id}"
    create_crdt(crdt_id, :crdt_map, %{})
  end
  
  @doc """
  Adds a relationship to the context graph.
  """
  def add_context_relationship(context_id, from_concept, to_concept, relationship_type) do
    crdt_id = "context_graph:#{context_id}"
    relationship = %{
      from: from_concept,
      to: to_concept,
      type: relationship_type,
      timestamp: DateTime.utc_now()
    }
    update_crdt(crdt_id, :put, {"relationships", generate_relationship_id(), relationship})
  end
  
  @doc """
  Creates a metric counter for performance tracking.
  """
  def create_metric_counter(metric_name) do
    crdt_id = "metric:#{metric_name}"
    create_crdt(crdt_id, :pn_counter, 0)
  end
  
  @doc """
  Increments a metric counter.
  """
  def increment_metric(metric_name, amount \\ 1) do
    crdt_id = "metric:#{metric_name}"
    update_crdt(crdt_id, :increment, amount)
  end
  
  @doc """
  Decrements a metric counter.
  """
  def decrement_metric(metric_name, amount \\ 1) do
    crdt_id = "metric:#{metric_name}"
    update_crdt(crdt_id, :decrement, amount)
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, generate_node_id())
    
    # Subscribe to relevant events
    EventBus.subscribe(:amcp_context_update)
    EventBus.subscribe(:amcp_belief_change)
    EventBus.subscribe(:vsm_state_change)
    
    # Start periodic sync timer
    :timer.send_interval(30_000, :periodic_sync)
    
    state = %__MODULE__{
      node_id: node_id,
      crdts: %{},
      vector_clock: %{node_id => 0},
      sync_peers: MapSet.new(),
      merge_queue: :queue.new(),
      stats: init_stats()
    }
    
    Logger.info("CRDT Store started with node ID: #{node_id}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:create_crdt, crdt_id, crdt_type, initial_value}, _from, state) do
    case Map.has_key?(state.crdts, crdt_id) do
      true ->
        {:reply, {:error, :already_exists}, state}
        
      false ->
        case create_crdt_instance(crdt_type, initial_value, state.node_id) do
          {:ok, crdt_instance} ->
            new_crdts = Map.put(state.crdts, crdt_id, {crdt_type, crdt_instance})
            new_state = increment_vector_clock(state)
            new_state = %{new_state | crdts: new_crdts}
            
            # Notify peers of new CRDT
            broadcast_crdt_creation(crdt_id, crdt_type, new_state)
            
            Logger.info("Created CRDT: #{crdt_id} (#{crdt_type})")
            {:reply, :ok, new_state}
            
          error ->
            {:reply, error, state}
        end
    end
  end
  
  @impl true
  def handle_call({:get_crdt, crdt_id}, _from, state) do
    case Map.get(state.crdts, crdt_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      {crdt_type, crdt_instance} ->
        value = get_crdt_value(crdt_type, crdt_instance)
        {:reply, {:ok, value}, state}
    end
  end
  
  @impl true
  def handle_call({:update_crdt, crdt_id, operation, value}, _from, state) do
    case Map.get(state.crdts, crdt_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      {crdt_type, crdt_instance} ->
        case update_crdt_instance(crdt_type, crdt_instance, operation, value) do
          {:ok, new_instance} ->
            new_crdts = Map.put(state.crdts, crdt_id, {crdt_type, new_instance})
            new_state = increment_vector_clock(state)
            new_state = %{new_state | crdts: new_crdts}
            
            # Broadcast update to peers
            broadcast_crdt_update(crdt_id, operation, value, new_state)
            
            # Update stats
            new_stats = increment_stat(new_state.stats, :updates)
            new_state = %{new_state | stats: new_stats}
            
            {:reply, :ok, new_state}
            
          error ->
            {:reply, error, state}
        end
    end
  end
  
  @impl true
  def handle_call({:merge_remote_state, crdt_id, remote_state}, _from, state) do
    case Map.get(state.crdts, crdt_id) do
      nil ->
        # Create CRDT from remote state
        case create_crdt_from_remote(crdt_id, remote_state, state) do
          {:ok, new_state} ->
            {:reply, :ok, new_state}
          error ->
            {:reply, error, state}
        end
        
      {crdt_type, local_instance} ->
        case merge_crdt_instances(crdt_type, local_instance, remote_state) do
          {:ok, merged_instance} ->
            new_crdts = Map.put(state.crdts, crdt_id, {crdt_type, merged_instance})
            new_state = %{state | crdts: new_crdts}
            
            # Update stats
            new_stats = increment_stat(new_state.stats, :merges)
            new_state = %{new_state | stats: new_stats}
            
            {:reply, :ok, new_state}
            
          error ->
            {:reply, error, state}
        end
    end
  end
  
  @impl true
  def handle_call(:list_crdts, _from, state) do
    crdt_list = state.crdts
    |> Enum.map(fn {crdt_id, {crdt_type, crdt_instance}} ->
      %{
        id: crdt_id,
        type: crdt_type,
        value: get_crdt_value(crdt_type, crdt_instance),
        size: get_crdt_size(crdt_type, crdt_instance)
      }
    end)
    
    {:reply, crdt_list, state}
  end
  
  @impl true
  def handle_call(:get_vector_clock, _from, state) do
    {:reply, state.vector_clock, state}
  end
  
  @impl true
  def handle_call({:add_sync_peer, peer_node_id}, _from, state) do
    new_peers = MapSet.put(state.sync_peers, peer_node_id)
    new_state = %{state | sync_peers: new_peers}
    Logger.info("Added sync peer: #{peer_node_id}")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:remove_sync_peer, peer_node_id}, _from, state) do
    new_peers = MapSet.delete(state.sync_peers, peer_node_id)
    new_state = %{state | sync_peers: new_peers}
    Logger.info("Removed sync peer: #{peer_node_id}")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      crdt_count: map_size(state.crdts),
      peer_count: MapSet.size(state.sync_peers),
      node_id: state.node_id,
      vector_clock: state.vector_clock
    })
    {:reply, stats, state}
  end
  
  def handle_call({:synthesize_knowledge, domains}, _from, state) do
    case perform_knowledge_synthesis(domains, state) do
      {:ok, synthesis} ->
        {:reply, {:ok, synthesis}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:generate_memory_narrative, focus_area}, _from, state) do
    case generate_llm_memory_narrative(focus_area, state) do
      {:ok, narrative} ->
        {:reply, {:ok, narrative}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call(:analyze_memory_patterns, _from, state) do
    case analyze_memory_with_llm(state) do
      {:ok, analysis} ->
        {:reply, {:ok, analysis}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_cast(:sync_with_peers, state) do
    new_state = perform_peer_sync(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:periodic_sync, state) do
    new_state = perform_peer_sync(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:crdt_sync_message, message}, state) do
    new_state = handle_sync_message(message, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, event_name, data}, state) do
    # Handle context and belief events automatically
    new_state = case event_name do
      :amcp_context_update ->
        handle_context_update(data, state)
        
      :amcp_belief_change ->
        handle_belief_change(data, state)
        
      :vsm_state_change ->
        handle_vsm_state_change(data, state)
        
      _ ->
        state
    end
    
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp init_stats do
    %{
      updates: 0,
      merges: 0,
      syncs: 0,
      created_at: DateTime.utc_now()
    }
  end
  
  defp increment_stat(stats, key) do
    Map.update(stats, key, 1, &(&1 + 1))
  end
  
  defp generate_node_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp generate_relationship_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
  
  defp increment_vector_clock(state) do
    current_clock = Map.get(state.vector_clock, state.node_id, 0)
    new_clock = Map.put(state.vector_clock, state.node_id, current_clock + 1)
    %{state | vector_clock: new_clock}
  end
  
  defp create_crdt_instance(:g_set, initial_value, _node_id) do
    {:ok, GSet.new(initial_value || [])}
  end
  
  defp create_crdt_instance(:pn_counter, initial_value, node_id) do
    {:ok, PNCounter.new(node_id, initial_value || 0)}
  end
  
  defp create_crdt_instance(:lww_register, initial_value, node_id) do
    {:ok, LWWRegister.new(node_id, initial_value)}
  end
  
  defp create_crdt_instance(:or_set, initial_value, node_id) do
    {:ok, ORSet.new(node_id, initial_value || [])}
  end
  
  defp create_crdt_instance(:crdt_map, initial_value, node_id) do
    {:ok, CRDTMap.new(node_id, initial_value || %{})}
  end
  
  defp create_crdt_instance(unknown_type, _initial_value, _node_id) do
    {:error, {:unsupported_crdt_type, unknown_type}}
  end
  
  defp get_crdt_value(:g_set, instance), do: GSet.value(instance)
  defp get_crdt_value(:pn_counter, instance), do: PNCounter.value(instance)
  defp get_crdt_value(:lww_register, instance), do: LWWRegister.value(instance)
  defp get_crdt_value(:or_set, instance), do: ORSet.value(instance)
  defp get_crdt_value(:crdt_map, instance), do: CRDTMap.value(instance)
  
  defp get_crdt_size(:g_set, instance), do: GSet.size(instance)
  defp get_crdt_size(:pn_counter, _instance), do: 1
  defp get_crdt_size(:lww_register, _instance), do: 1
  defp get_crdt_size(:or_set, instance), do: ORSet.size(instance)
  defp get_crdt_size(:crdt_map, instance), do: CRDTMap.size(instance)
  
  defp update_crdt_instance(:g_set, instance, :add, value) do
    {:ok, GSet.add(instance, value)}
  end
  
  defp update_crdt_instance(:pn_counter, instance, :increment, amount) do
    {:ok, PNCounter.increment(instance, amount)}
  end
  
  defp update_crdt_instance(:pn_counter, instance, :decrement, amount) do
    {:ok, PNCounter.decrement(instance, amount)}
  end
  
  defp update_crdt_instance(:lww_register, instance, :set, value) do
    {:ok, LWWRegister.set(instance, value)}
  end
  
  defp update_crdt_instance(:or_set, instance, :add, value) do
    {:ok, ORSet.add(instance, value)}
  end
  
  defp update_crdt_instance(:or_set, instance, :remove, value) do
    {:ok, ORSet.remove(instance, value)}
  end
  
  defp update_crdt_instance(:crdt_map, instance, :put, {key, subkey, value}) do
    {:ok, CRDTMap.put(instance, key, subkey, value)}
  end
  
  defp update_crdt_instance(:crdt_map, instance, :remove, {key, subkey}) do
    {:ok, CRDTMap.remove(instance, key, subkey)}
  end
  
  defp update_crdt_instance(_type, _instance, operation, _value) do
    {:error, {:unsupported_operation, operation}}
  end
  
  defp merge_crdt_instances(:g_set, local, remote), do: {:ok, GSet.merge(local, remote)}
  defp merge_crdt_instances(:pn_counter, local, remote), do: {:ok, PNCounter.merge(local, remote)}
  defp merge_crdt_instances(:lww_register, local, remote), do: {:ok, LWWRegister.merge(local, remote)}
  defp merge_crdt_instances(:or_set, local, remote), do: {:ok, ORSet.merge(local, remote)}
  defp merge_crdt_instances(:crdt_map, local, remote), do: {:ok, CRDTMap.merge(local, remote)}
  
  defp broadcast_crdt_creation(crdt_id, crdt_type, state) do
    {_, crdt_instance} = Map.get(state.crdts, crdt_id)
    
    EventBus.publish(:amcp_crdt_created, %{
      crdt_id: crdt_id,
      crdt_type: crdt_type,
      node_id: state.node_id,
      vector_clock: state.vector_clock,
      crdt_data: serialize_crdt_instance(crdt_type, crdt_instance)
    })
    
    # Also send directly to known peers
    if MapSet.size(state.sync_peers) > 0 do
      sync_message = %{
        type: :crdt_sync,
        operation: :create,
        crdt_id: crdt_id,
        crdt_type: crdt_type,
        crdt_data: serialize_crdt_instance(crdt_type, crdt_instance),
        vector_clock: state.vector_clock,
        node_id: state.node_id
      }
      
      send_to_peers(state.sync_peers, sync_message)
    end
  end
  
  defp serialize_crdt_instance(:g_set, instance), do: GSet.to_list(instance)
  defp serialize_crdt_instance(:pn_counter, instance), do: PNCounter.to_map(instance)
  defp serialize_crdt_instance(:lww_register, instance), do: LWWRegister.to_map(instance)
  defp serialize_crdt_instance(:or_set, instance), do: ORSet.to_map(instance)
  defp serialize_crdt_instance(:crdt_map, instance), do: CRDTMap.to_map(instance)
  
  defp broadcast_crdt_update(crdt_id, operation, value, state) do
    EventBus.publish(:amcp_crdt_updated, %{
      crdt_id: crdt_id,
      operation: operation,
      value: value,
      node_id: state.node_id,
      vector_clock: state.vector_clock
    })
  end
  
  defp perform_peer_sync(state) do
    if MapSet.size(state.sync_peers) > 0 do
      # Create sync digest
      sync_digest = %{
        type: :sync_digest,
        node_id: state.node_id,
        vector_clock: state.vector_clock,
        crdt_summaries: create_crdt_summaries(state.crdts),
        timestamp: DateTime.utc_now()
      }
      
      # Send to all peers
      send_to_peers(state.sync_peers, sync_digest)
      
      # Also publish to EventBus for monitoring
      EventBus.publish(:amcp_crdt_sync_request, sync_digest)
      
      new_stats = increment_stat(state.stats, :syncs)
      %{state | stats: new_stats}
    else
      state
    end
  end
  
  defp send_to_peers(peers, message) do
    Enum.each(peers, fn peer_node_id ->
      # Try multiple transport mechanisms
      case send_via_transport(peer_node_id, message) do
        :ok -> 
          Logger.debug("Sent sync message to #{peer_node_id}")
        {:error, reason} ->
          Logger.warning("Failed to send to #{peer_node_id}: #{inspect(reason)}")
          # Fallback to EventBus
          EventBus.publish({:crdt_sync, peer_node_id}, message)
      end
    end)
  end
  
  defp send_via_transport(peer_node_id, message) do
    # First try direct process messaging if on same node
    case Process.whereis(String.to_atom("crdt_store_#{peer_node_id}")) do
      pid when is_pid(pid) ->
        send(pid, {:crdt_sync_message, message})
        :ok
        
      nil ->
        # Try AMQP if available
        send_via_amqp(peer_node_id, message)
    end
  end
  
  defp send_via_amqp(peer_node_id, message) do
    case EventBus.call(:amqp_publisher, {:publish, "crdt.sync.#{peer_node_id}", message}, 1000) do
      {:ok, _} -> :ok
      error -> error
    end
  end
  
  defp handle_sync_message(%{type: :sync_digest} = digest, state) do
    # Compare vector clocks and summaries
    differences = find_crdt_differences(digest, state)
    
    if not Enum.empty?(differences) do
      # Send full state for differing CRDTs
      sync_response = %{
        type: :sync_response,
        node_id: state.node_id,
        updates: prepare_sync_updates(differences, state),
        vector_clock: state.vector_clock
      }
      
      send_via_transport(digest.node_id, sync_response)
    end
    
    state
  end
  
  defp handle_sync_message(%{type: :sync_response, updates: updates}, state) do
    # Apply remote updates
    Enum.reduce(updates, state, fn update, acc_state ->
      case update do
        %{crdt_id: id, operation: :create, crdt_type: type, crdt_data: data} ->
          case create_crdt_from_remote(id, %{crdt_type: type, crdt_data: data, vector_clock: update.vector_clock}, acc_state) do
            {:ok, new_state} -> new_state
            _ -> acc_state
          end
          
        %{crdt_id: id, operation: :update, crdt_data: data} ->
          case merge_remote_state(id, data) do
            :ok -> acc_state
            _ -> acc_state
          end
      end
    end)
  end
  
  defp handle_sync_message(%{type: :crdt_sync, operation: operation} = message, state) do
    # Handle direct CRDT operations from peers
    case operation do
      :create ->
        handle_remote_create(message, state)
      :update ->
        handle_remote_update(message, state)
      _ ->
        state
    end
  end
  
  defp handle_sync_message(_message, state), do: state
  
  defp find_crdt_differences(digest, state) do
    remote_summaries = Map.new(digest.crdt_summaries, &{&1.id, &1})
    
    state.crdts
    |> Enum.filter(fn {crdt_id, {crdt_type, crdt_instance}} ->
      case Map.get(remote_summaries, crdt_id) do
        nil -> true  # Remote doesn't have this CRDT
        %{checksum: remote_checksum} ->
          local_checksum = calculate_crdt_checksum(crdt_type, crdt_instance)
          local_checksum != remote_checksum
      end
    end)
    |> Enum.map(fn {crdt_id, _} -> crdt_id end)
  end
  
  defp prepare_sync_updates(crdt_ids, state) do
    Enum.map(crdt_ids, fn crdt_id ->
      {crdt_type, crdt_instance} = Map.get(state.crdts, crdt_id)
      
      %{
        crdt_id: crdt_id,
        operation: :update,
        crdt_type: crdt_type,
        crdt_data: serialize_crdt_instance(crdt_type, crdt_instance),
        vector_clock: state.vector_clock
      }
    end)
  end
  
  defp handle_remote_create(message, state) do
    %{crdt_id: id, crdt_type: type, crdt_data: data, vector_clock: clock} = message
    
    case create_crdt_from_remote(id, %{crdt_type: type, crdt_data: data, vector_clock: clock}, state) do
      {:ok, new_state} -> new_state
      _ -> state
    end
  end
  
  defp handle_remote_update(message, state) do
    %{crdt_id: id, crdt_data: data} = message
    
    case Map.get(state.crdts, id) do
      {crdt_type, local_instance} ->
        remote_instance = reconstruct_crdt_instance(crdt_type, data, message.node_id)
        case merge_crdt_instances(crdt_type, local_instance, remote_instance) do
          {:ok, merged} ->
            new_crdts = Map.put(state.crdts, id, {crdt_type, merged})
            %{state | crdts: new_crdts}
          _ ->
            state
        end
      nil ->
        state
    end
  end
  
  defp create_crdt_summaries(crdts) do
    crdts
    |> Enum.map(fn {crdt_id, {crdt_type, crdt_instance}} ->
      %{
        id: crdt_id,
        type: crdt_type,
        checksum: calculate_crdt_checksum(crdt_type, crdt_instance)
      }
    end)
  end
  
  defp calculate_crdt_checksum(crdt_type, crdt_instance) do
    value = get_crdt_value(crdt_type, crdt_instance)
    :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)
  end
  
  defp handle_context_update(data, state) do
    context_id = data[:context_id] || "global"
    create_context_graph(context_id)
    state
  end
  
  defp handle_belief_change(data, state) do
    agent_id = data[:agent_id] || "system"
    create_belief_set(agent_id)
    state
  end
  
  defp handle_vsm_state_change(data, state) do
    subsystem = data[:subsystem] || "unknown"
    metric_name = "vsm_updates_#{subsystem}"
    create_metric_counter(metric_name)
    increment_metric(metric_name)
    state
  end
  
  defp create_crdt_from_remote(crdt_id, remote_state, state) do
    case remote_state do
      %{crdt_type: crdt_type, crdt_data: crdt_data, vector_clock: remote_clock} ->
        # Reconstruct CRDT instance from remote state
        case reconstruct_crdt_instance(crdt_type, crdt_data, state.node_id) do
          {:ok, crdt_instance} ->
            new_crdts = Map.put(state.crdts, crdt_id, {crdt_type, crdt_instance})
            
            # Merge vector clocks
            merged_clock = merge_vector_clocks(state.vector_clock, remote_clock)
            
            new_state = %{state | 
              crdts: new_crdts,
              vector_clock: merged_clock
            }
            
            Logger.info("Created CRDT #{crdt_id} from remote state")
            {:ok, new_state}
            
          error ->
            Logger.error("Failed to reconstruct CRDT from remote: #{inspect(error)}")
            error
        end
        
      _ ->
        {:error, :invalid_remote_state}
    end
  end
  
  defp reconstruct_crdt_instance(:g_set, data, _node_id) when is_list(data) do
    {:ok, GSet.new(data)}
  end
  
  defp reconstruct_crdt_instance(:pn_counter, %{increments: inc, decrements: dec}, node_id) do
    {:ok, PNCounter.reconstruct(node_id, inc, dec)}
  end
  
  defp reconstruct_crdt_instance(:lww_register, %{value: value, timestamp: ts}, node_id) do
    {:ok, LWWRegister.reconstruct(node_id, value, ts)}
  end
  
  defp reconstruct_crdt_instance(:or_set, %{adds: adds, removes: removes}, node_id) do
    {:ok, ORSet.reconstruct(node_id, adds, removes)}
  end
  
  defp reconstruct_crdt_instance(:crdt_map, data, node_id) when is_map(data) do
    {:ok, CRDTMap.reconstruct(node_id, data)}
  end
  
  defp reconstruct_crdt_instance(type, _data, _node_id) do
    {:error, {:unsupported_crdt_type, type}}
  end
  
  defp merge_vector_clocks(local_clock, remote_clock) do
    Map.merge(local_clock, remote_clock, fn _k, v1, v2 -> max(v1, v2) end)
  end
  
  @doc """
  Synthesize knowledge from distributed CRDT data using LLM analysis.
  """
  def synthesize_knowledge(knowledge_domains \\ :all) do
    GenServer.call(__MODULE__, {:synthesize_knowledge, knowledge_domains}, 30_000)
  end
  
  @doc """
  Generate narrative summary of memory contents.
  """
  def generate_memory_narrative(focus_area \\ :general) do
    GenServer.call(__MODULE__, {:generate_memory_narrative, focus_area}, 25_000)
  end
  
  @doc """
  Perform LLM-powered analysis of memory patterns.
  """
  def analyze_memory_patterns do
    GenServer.call(__MODULE__, :analyze_memory_patterns, 20_000)
  end
  
  # Private Functions
  
  defp perform_knowledge_synthesis(domains, state) do
    # Extract relevant CRDT data based on domains
    knowledge_data = extract_knowledge_data(domains, state)
    
    # Use LLM to synthesize insights
    LLMBridge.call_llm_api(
      """
      Synthesize knowledge from this distributed memory system data:
      
      Knowledge Domains: #{inspect(domains)}
      CRDT Data Summary:
      #{format_crdt_data_for_llm(knowledge_data)}
      
      Provide synthesis covering:
      1. Key patterns and relationships discovered
      2. Emergent insights from the distributed data
      3. Knowledge gaps or inconsistencies
      4. Strategic implications
      5. Recommended actions based on knowledge
      6. Evolution of understanding over time
      
      Generate coherent knowledge synthesis from the distributed memory.
      """,
      :knowledge_synthesis,
      timeout: 25_000
    )
  end
  
  defp generate_llm_memory_narrative(focus_area, state) do
    # Get memory overview
    memory_overview = get_memory_overview(state)
    
    LLMBridge.call_llm_api(
      """
      Generate a narrative description of the system's distributed memory:
      
      Focus Area: #{focus_area}
      Memory Overview: #{memory_overview}
      
      Total CRDTs: #{map_size(state.crdts)}
      Node ID: #{state.node_id}
      Sync Peers: #{length(state.sync_peers)}
      
      Create a narrative that explains:
      1. What the system remembers and knows
      2. How knowledge is distributed and synchronized
      3. The evolution of understanding over time
      4. Key insights stored in memory
      5. The relationship between different memory domains
      
      Write as the system describing its own memory and knowledge.
      """,
      :memory_narrative,
      timeout: 20_000
    )
  end
  
  defp analyze_memory_with_llm(state) do
    # Extract memory patterns for analysis
    memory_patterns = extract_memory_patterns(state)
    
    LLMBridge.call_llm_api(
      """
      Analyze patterns in this distributed memory system:
      
      Memory Patterns: #{inspect(memory_patterns, limit: 5)}
      System Stats: #{inspect(state.stats, limit: 3)}
      Active CRDTs: #{map_size(state.crdts)}
      
      Analyze:
      1. Memory usage patterns and efficiency
      2. Knowledge distribution across nodes
      3. Synchronization patterns and consistency
      4. Data growth and evolution trends
      5. Potential optimizations or improvements
      6. Health and integrity of distributed memory
      
      Provide technical analysis and recommendations.
      """,
      :memory_analysis,
      timeout: 18_000
    )
  end
  
  defp extract_knowledge_data(domains, state) do
    case domains do
      :all ->
        state.crdts
        |> Enum.take(10)  # Limit for LLM context
        |> Enum.map(fn {id, crdt} -> {id, summarize_crdt(crdt)} end)
        |> Map.new()
        
      specific_domains when is_list(specific_domains) ->
        state.crdts
        |> Enum.filter(fn {id, _} -> 
          Enum.any?(specific_domains, &String.contains?(id, to_string(&1)))
        end)
        |> Enum.take(10)
        |> Enum.map(fn {id, crdt} -> {id, summarize_crdt(crdt)} end)
        |> Map.new()
        
      single_domain ->
        state.crdts
        |> Enum.filter(fn {id, _} -> String.contains?(id, to_string(single_domain)) end)
        |> Enum.take(10)
        |> Enum.map(fn {id, crdt} -> {id, summarize_crdt(crdt)} end)
        |> Map.new()
    end
  end
  
  defp format_crdt_data_for_llm(knowledge_data) do
    knowledge_data
    |> Enum.map(fn {id, summary} ->
      "#{id}: #{inspect(summary, limit: 3)}"
    end)
    |> Enum.join("\n")
  end
  
  defp summarize_crdt(crdt_instance) do
    cond do
      is_struct(crdt_instance, GSet) ->
        %{type: :g_set, size: MapSet.size(crdt_instance.set)}
        
      is_struct(crdt_instance, PNCounter) ->
        %{type: :pn_counter, value: PNCounter.value(crdt_instance)}
        
      is_struct(crdt_instance, LWWRegister) ->
        %{type: :lww_register, value: LWWRegister.value(crdt_instance)}
        
      is_struct(crdt_instance, ORSet) ->
        %{type: :or_set, size: ORSet.size(crdt_instance)}
        
      is_struct(crdt_instance, CRDTMap) ->
        %{type: :crdt_map, keys: Map.keys(crdt_instance.entries) |> Enum.take(5)}
        
      true ->
        %{type: :unknown, data: inspect(crdt_instance, limit: 2)}
    end
  end
  
  defp get_memory_overview(state) do
    crdt_summary = state.crdts
    |> Enum.group_by(fn {_id, crdt} -> summarize_crdt(crdt).type end)
    |> Enum.map(fn {type, crdts} -> {type, length(crdts)} end)
    |> Map.new()
    
    %{
      total_crdts: map_size(state.crdts),
      crdt_types: crdt_summary,
      sync_peers: length(state.sync_peers),
      node_id: state.node_id
    }
  end
  
  defp extract_memory_patterns(state) do
    %{
      crdt_distribution: get_crdt_type_distribution(state),
      memory_usage: get_memory_usage_stats(state),
      sync_activity: get_sync_activity_patterns(state),
      data_evolution: get_data_evolution_trends(state)
    }
  end
  
  defp get_crdt_type_distribution(state) do
    state.crdts
    |> Enum.group_by(fn {_id, crdt} -> summarize_crdt(crdt).type end)
    |> Enum.map(fn {type, crdts} -> {type, length(crdts)} end)
    |> Map.new()
  end
  
  defp get_memory_usage_stats(state) do
    %{
      total_crdts: map_size(state.crdts),
      vector_clock_size: map_size(state.vector_clock),
      merge_queue_size: length(state.merge_queue)
    }
  end
  
  defp get_sync_activity_patterns(state) do
    %{
      active_peers: length(state.sync_peers),
      pending_merges: length(state.merge_queue),
      stats: state.stats
    }
  end
  
  defp get_data_evolution_trends(_state) do
    # This would track how data changes over time
    # For now, provide basic trend indicators
    %{
      growth_rate: :steady,
      consistency_level: :high,
      sync_frequency: :normal
    }
  end
end