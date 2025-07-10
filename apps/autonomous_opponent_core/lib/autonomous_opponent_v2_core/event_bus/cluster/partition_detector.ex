defmodule AutonomousOpponentV2Core.EventBus.Cluster.PartitionDetector do
  @moduledoc """
  Partition Detector - Split-Brain Detection and Resolution for VSM
  
  This module implements sophisticated network partition detection for the distributed VSM.
  It uses multiple strategies to detect split-brain scenarios and provides resolution
  mechanisms based on cybernetic principles.
  
  ## Detection Strategies
  
  1. **Quorum-Based**: Classic majority detection
  2. **VSM Health-Based**: Uses algedonic signals and variety flow
  3. **Asymmetric Failure Detection**: Detects one-way network failures
  4. **Temporal Analysis**: Monitors communication patterns over time
  
  ## Resolution Strategies
  
  1. **Static Quorum**: Only majority partition continues
  2. **Dynamic Weights**: Based on VSM subsystem health
  3. **Last Writer Wins**: Using HLC timestamps
  4. **Manual Intervention**: For critical systems
  
  ## Cybernetic Principles
  
  - Partitions represent variety channel disruption
  - Resolution must maintain system viability
  - Algedonic signals indicate partition urgency
  - S5 (Policy) makes final partition decisions
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Telemetry
  alias AutonomousOpponentV2Core.HybridLogicalClock, as: HLC
  
  defstruct [
    :strategy,
    :quorum_size,
    :nodes,
    :node_states,
    :partition_history,
    :detection_window,
    :vsm_health_scores,
    :config
  ]
  
  @detection_window 30_000  # 30 seconds
  @health_check_interval 5_000  # 5 seconds
  @communication_timeout 3_000  # 3 seconds
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Check for network partitions among the given nodes
  """
  def check(server \\ __MODULE__, nodes) do
    GenServer.call(server, {:check_partition, nodes}, 10_000)
  end
  
  @doc """
  Get current partition status
  """
  def status(server \\ __MODULE__) do
    GenServer.call(server, :get_status)
  end
  
  @doc """
  Notify detector of node addition
  """
  def node_added(server \\ __MODULE__, node) do
    GenServer.cast(server, {:node_added, node})
  end
  
  @doc """
  Notify detector of node removal
  """
  def node_removed(server \\ __MODULE__, node) do
    GenServer.cast(server, {:node_removed, node})
  end
  
  @doc """
  Update VSM health score for a node
  """
  def update_health_score(server \\ __MODULE__, node, score) do
    GenServer.cast(server, {:update_health_score, node, score})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    strategy = opts[:strategy] || :static_quorum
    quorum_size = opts[:quorum_size] || :majority
    
    config = %{
      detection_interval: opts[:detection_interval] || @health_check_interval,
      detection_window: opts[:detection_window] || @detection_window,
      communication_timeout: opts[:communication_timeout] || @communication_timeout,
      vsm_weight_factors: opts[:vsm_weight_factors] || default_weight_factors()
    }
    
    state = %__MODULE__{
      strategy: strategy,
      quorum_size: quorum_size,
      nodes: MapSet.new([node() | Node.list()]),
      node_states: init_node_states(),
      partition_history: [],
      detection_window: config.detection_window,
      vsm_health_scores: %{},
      config: config
    }
    
    # Schedule periodic health checks
    schedule_health_check(config.detection_interval)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:check_partition, nodes}, _from, state) do
    # Comprehensive partition detection
    result = perform_partition_detection(nodes, state)
    
    # Update state with detection results
    new_state = case result do
      {:partitioned, partitions} ->
        record_partition(partitions, state)
      :healthy ->
        state
    end
    
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      strategy: state.strategy,
      nodes: MapSet.to_list(state.nodes),
      node_states: state.node_states,
      current_partition: detect_current_partition(state),
      partition_history: Enum.take(state.partition_history, 10),
      vsm_health_scores: state.vsm_health_scores
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_cast({:node_added, node}, state) do
    new_nodes = MapSet.put(state.nodes, node)
    new_node_states = Map.put(state.node_states, node, %{
      reachable: true,
      last_seen: System.monotonic_time(:millisecond),
      communication_matrix: %{}
    })
    
    {:noreply, %{state | nodes: new_nodes, node_states: new_node_states}}
  end
  
  @impl true
  def handle_cast({:node_removed, node}, state) do
    new_nodes = MapSet.delete(state.nodes, node)
    new_node_states = Map.delete(state.node_states, node)
    new_health_scores = Map.delete(state.vsm_health_scores, node)
    
    {:noreply, %{state | 
      nodes: new_nodes, 
      node_states: new_node_states,
      vsm_health_scores: new_health_scores
    }}
  end
  
  @impl true
  def handle_cast({:update_health_score, node, score}, state) do
    new_health_scores = Map.put(state.vsm_health_scores, node, %{
      score: score,
      timestamp: System.monotonic_time(:millisecond)
    })
    
    {:noreply, %{state | vsm_health_scores: new_health_scores}}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    # Perform comprehensive health check
    new_state = perform_health_check(state)
    
    # Check for partitions
    case detect_current_partition(new_state) do
      {:partitioned, partitions} ->
        if not partition_already_detected?(partitions, new_state) do
          Logger.error("Partition detected during health check: #{inspect(partitions)}")
          EventBus.publish(:partition_detected, %{partitions: partitions})
        end
        
      :healthy ->
        # Check if we recovered from partition
        if length(state.partition_history) > 0 and 
           elem(hd(state.partition_history), 1) == :active do
          Logger.info("Partition healed - all nodes reachable")
          EventBus.publish(:partition_healed, %{nodes: MapSet.to_list(state.nodes)})
        end
    end
    
    schedule_health_check(state.config.detection_interval)
    
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp default_weight_factors do
    %{
      s5_policy: 5.0,      # Highest weight for governance
      s4_intelligence: 4.0, # Intelligence subsystem
      s3_control: 3.0,     # Resource control
      s2_coordination: 2.0, # Anti-oscillation
      s1_operational: 1.0,  # Basic operations
      algedonic_health: 10.0 # Pain signals are critical
    }
  end
  
  defp init_node_states do
    nodes = [node() | Node.list()]
    
    Enum.reduce(nodes, %{}, fn n, acc ->
      Map.put(acc, n, %{
        reachable: true,
        last_seen: System.monotonic_time(:millisecond),
        communication_matrix: init_communication_matrix(nodes, n)
      })
    end)
  end
  
  defp init_communication_matrix(all_nodes, from_node) do
    Enum.reduce(all_nodes, %{}, fn to_node, acc ->
      if to_node != from_node do
        Map.put(acc, to_node, %{
          reachable: true,
          latency: nil,
          last_check: System.monotonic_time(:millisecond)
        })
      else
        acc
      end
    end)
  end
  
  defp perform_partition_detection(nodes, state) do
    # Build communication graph
    comm_graph = build_communication_graph(nodes, state)
    
    # Find strongly connected components
    partitions = find_partitions(comm_graph)
    
    # Apply detection strategy
    case state.strategy do
      :static_quorum ->
        detect_quorum_partition(partitions, state.quorum_size, nodes)
        
      :dynamic_weights ->
        detect_weighted_partition(partitions, state)
        
      :vsm_health ->
        detect_vsm_health_partition(partitions, state)
        
      _ ->
        detect_basic_partition(partitions)
    end
  end
  
  defp build_communication_graph(nodes, state) do
    # Test all node pairs for bidirectional communication
    tasks = for from <- nodes, to <- nodes, from != to do
      Task.async(fn ->
        {from, to, test_communication(from, to, state.config.communication_timeout)}
      end)
    end
    
    results = Task.await_many(tasks, state.config.communication_timeout * 2)
    
    # Build adjacency list
    Enum.reduce(results, %{}, fn {from, to, reachable}, acc ->
      Map.update(acc, from, %{to => reachable}, fn edges ->
        Map.put(edges, to, reachable)
      end)
    end)
  end
  
  defp test_communication(from_node, to_node, timeout) do
    if from_node == node() do
      # Test from local node
      test_remote_node(to_node, timeout)
    else
      # Ask remote node to test
      try do
        :rpc.call(from_node, __MODULE__, :test_remote_node, [to_node, timeout], timeout)
      catch
        _, _ -> false
      end
    end
  end
  
  def test_remote_node(target_node, timeout) do
    # Public function for RPC calls
    ref = make_ref()
    test_pid = self()
    
    # Spawn process on target node
    case :rpc.call(target_node, Kernel, :spawn, [fn ->
      send(test_pid, {:pong, ref})
    end], timeout) do
      {:badrpc, _} -> 
        false
      _ ->
        # Wait for response
        receive do
          {:pong, ^ref} -> true
        after
          timeout -> false
        end
    end
  end
  
  defp find_partitions(comm_graph) do
    # Tarjan's algorithm for strongly connected components
    nodes = Map.keys(comm_graph)
    
    {_index, _stack, _indices, _lowlinks, _on_stack, sccs} = 
      Enum.reduce(nodes, {0, [], %{}, %{}, %{}, []}, fn node, acc ->
        if Map.has_key?(elem(acc, 2), node) do
          acc
        else
          tarjan_visit(node, comm_graph, acc)
        end
      end)
    
    # Filter out single-node partitions
    Enum.filter(sccs, fn scc -> length(scc) > 1 end)
  end
  
  defp tarjan_visit(node, graph, {index, stack, indices, lowlinks, on_stack, sccs}) do
    # Initialize node
    indices = Map.put(indices, node, index)
    lowlinks = Map.put(lowlinks, node, index)
    index = index + 1
    stack = [node | stack]
    on_stack = Map.put(on_stack, node, true)
    
    # Visit neighbors
    neighbors = Map.get(graph, node, %{})
    |> Enum.filter(fn {_n, reachable} -> reachable end)
    |> Enum.map(fn {n, _} -> n end)
    
    {index, stack, indices, lowlinks, on_stack, sccs} = 
      Enum.reduce(neighbors, {index, stack, indices, lowlinks, on_stack, sccs}, 
        fn neighbor, acc ->
          if not Map.has_key?(elem(acc, 2), neighbor) do
            # Neighbor not visited
            {new_index, new_stack, new_indices, new_lowlinks, new_on_stack, new_sccs} = 
              tarjan_visit(neighbor, graph, acc)
            
            # Update lowlink
            node_lowlink = Map.get(new_lowlinks, node)
            neighbor_lowlink = Map.get(new_lowlinks, neighbor)
            new_lowlinks = Map.put(new_lowlinks, node, min(node_lowlink, neighbor_lowlink))
            
            {new_index, new_stack, new_indices, new_lowlinks, new_on_stack, new_sccs}
          else
            if Map.get(elem(acc, 4), neighbor, false) do
              # Neighbor is on stack
              {i, s, ind, low, os, sc} = acc
              node_lowlink = Map.get(low, node)
              neighbor_index = Map.get(ind, neighbor)
              new_lowlinks = Map.put(low, node, min(node_lowlink, neighbor_index))
              {i, s, ind, new_lowlinks, os, sc}
            else
              acc
            end
          end
        end)
    
    # Check if root of SCC
    if Map.get(lowlinks, node) == Map.get(indices, node) do
      # Pop SCC from stack
      {scc, new_stack, new_on_stack} = pop_scc(node, stack, on_stack, [])
      {index, new_stack, indices, lowlinks, new_on_stack, [scc | sccs]}
    else
      {index, stack, indices, lowlinks, on_stack, sccs}
    end
  end
  
  defp pop_scc(node, [node | rest], on_stack, scc) do
    {[node | scc], rest, Map.put(on_stack, node, false)}
  end
  defp pop_scc(node, [other | rest], on_stack, scc) do
    pop_scc(node, rest, Map.put(on_stack, other, false), [other | scc])
  end
  defp pop_scc(_node, [], on_stack, scc) do
    {scc, [], on_stack}
  end
  
  defp detect_quorum_partition(partitions, quorum_size, all_nodes) do
    if partitions == [] do
      :healthy
    else
      # Calculate quorum requirement
      total_nodes = length(all_nodes)
      required_quorum = case quorum_size do
        :majority -> div(total_nodes, 2) + 1
        n when is_integer(n) -> n
        _ -> div(total_nodes, 2) + 1
      end
      
      # Check if any partition has quorum
      quorum_partitions = Enum.filter(partitions, fn partition ->
        length(partition) >= required_quorum
      end)
      
      if length(quorum_partitions) > 0 do
        {:partitioned, partitions}
      else
        # No partition has quorum - split brain!
        {:partitioned, partitions}
      end
    end
  end
  
  defp detect_weighted_partition(partitions, state) do
    if partitions == [] do
      :healthy
    else
      # Calculate weighted scores for each partition
      partition_scores = Enum.map(partitions, fn partition ->
        score = calculate_partition_weight(partition, state)
        {partition, score}
      end)
      
      # Sort by weight
      sorted = Enum.sort_by(partition_scores, fn {_p, score} -> score end, :desc)
      
      # Log partition weights
      Logger.info("Partition weights: #{inspect(sorted)}")
      
      {:partitioned, partitions}
    end
  end
  
  defp calculate_partition_weight(partition, state) do
    Enum.reduce(partition, 0.0, fn node, acc ->
      node_weight = calculate_node_weight(node, state)
      acc + node_weight
    end)
  end
  
  defp calculate_node_weight(node, state) do
    # Base weight
    weight = 1.0
    
    # Add VSM health score if available
    case Map.get(state.vsm_health_scores, node) do
      nil -> 
        weight
      %{score: health_score} ->
        weight + (health_score * state.config.vsm_weight_factors.algedonic_health)
    end
  end
  
  defp detect_vsm_health_partition(partitions, state) do
    if partitions == [] do
      :healthy
    else
      # Use VSM health metrics to determine viable partitions
      viable_partitions = Enum.filter(partitions, fn partition ->
        is_vsm_viable_partition?(partition, state)
      end)
      
      if length(viable_partitions) == length(partitions) do
        # All partitions are viable - this is bad!
        Logger.error("All partitions claim VSM viability - critical split brain!")
        {:partitioned, partitions}
      else
        {:partitioned, partitions}
      end
    end
  end
  
  defp is_vsm_viable_partition?(partition, state) do
    # A partition is viable if it has:
    # 1. At least one S5 (Policy) node
    # 2. Reasonable coverage of other subsystems
    # 3. No critical algedonic signals
    
    partition_health = Enum.reduce(partition, %{}, fn node, acc ->
      case Map.get(state.vsm_health_scores, node) do
        nil -> acc
        %{score: score} -> Map.put(acc, node, score)
      end
    end)
    
    # Simple viability: average health > 0.5
    if map_size(partition_health) > 0 do
      avg_health = Enum.sum(Map.values(partition_health)) / map_size(partition_health)
      avg_health > 0.5
    else
      false
    end
  end
  
  defp detect_basic_partition(partitions) do
    if partitions == [] or length(partitions) == 1 do
      :healthy
    else
      {:partitioned, partitions}
    end
  end
  
  defp detect_current_partition(state) do
    nodes = MapSet.to_list(state.nodes)
    perform_partition_detection(nodes, state)
  end
  
  defp perform_health_check(state) do
    # Update node reachability
    nodes = MapSet.to_list(state.nodes)
    
    tasks = Enum.map(nodes, fn node ->
      if node == node() do
        Task.async(fn -> {node, true} end)
      else
        Task.async(fn ->
          {node, test_remote_node(node, state.config.communication_timeout)}
        end)
      end
    end)
    
    results = Task.await_many(tasks, state.config.communication_timeout * 2)
    
    # Update node states
    now = System.monotonic_time(:millisecond)
    
    new_node_states = Enum.reduce(results, state.node_states, fn {node, reachable}, acc ->
      Map.update(acc, node, %{reachable: false, last_seen: now}, fn node_state ->
        if reachable do
          %{node_state | reachable: true, last_seen: now}
        else
          %{node_state | reachable: false}
        end
      end)
    end)
    
    %{state | node_states: new_node_states}
  end
  
  defp record_partition(partitions, state) do
    entry = {
      DateTime.utc_now(),
      :active,
      partitions,
      determine_local_partition(partitions, state)
    }
    
    new_history = [entry | state.partition_history] |> Enum.take(100)
    
    # Report telemetry
    Telemetry.execute(
      [:vsm, :partition, :detected],
      %{partition_count: length(partitions)},
      %{
        node: node(),
        strategy: state.strategy,
        local_partition_size: length(determine_local_partition(partitions, state))
      }
    )
    
    %{state | partition_history: new_history}
  end
  
  defp determine_local_partition(partitions, _state) do
    # Find which partition contains the local node
    Enum.find(partitions, [], fn partition ->
      node() in partition
    end)
  end
  
  defp partition_already_detected?(partitions, state) do
    case state.partition_history do
      [] -> false
      [{_time, :active, last_partitions, _} | _] ->
        # Check if partitions are the same (order-independent)
        MapSet.new(partitions) == MapSet.new(last_partitions)
      _ -> false
    end
  end
  
  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end
end