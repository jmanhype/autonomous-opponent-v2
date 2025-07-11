defmodule AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator do
  @moduledoc """
  Cluster-wide pattern aggregation for distributed HNSW indices.
  
  Aggregates pattern data across all nodes in the cluster, providing:
  - Unified pattern search across nodes
  - Pattern consensus and confidence scoring
  - Distributed pattern statistics
  - Algedonic pattern prioritization
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
  alias AutonomousOpponentV2Core.Metrics.CRDTStore
  
  defstruct [
    :pattern_cache,
    :node_indices,
    :aggregation_interval,
    :last_aggregation,
    :stats
  ]
  
  @aggregation_interval 30_000  # 30 seconds
  @pattern_consensus_threshold 0.5  # 50% of nodes must have pattern
  @algedonic_priority_threshold 0.8
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Search for similar patterns across the cluster.
  """
  def search_cluster(vector, k \\ 10, opts \\ []) do
    GenServer.call(__MODULE__, {:search_cluster, vector, k, opts})
  end
  
  @doc """
  Get aggregated pattern statistics from all nodes.
  """
  def get_cluster_stats do
    GenServer.call(__MODULE__, :get_cluster_stats)
  end
  
  @doc """
  Get patterns with consensus across multiple nodes.
  """
  def get_consensus_patterns(min_nodes \\ 2) do
    GenServer.call(__MODULE__, {:get_consensus_patterns, min_nodes})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Join the metrics cluster pg group
    :pg.start_link(:metrics_cluster)
    :pg.join(:metrics_cluster, :pattern_aggregator, self())
    
    # Subscribe to pattern events
    EventBus.subscribe(:patterns_indexed)
    EventBus.subscribe(:algedonic_signal)
    
    state = %__MODULE__{
      pattern_cache: %{},
      node_indices: %{},
      aggregation_interval: @aggregation_interval,
      last_aggregation: System.monotonic_time(:millisecond),
      stats: %{
        searches_performed: 0,
        patterns_aggregated: 0,
        consensus_patterns: 0,
        algedonic_patterns: 0
      }
    }
    
    # Schedule first aggregation
    schedule_aggregation()
    
    Logger.info("Pattern Aggregator started for cluster-wide HNSW coordination")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:search_cluster, vector, k, opts}, _from, state) do
    # Get all nodes with pattern indices
    nodes = get_pattern_nodes()
    
    # Perform distributed search
    search_results = perform_distributed_search(nodes, vector, k, opts)
    
    # Update stats
    new_state = update_in(state.stats.searches_performed, &(&1 + 1))
    
    {:reply, {:ok, search_results}, new_state}
  end
  
  @impl true
  def handle_call(:get_cluster_stats, _from, state) do
    # Collect stats from all nodes
    nodes = get_pattern_nodes()
    
    node_stats = :erpc.multicall(
      nodes,
      AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge,
      :get_stats,
      [],
      5000
    )
    
    aggregated_stats = aggregate_node_stats(node_stats, nodes)
    
    {:reply, {:ok, aggregated_stats}, state}
  end
  
  @impl true
  def handle_call({:get_consensus_patterns, min_nodes}, _from, state) do
    consensus_patterns = state.pattern_cache
    |> Enum.filter(fn {_pattern_id, pattern_data} ->
      length(pattern_data.nodes) >= min_nodes
    end)
    |> Enum.map(fn {pattern_id, pattern_data} ->
      %{
        pattern_id: pattern_id,
        nodes: pattern_data.nodes,
        confidence: pattern_data.avg_confidence,
        first_seen: pattern_data.first_seen,
        last_seen: pattern_data.last_seen
      }
    end)
    
    {:reply, {:ok, consensus_patterns}, state}
  end
  
  @impl true
  def handle_info(:aggregate_patterns, state) do
    # Perform pattern aggregation
    new_state = perform_pattern_aggregation(state)
    
    # Schedule next aggregation
    schedule_aggregation()
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :patterns_indexed} = event}, state) do
    # Track indexed patterns for aggregation
    pattern_info = %{
      node: node(),
      count: event.data[:count] || 0,
      timestamp: event.timestamp
    }
    
    # Update CRDT store
    CRDTStore.update(:pattern_index_events, event.id, pattern_info)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :algedonic_signal} = event}, state) do
    # Handle high-priority algedonic patterns
    if event.data[:intensity] > @algedonic_priority_threshold do
      handle_algedonic_pattern(event.data, state)
    else
      {:noreply, state}
    end
  end
  
  # Private functions
  
  defp get_pattern_nodes do
    # Get all nodes running pattern indices
    nodes = [node() | Node.list()]
    
    Enum.filter(nodes, fn n ->
      case :rpc.call(n, Process, :whereis, [AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge]) do
        pid when is_pid(pid) -> true
        _ -> false
      end
    end)
  end
  
  defp perform_distributed_search(nodes, vector, k, opts) do
    # Search each node's HNSW index
    timeout = opts[:timeout] || 5000
    
    results = :erpc.multicall(
      nodes,
      __MODULE__,
      :local_hnsw_search,
      [vector, k],
      timeout
    )
    
    # Process results
    case results do
      {node_results, []} ->
        # All nodes responded
        merge_search_results(node_results, nodes, k)
      
      {node_results, bad_nodes} ->
        # Some nodes failed
        Logger.warning("Pattern search failed on nodes: #{inspect(bad_nodes)}")
        merge_search_results(node_results, nodes -- bad_nodes, k)
    end
  end
  
  def local_hnsw_search(vector, k) do
    # This runs on each node
    case HNSWIndex.search(:hnsw_index, vector, k) do
      {:ok, results} ->
        # Add node information to results
        Enum.map(results, fn {pattern_id, distance} ->
          %{
            pattern_id: pattern_id,
            distance: distance,
            node: node()
          }
        end)
      
      {:error, _reason} ->
        []
    end
  end
  
  defp merge_search_results(node_results, nodes, k) do
    # Flatten and sort all results by distance
    all_results = node_results
    |> List.flatten()
    |> Enum.sort_by(& &1.distance)
    |> Enum.take(k)
    
    # Group by pattern to find consensus
    pattern_groups = Enum.group_by(all_results, & &1.pattern_id)
    
    # Calculate consensus scores
    Enum.map(all_results, fn result ->
      nodes_with_pattern = pattern_groups[result.pattern_id]
      |> Enum.map(& &1.node)
      |> Enum.uniq()
      
      Map.merge(result, %{
        consensus_score: length(nodes_with_pattern) / length(nodes),
        nodes: nodes_with_pattern
      })
    end)
  end
  
  defp aggregate_node_stats({results, _bad_nodes}, nodes) do
    # Sum up stats from all nodes
    total_stats = Enum.reduce(results, %{}, fn node_stats, acc ->
      Map.merge(acc, node_stats, fn _k, v1, v2 ->
        cond do
          is_number(v1) and is_number(v2) -> v1 + v2
          is_map(v1) and is_map(v2) -> Map.merge(v1, v2)
          true -> v2
        end
      end)
    end)
    
    # Add cluster-wide metrics
    Map.merge(total_stats, %{
      cluster_nodes: length(nodes),
      aggregation_timestamp: DateTime.utc_now()
    })
  end
  
  defp perform_pattern_aggregation(state) do
    nodes = get_pattern_nodes()
    
    # Collect pattern summaries from all nodes
    pattern_summaries = collect_pattern_summaries(nodes)
    
    # Update pattern cache with consensus data
    new_cache = update_pattern_cache(state.pattern_cache, pattern_summaries)
    
    # Update stats
    consensus_count = Enum.count(new_cache, fn {_id, data} ->
      length(data.nodes) >= 2
    end)
    
    new_stats = state.stats
    |> Map.update!(:patterns_aggregated, &(&1 + map_size(new_cache)))
    |> Map.put(:consensus_patterns, consensus_count)
    
    %{state | 
      pattern_cache: new_cache,
      stats: new_stats,
      last_aggregation: System.monotonic_time(:millisecond)
    }
  end
  
  defp collect_pattern_summaries(nodes) do
    # Get pattern summaries from each node
    {:ok, summaries} = :erpc.multicall(
      nodes,
      __MODULE__,
      :get_local_pattern_summary,
      [],
      10_000
    )
    
    summaries
  end
  
  def get_local_pattern_summary do
    # This runs on each node to get pattern summary
    case Process.whereis(AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge) do
      nil -> 
        %{node: node(), patterns: []}
      
      _pid ->
        stats = AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_stats()
        
        %{
          node: node(),
          patterns: [], # TODO: Get actual pattern list from HNSW
          total_patterns: stats[:patterns_indexed] || 0,
          dedup_rate: stats[:patterns_deduplicated] || 0
        }
    end
  end
  
  defp update_pattern_cache(cache, summaries) do
    # Merge pattern data from all nodes
    Enum.reduce(summaries, cache, fn summary, acc ->
      node = summary.node
      
      # Update cache with node's patterns
      # TODO: Implement actual pattern merging
      acc
    end)
  end
  
  defp handle_algedonic_pattern(pattern_data, state) do
    # Broadcast high-priority pattern to all nodes immediately
    nodes = get_pattern_nodes()
    
    :erpc.multicast(
      nodes,
      EventBus,
      :publish,
      [:algedonic_pattern_alert, pattern_data]
    )
    
    # Update stats
    new_state = update_in(state.stats.algedonic_patterns, &(&1 + 1))
    
    # Store in CRDT for persistence
    CRDTStore.update(:algedonic_patterns, pattern_data[:id], %{
      pattern: pattern_data,
      nodes_alerted: nodes,
      timestamp: DateTime.utc_now()
    })
    
    {:noreply, new_state}
  end
  
  defp schedule_aggregation do
    Process.send_after(self(), :aggregate_patterns, @aggregation_interval)
  end
end