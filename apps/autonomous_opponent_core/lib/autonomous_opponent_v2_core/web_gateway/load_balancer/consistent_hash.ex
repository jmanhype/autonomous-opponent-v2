defmodule AutonomousOpponentV2Core.WebGateway.LoadBalancer.ConsistentHash do
  @moduledoc """
  Consistent hashing implementation for Web Gateway load balancing.
  
  Distributes clients across transport nodes using consistent hashing
  to minimize redistribution when nodes are added or removed.
  """
  
  use GenServer
  
  alias AutonomousOpponentV2Core.EventBus
  
  require Logger
  
  @default_vnodes 150
  @hash_function :sha256
  
  defmodule Ring do
    @moduledoc """
    Represents the consistent hash ring.
    """
    defstruct [:vnodes, :nodes, :ring]
  end
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Adds a node to the hash ring.
  """
  def add_node(node, weight \\ 1) do
    GenServer.call(__MODULE__, {:add_node, node, weight})
  end
  
  @doc """
  Removes a node from the hash ring.
  """
  def remove_node(node) do
    GenServer.call(__MODULE__, {:remove_node, node})
  end
  
  @doc """
  Gets the node assignment for a given key.
  """
  def get_node(key, nodes \\ nil) do
    GenServer.call(__MODULE__, {:get_node, key, nodes})
  end
  
  @doc """
  Gets multiple nodes for a key (for replication).
  """
  def get_nodes(key, count) do
    GenServer.call(__MODULE__, {:get_nodes, key, count})
  end
  
  @doc """
  Gets the current ring state.
  """
  def get_ring_state do
    GenServer.call(__MODULE__, :get_ring_state)
  end
  
  @doc """
  Rebalances the hash ring.
  """
  def rebalance do
    GenServer.cast(__MODULE__, :rebalance)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    vnodes = Keyword.get(opts, :vnodes, @default_vnodes)
    initial_nodes = Keyword.get(opts, :nodes, [])
    
    ring = %Ring{
      vnodes: vnodes,
      nodes: %{},
      ring: :gb_trees.empty()
    }
    
    # Add initial nodes
    ring = Enum.reduce(initial_nodes, ring, fn {node, weight}, acc ->
      add_node_to_ring(acc, node, weight)
    end)
    
    # Subscribe to node events
    EventBus.subscribe(:mcp_node_events)
    
    {:ok, ring}
  end
  
  @impl true
  def handle_call({:add_node, node, weight}, _from, ring) do
    if Map.has_key?(ring.nodes, node) do
      {:reply, {:error, :already_exists}, ring}
    else
      new_ring = add_node_to_ring(ring, node, weight)
      
      # Notify about ring change
      notify_ring_change(:node_added, node, new_ring)
      
      {:reply, :ok, new_ring}
    end
  end
  
  @impl true
  def handle_call({:remove_node, node}, _from, ring) do
    if Map.has_key?(ring.nodes, node) do
      new_ring = remove_node_from_ring(ring, node)
      
      # Notify about ring change
      notify_ring_change(:node_removed, node, new_ring)
      
      {:reply, :ok, new_ring}
    else
      {:reply, {:error, :not_found}, ring}
    end
  end
  
  @impl true
  def handle_call({:get_node, key, nodes}, _from, ring) do
    nodes_to_check = nodes || Map.keys(ring.nodes)
    
    case find_node(ring, key, nodes_to_check) do
      {:ok, node} -> {:reply, node, ring}
      :error -> {:reply, nil, ring}
    end
  end
  
  @impl true
  def handle_call({:get_nodes, key, count}, _from, ring) do
    nodes = find_nodes(ring, key, count)
    {:reply, nodes, ring}
  end
  
  @impl true
  def handle_call(:get_ring_state, _from, ring) do
    state = %{
      nodes: Map.keys(ring.nodes),
      weights: ring.nodes,
      vnodes_per_node: ring.vnodes,
      total_vnodes: :gb_trees.size(ring.ring)
    }
    {:reply, state, ring}
  end
  
  @impl true
  def handle_cast(:rebalance, ring) do
    # Rebuild the ring with current nodes
    new_ring = %Ring{
      vnodes: ring.vnodes,
      nodes: %{},
      ring: :gb_trees.empty()
    }
    
    new_ring = Enum.reduce(ring.nodes, new_ring, fn {node, weight}, acc ->
      add_node_to_ring(acc, node, weight)
    end)
    
    notify_ring_change(:rebalanced, nil, new_ring)
    
    {:noreply, new_ring}
  end
  
  @impl true
  def handle_info({:event_bus, :mcp_node_events, %{action: :add, node: node, weight: weight}}, ring) do
    new_ring = add_node_to_ring(ring, node, weight)
    {:noreply, new_ring}
  end
  
  @impl true
  def handle_info({:event_bus, :mcp_node_events, %{action: :remove, node: node}}, ring) do
    new_ring = remove_node_from_ring(ring, node)
    {:noreply, new_ring}
  end
  
  # Private functions
  
  defp add_node_to_ring(ring, node, weight) do
    # Calculate number of vnodes based on weight
    vnode_count = round(ring.vnodes * weight)
    
    # Add vnodes to the ring
    new_ring_tree = Enum.reduce(0..(vnode_count - 1), ring.ring, fn i, tree ->
      vnode_key = hash_key("#{node}:#{i}")
      :gb_trees.enter(vnode_key, node, tree)
    end)
    
    %{ring |
      nodes: Map.put(ring.nodes, node, weight),
      ring: new_ring_tree
    }
  end
  
  defp remove_node_from_ring(ring, node) do
    # Remove all vnodes for this node
    new_ring_tree = :gb_trees.to_list(ring.ring)
    |> Enum.reject(fn {_hash, n} -> n == node end)
    |> :gb_trees.from_orddict()
    
    %{ring |
      nodes: Map.delete(ring.nodes, node),
      ring: new_ring_tree
    }
  end
  
  defp find_node(ring, key, allowed_nodes) do
    hash = hash_key(key)
    
    # Find the first vnode with hash >= key hash
    case find_successor(ring.ring, hash) do
      {:ok, node} ->
        if node in allowed_nodes do
          {:ok, node}
        else
          # Keep searching for an allowed node
          find_next_allowed_node(ring.ring, hash, allowed_nodes)
        end
        
      :error ->
        # Wrap around to the beginning
        case :gb_trees.smallest(ring.ring) do
          {_hash, node} when node in allowed_nodes -> {:ok, node}
          _ -> :error
        end
    end
  end
  
  defp find_nodes(ring, key, count) do
    hash = hash_key(key)
    nodes = find_successive_nodes(ring.ring, hash, count, [])
    Enum.uniq(nodes) |> Enum.take(count)
  end
  
  defp find_successor(tree, hash) do
    iterator = :gb_trees.iterator_from(hash, tree)
    
    case :gb_trees.next(iterator) do
      {_key, value, _iter} -> {:ok, value}
      none -> :error
    end
  end
  
  defp find_next_allowed_node(tree, start_hash, allowed_nodes) do
    iterator = :gb_trees.iterator_from(start_hash, tree)
    find_allowed_in_iterator(iterator, allowed_nodes)
  end
  
  defp find_allowed_in_iterator(iterator, allowed_nodes) do
    case :gb_trees.next(iterator) do
      {_key, node, next_iter} ->
        if node in allowed_nodes do
          {:ok, node}
        else
          find_allowed_in_iterator(next_iter, allowed_nodes)
        end
        
      none ->
        :error
    end
  end
  
  defp find_successive_nodes(tree, hash, count, acc) when length(acc) >= count do
    acc
  end
  
  defp find_successive_nodes(tree, hash, count, acc) do
    case find_successor(tree, hash) do
      {:ok, node} ->
        # Get next hash position
        next_hash = get_next_hash(tree, hash)
        find_successive_nodes(tree, next_hash, count, [node | acc])
        
      :error ->
        # Wrap around
        if :gb_trees.is_empty(tree) do
          acc
        else
          {first_hash, first_node} = :gb_trees.smallest(tree)
          find_successive_nodes(tree, first_hash, count, [first_node | acc])
        end
    end
  end
  
  defp get_next_hash(tree, current_hash) do
    iterator = :gb_trees.iterator_from(current_hash, tree)
    
    case :gb_trees.next(iterator) do
      {key, _value, _iter} -> key + 1
      none -> 0
    end
  end
  
  defp hash_key(key) do
    :crypto.hash(@hash_function, key)
    |> :binary.decode_unsigned()
  end
  
  defp notify_ring_change(action, node, ring) do
    EventBus.publish(:mcp_ring_change, %{
      action: action,
      node: node,
      total_nodes: map_size(ring.nodes),
      total_vnodes: :gb_trees.size(ring.ring)
    })
    
    Logger.info("Consistent hash ring changed: #{action} #{inspect(node)}")
  end
end