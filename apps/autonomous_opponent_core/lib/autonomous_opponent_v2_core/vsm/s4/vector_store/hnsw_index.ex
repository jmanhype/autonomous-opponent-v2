defmodule AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex do
  @moduledoc """
  Hierarchical Navigable Small World (HNSW) index for efficient vector similarity search.
  
  This module implements a pure Elixir version of the HNSW algorithm for S4 environmental
  scanning and pattern recognition. It provides fast approximate nearest neighbor search
  with configurable parameters and multiple distance metrics.
  
  ## Algorithm Overview
  
  HNSW builds a multi-layer graph where each layer contains a subset of vectors,
  with connections between similar vectors. Search starts from the top layer and
  navigates down to find nearest neighbors efficiently.
  
  ## Wisdom Preservation
  
  ### Why HNSW for S4?
  S4 Intelligence needs to quickly find similar patterns in high-dimensional spaces.
  Traditional linear search becomes impractical with large pattern libraries.
  HNSW provides logarithmic search complexity while maintaining high recall.
  
  ### Design Decisions
  
  1. **M=16, ef=200 defaults**: Balances index size with search quality.
     M controls connectivity (memory usage), ef controls search beam width (accuracy).
     These values work well for 100-1000 dimensional vectors.
  
  2. **Pure Elixir over NIFs**: Prioritizes maintainability and fault tolerance
     over raw speed. S4's 10-second scan interval allows for millisecond searches.
     
  3. **Incremental index building**: S4 continuously discovers new patterns.
     The index must grow without full rebuilds. Each insertion is independent.
  
  4. **Persistence via :ets**: Fast in-memory storage with disk persistence.
     Survives process crashes but not node restarts. For S4, recent patterns
     matter most, so occasional rebuilds are acceptable.
  """
  
  use GenServer
  require Logger
  
  # WISDOM: M=16 provides good connectivity without excessive memory
  # Each node connects to ~16 neighbors per layer
  @default_m 16
  
  # WISDOM: ef=200 balances search accuracy with speed
  # Explores 200 candidates during search
  @default_ef 200
  
  # WISDOM: ml=1/ln(2) ≈ 1.44 for optimal layer distribution
  # Probability decay for layer assignment
  @ml 1.44
  
  defstruct [
    :m,
    :max_m,
    :max_m0,
    :ef,
    :ef_construction,
    :ml,
    :entry_point,
    :distance_fn,
    :node_count,
    :graph,
    :data_table,
    :level_table,
    :persist_path,
    :prune_timer,
    :prune_interval,
    :prune_max_age
  ]
  
  @type vector :: list(float)
  @type node_id :: non_neg_integer
  @type level :: non_neg_integer
  @type distance_metric :: :cosine | :euclidean
  
  # Client API
  
  @doc """
  Starts the HNSW index process.
  
  Options:
    * `:m` - Number of bidirectional links for each node (default: 16)
    * `:ef` - Size of the candidate list (default: 200)
    * `:distance_metric` - :cosine or :euclidean (default: :cosine)
    * `:persist_path` - Path for persistence (optional)
    * `:prune_interval` - Milliseconds between automatic pruning (optional)
    * `:prune_max_age` - Max age in ms for patterns before pruning (optional)
  
  Example with automatic pruning:
      {:ok, index} = HNSWIndex.start_link(
        prune_interval: :timer.hours(1),
        prune_max_age: :timer.hours(24)
      )
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Creates a new HNSW index without starting a GenServer process.
  Returns {:ok, index_state} for direct use.
  """
  def new(opts \\ []) do
    case init(opts) do
      {:ok, state} -> {:ok, state}
      error -> error
    end
  end
  
  @doc """
  Inserts a vector into the index with associated metadata.
  """
  def insert(server \\ __MODULE__, vector, metadata \\ %{}) when is_list(vector) do
    GenServer.call(server, {:insert, vector, metadata})
  end
  
  @doc """
  Searches for k nearest neighbors of the query vector.
  """
  def search(server \\ __MODULE__, query_vector, k, opts \\ []) when is_list(query_vector) do
    GenServer.call(server, {:search, query_vector, k, opts})
  end
  
  @doc """
  Persists the index to disk.
  """
  def persist(server \\ __MODULE__) do
    GenServer.call(server, :persist)
  end
  
  @doc """
  Returns index statistics.
  """
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end
  
  @doc """
  Compacts the index by removing orphaned nodes and optimizing connections.
  
  This operation:
  - Removes nodes with no connections
  - Rebalances heavily connected nodes
  - Optimizes graph structure for better search performance
  
  Returns {:ok, stats} with compaction statistics.
  """
  def compact(server \\ __MODULE__) do
    GenServer.call(server, :compact, :infinity)
  end
  
  @doc """
  Searches for k nearest neighbors for multiple query vectors in parallel.
  
  Options:
    * `:ef` - Search beam width (default: index ef)
    * `:max_concurrency` - Max parallel searches (default: System.schedulers_online())
    * `:timeout` - Per-search timeout in ms (default: 5000)
  
  Returns results in the same order as query vectors.
  """
  def search_batch(server \\ __MODULE__, query_vectors, k, opts \\ []) when is_list(query_vectors) do
    GenServer.call(server, {:search_batch, query_vectors, k, opts}, :infinity)
  end
  
  @doc """
  Removes patterns older than the specified age in milliseconds.
  
  This helps maintain index freshness for temporal pattern relevance.
  Patterns without :inserted_at timestamp are preserved.
  
  Returns {:ok, removed_count}.
  """
  def prune_old_patterns(server \\ __MODULE__, max_age_ms) when is_integer(max_age_ms) and max_age_ms > 0 do
    GenServer.call(server, {:prune_old_patterns, max_age_ms})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    m = opts[:m] || @default_m
    ef = opts[:ef] || @default_ef
    
    # WISDOM: max_m = M for all but layer 0, max_m0 = M*2 for layer 0
    # Layer 0 has more connections for better connectivity
    max_m = m
    max_m0 = m * 2
    
    # WISDOM: ef_construction > ef for better index quality during building
    ef_construction = max(ef, 64)
    
    # Initialize ETS tables for graph storage
    graph = :ets.new(:hnsw_graph, [:set, :protected])
    data_table = :ets.new(:hnsw_data, [:set, :protected])
    level_table = :ets.new(:hnsw_levels, [:set, :protected])
    
    state = %__MODULE__{
      m: m,
      max_m: max_m,
      max_m0: max_m0,
      ef: ef,
      ef_construction: ef_construction,
      ml: @ml,
      entry_point: nil,
      distance_fn: get_distance_function(opts[:distance_metric] || :cosine),
      node_count: 0,
      graph: graph,
      data_table: data_table,
      level_table: level_table,
      persist_path: opts[:persist_path],
      prune_interval: opts[:prune_interval],
      prune_max_age: opts[:prune_max_age]
    }
    
    # Restore from persistence if path provided and file exists
    final_state = if opts[:persist_path] do
      alias AutonomousOpponentV2Core.VSM.S4.VectorStore.Persistence
      
      if Persistence.index_exists?(opts[:persist_path]) do
        case Persistence.load_index(opts[:persist_path]) do
          {:ok, loaded_state} ->
            Logger.info("Restored HNSW index from #{opts[:persist_path]}")
            Map.merge(state, loaded_state)
          
          {:error, reason} ->
            Logger.warning("Failed to restore index: #{inspect(reason)}, starting fresh")
            state
        end
      else
        state
      end
    else
      state
    end
    
    Logger.info("HNSW index initialized with M=#{m}, ef=#{ef}")
    
    # Schedule periodic pruning if configured
    final_state_with_timer = 
      if final_state.prune_interval && final_state.prune_max_age do
        timer_ref = Process.send_after(self(), :prune_tick, final_state.prune_interval)
        %{final_state | prune_timer: timer_ref}
      else
        final_state
      end
    
    {:ok, final_state_with_timer}
  end
  
  @impl true
  def handle_call({:insert, vector, metadata}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Generate node ID
    node_id = state.node_count
    
    # Randomly select layer based on exponential decay distribution
    level = select_level(state.ml)
    
    # Add timestamp to metadata if not present
    enhanced_metadata = Map.put_new(metadata, :inserted_at, DateTime.utc_now())
    
    # Store vector and metadata
    :ets.insert(state.data_table, {node_id, vector, enhanced_metadata})
    :ets.insert(state.level_table, {node_id, level})
    
    # Update graph structure
    new_state = 
      if state.entry_point == nil do
        # First insertion
        initialize_graph_node(state, node_id, level)
        %{state | entry_point: node_id, node_count: node_id + 1}
      else
        # Insert into existing graph
        insert_node(state, node_id, vector, level)
        %{state | node_count: node_id + 1}
      end
    
    # Emit telemetry event
    duration = System.monotonic_time(:microsecond) - start_time
    :telemetry.execute(
      [:hnsw, :insert],
      %{duration: duration, vector_size: length(vector)},
      %{node_id: node_id, level: level, m: state.m}
    )
    
    {:reply, {:ok, node_id}, new_state}
  end
  
  @impl true
  def handle_call({:search, query_vector, k, opts}, _from, state) do
    if state.entry_point == nil do
      {:reply, {:ok, []}, state}
    else
      start_time = System.monotonic_time(:microsecond)
      
      ef = opts[:ef] || state.ef
      
      # Perform hierarchical search from top layer to bottom
      results = hierarchical_search(state, query_vector, k, ef)
      
      # Format results with distances and metadata
      formatted_results = 
        results
        |> Enum.take(k)
        |> Enum.map(fn {dist, node_id} ->
          [{^node_id, vector, metadata}] = :ets.lookup(state.data_table, node_id)
          %{
            node_id: node_id,
            distance: dist,
            vector: vector,
            metadata: metadata
          }
        end)
      
      # Emit telemetry event
      duration = System.monotonic_time(:microsecond) - start_time
      :telemetry.execute(
        [:hnsw, :search],
        %{duration: duration, results_count: length(formatted_results)},
        %{k: k, ef: ef, vector_size: length(query_vector), m: state.m}
      )
      
      {:reply, {:ok, formatted_results}, state}
    end
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      node_count: state.node_count,
      entry_point: state.entry_point,
      m: state.m,
      ef: state.ef,
      memory_usage: calculate_memory_usage(state)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:persist, _from, state) do
    case state[:persist_path] do
      nil ->
        {:reply, {:error, :no_persist_path}, state}
      
      path ->
        alias AutonomousOpponentV2Core.VSM.S4.VectorStore.Persistence
        result = Persistence.save_index(path, state)
        {:reply, result, state}
    end
  end
  
  @impl true
  def handle_call({:load_from_disk, path}, _from, state) do
    alias AutonomousOpponentV2Core.VSM.S4.VectorStore.Persistence
    
    case Persistence.load_index(path) do
      {:ok, loaded_state} ->
        # Merge loaded state with current configuration
        new_state = Map.merge(state, loaded_state)
        {:reply, :ok, new_state}
      
      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:compact, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Compact the graph by removing orphaned nodes and optimizing connections
    {compacted_state, stats} = compact_graph(state)
    
    # Emit telemetry event
    duration = System.monotonic_time(:microsecond) - start_time
    :telemetry.execute(
      [:hnsw, :compact],
      %{duration: duration, removed_nodes: stats.removed_nodes, optimized_connections: stats.optimized_connections},
      %{node_count: state.node_count, m: state.m}
    )
    
    Logger.info("HNSW index compacted: removed #{stats.removed_nodes} nodes, optimized #{stats.optimized_connections} connections")
    
    {:reply, {:ok, stats}, compacted_state}
  end
  
  @impl true
  def handle_call({:search_batch, query_vectors, k, opts}, _from, state) when is_list(query_vectors) do
    if state.entry_point == nil do
      {:reply, {:ok, List.duplicate([], length(query_vectors))}, state}
    else
      start_time = System.monotonic_time(:microsecond)
      
      # Process queries in parallel
      max_concurrency = opts[:max_concurrency] || System.schedulers_online()
      timeout = opts[:timeout] || 5_000
      
      results = 
        query_vectors
        |> Enum.with_index()
        |> Task.async_stream(
          fn {query_vector, index} ->
            ef = opts[:ef] || state.ef
            search_results = hierarchical_search(state, query_vector, k, ef)
            
            formatted_results = 
              search_results
              |> Enum.take(k)
              |> Enum.map(fn {dist, node_id} ->
                [{^node_id, vector, metadata}] = :ets.lookup(state.data_table, node_id)
                %{
                  node_id: node_id,
                  distance: dist,
                  vector: vector,
                  metadata: metadata
                }
              end)
              
            {index, formatted_results}
          end,
          max_concurrency: max_concurrency,
          timeout: timeout,
          ordered: false
        )
        |> Enum.map(fn
          {:ok, {index, result}} -> {index, result}
          {:exit, :timeout} -> {nil, {:error, :timeout}}
        end)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(&elem(&1, 1))
      
      # Emit telemetry event
      duration = System.monotonic_time(:microsecond) - start_time
      :telemetry.execute(
        [:hnsw, :search_batch],
        %{duration: duration, batch_size: length(query_vectors)},
        %{k: k, ef: opts[:ef] || state.ef, max_concurrency: max_concurrency}
      )
      
      {:reply, {:ok, results}, state}
    end
  end
  
  @impl true
  def handle_call({:prune_old_patterns, max_age_ms}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Prune patterns older than max_age_ms
    {pruned_state, removed_count} = do_prune_old_patterns(state, max_age_ms)
    
    # Emit telemetry event
    duration = System.monotonic_time(:microsecond) - start_time
    :telemetry.execute(
      [:hnsw, :prune],
      %{duration: duration, removed_count: removed_count},
      %{max_age_ms: max_age_ms, remaining_nodes: pruned_state.node_count}
    )
    
    Logger.info("Pruned #{removed_count} old patterns from HNSW index")
    
    {:reply, {:ok, removed_count}, pruned_state}
  end
  
  @impl true
  def handle_info(:prune_tick, state) do
    # Perform periodic pruning
    {pruned_state, removed_count} = do_prune_old_patterns(state, state.prune_max_age)
    
    if removed_count > 0 do
      Logger.info("Periodic pruning removed #{removed_count} old patterns")
    end
    
    # Schedule next prune
    timer_ref = Process.send_after(self(), :prune_tick, state.prune_interval)
    
    {:noreply, %{pruned_state | prune_timer: timer_ref}}
  end
  
  @impl true
  def handle_info({:telemetry_event, _event_name, _measurements, _metadata}, state) do
    # Handle telemetry events silently - they're for monitoring
    {:noreply, state}
  end
  
  # Private Functions
  
  defp get_distance_function(:cosine), do: &cosine_distance/2
  defp get_distance_function(:euclidean), do: &euclidean_distance/2
  
  @doc false
  # WISDOM: Cosine distance = 1 - cosine_similarity
  # Measures angle between vectors, good for high-dimensional data
  def cosine_distance(v1, v2) do
    dot_product = dot(v1, v2)
    norm1 = :math.sqrt(dot(v1, v1))
    norm2 = :math.sqrt(dot(v2, v2))
    
    if norm1 == 0 or norm2 == 0 do
      1.0
    else
      1.0 - (dot_product / (norm1 * norm2))
    end
  end
  
  @doc false
  # WISDOM: Euclidean distance - straight-line distance
  # Good for dense vectors where magnitude matters
  def euclidean_distance(v1, v2) do
    v1
    |> Enum.zip(v2)
    |> Enum.map(fn {a, b} -> :math.pow(a - b, 2) end)
    |> Enum.sum()
    |> :math.sqrt()
  end
  
  defp dot(v1, v2) do
    v1
    |> Enum.zip(v2)
    |> Enum.map(fn {a, b} -> a * b end)
    |> Enum.sum()
  end
  
  # WISDOM: Level selection follows exponential decay
  # Most nodes at level 0, exponentially fewer at higher levels
  # Creates hierarchical structure for efficient search
  defp select_level(ml) do
    level = floor(:math.log(1.0 - :rand.uniform()) * ml)
    max(0, -level)
  end
  
  defp initialize_graph_node(state, node_id, level) do
    # Initialize empty neighbor lists for each level
    for lc <- 0..level do
      :ets.insert(state.graph, {{node_id, lc}, []})
    end
  end
  
  defp insert_node(state, node_id, vector, level) do
    # Initialize neighbor lists
    initialize_graph_node(state, node_id, level)
    
    # Find nearest neighbors at all levels
    entry_points = 
      if level > get_node_level(state, state.entry_point) do
        # New node at higher level becomes entry point
        [state.entry_point]
      else
        search_layer(state, vector, state.entry_point, 1, 1)
        |> Enum.map(fn {_, id} -> id end)
      end
    
    # Insert at each level from top to bottom
    Enum.reduce(level..0//-1, entry_points, fn lc, current_entry_points ->
      # Get M nearest neighbors at this level
      m = if lc == 0, do: state.max_m0, else: state.max_m
      
      candidates = search_layer_for_insertion(state, vector, current_entry_points, state.ef_construction, lc)
      m_nearest = get_m_nearest(candidates, m)
      
      # Add bidirectional links
      for {_, neighbor_id} <- m_nearest do
        add_connection(state, node_id, neighbor_id, lc)
        add_connection(state, neighbor_id, node_id, lc)
        
        # Prune neighbor's connections if needed
        prune_connections(state, neighbor_id, lc)
      end
      
      # Return entry points for next level
      Enum.map(m_nearest, fn {_, id} -> id end)
    end)
  end
  
  # WISDOM: Hierarchical search traverses from top layer down
  # Each layer provides coarse-to-fine approximation
  defp hierarchical_search(state, query, k, ef) do
    entry_level = get_node_level(state, state.entry_point)
    
    # If entry point is at level 0, just search that level
    if entry_level == 0 do
      search_layer_with_entries(state, query, [state.entry_point], k, ef, 0)
    else
      # Start from the top layer and work down
      {entry_points, _} = Enum.reduce(entry_level..1//-1, {[state.entry_point], MapSet.new()}, fn level, {current_entry_points, _visited} ->
        # Search at this level with entry points from previous level
        candidates = search_layer_with_entries(state, query, current_entry_points, 1, ef, level)
        
        # Use the best candidate as entry point for next level
        case candidates do
          [] -> {current_entry_points, MapSet.new()}
          [{_, best_id} | _] -> {[best_id], MapSet.new()}
        end
      end)
      
      # Final search at layer 0
      search_layer_with_entries(state, query, entry_points, k, ef, 0)
    end
  end
  
  defp search_layer_with_entries(state, query, entry_points, k, ef, level) do
    # Initialize WITHOUT marking entry points as visited yet
    visited = MapSet.new()
    
    candidates = entry_points
    |> Enum.map(fn ep ->
      [{_, ep_data, _}] = :ets.lookup(state.data_table, ep)
      {state.distance_fn.(query, ep_data), ep}
    end)
    
    w = candidates
    
    search_loop_at_level(state, query, candidates, w, visited, ef, level)
    |> Enum.sort()
    |> Enum.take(k)
  end
  
  # WISDOM: Search traverses from top layer down
  # Each layer provides coarse-to-fine approximation
  defp search_layer(state, query, entry_point, k, ef) do
    [{_, entry_data, _}] = :ets.lookup(state.data_table, entry_point)
    
    # Start with entry point (NOT marked as visited yet)
    visited = MapSet.new()
    candidates = [{state.distance_fn.(query, entry_data), entry_point}]
    w = candidates
    
    search_loop(state, query, candidates, w, visited, ef)
    |> Enum.sort()
    |> Enum.take(k)
  end
  
  defp search_loop_at_level(state, query, candidates, w, visited, ef, level) do
    case get_nearest_unvisited(candidates, visited) do
      nil -> 
        w
      
      {curr_dist, current} ->
        # Mark current node as visited
        new_visited = MapSet.put(visited, current)
        
        # Check if we should stop searching
        furthest = get_furthest_distance(w)
        if curr_dist > furthest and length(w) >= ef do
          w
        else
          # Get neighbors at the specified level
          neighbors = get_neighbors(state, current, level)
          
          # Evaluate unvisited neighbors
          {new_candidates, new_w, final_visited} = 
            evaluate_neighbors(state, query, neighbors, candidates, w, new_visited, ef)
          
          search_loop_at_level(state, query, new_candidates, new_w, final_visited, ef, level)
        end
    end
  end
  
  defp search_loop(state, query, candidates, w, visited, ef) do
    case get_nearest_unvisited(candidates, visited) do
      nil -> 
        w
      
      {curr_dist, current} ->
        # Mark current node as visited
        new_visited = MapSet.put(visited, current)
        
        # Check if we should stop searching
        furthest = get_furthest_distance(w)
        if curr_dist > furthest and length(w) >= ef do
          w
        else
          # Get neighbors
          neighbors = get_neighbors(state, current, 0)
          
          # Evaluate unvisited neighbors
          {new_candidates, new_w, final_visited} = 
            evaluate_neighbors(state, query, neighbors, candidates, w, new_visited, ef)
          
          search_loop(state, query, new_candidates, new_w, final_visited, ef)
        end
    end
  end
  
  defp search_layer_for_insertion(state, query, entry_points, ef, level) do
    # Similar to search_layer but for specific level during insertion
    visited = MapSet.new()  # Don't mark entry points as visited yet
    
    candidates = 
      entry_points
      |> Enum.map(fn ep ->
        [{_, ep_data, _}] = :ets.lookup(state.data_table, ep)
        {state.distance_fn.(query, ep_data), ep}
      end)
    
    w = candidates
    
    insertion_search_loop(state, query, candidates, w, visited, ef, level)
  end
  
  defp insertion_search_loop(state, query, candidates, w, visited, ef, level) do
    case get_nearest_unvisited(candidates, visited) do
      nil -> 
        w
      
      {curr_dist, current} ->
        # Mark current node as visited
        new_visited = MapSet.put(visited, current)
        
        if curr_dist > get_furthest_distance(w) and length(w) >= ef do
          w
        else
          neighbors = get_neighbors(state, current, level)
          
          {new_candidates, new_w, final_visited} = 
            evaluate_neighbors(state, query, neighbors, candidates, w, new_visited, ef)
          
          insertion_search_loop(state, query, new_candidates, new_w, final_visited, ef, level)
        end
    end
  end
  
  defp evaluate_neighbors(state, query, neighbors, candidates, w, visited, ef) do
    Enum.reduce(neighbors, {candidates, w, visited}, fn neighbor, {cands, w_acc, vis} ->
      if MapSet.member?(vis, neighbor) do
        {cands, w_acc, vis}
      else
        [{_, neighbor_data, _}] = :ets.lookup(state.data_table, neighbor)
        dist = state.distance_fn.(query, neighbor_data)
        
        new_vis = MapSet.put(vis, neighbor)
        
        # WISDOM: Only keep ef closest candidates
        # Prevents unbounded memory growth during search
        if dist < get_furthest_distance(w_acc) or length(w_acc) < ef do
          new_cands = [{dist, neighbor} | cands] |> Enum.sort() |> Enum.take(ef)
          new_w = [{dist, neighbor} | w_acc] |> Enum.sort() |> Enum.take(ef)
          {new_cands, new_w, new_vis}
        else
          {cands, w_acc, new_vis}
        end
      end
    end)
  end
  
  defp get_neighbors(state, node_id, level) do
    case :ets.lookup(state.graph, {node_id, level}) do
      [{_, neighbors}] -> neighbors
      [] -> []
    end
  end
  
  defp add_connection(state, from, to, level) do
    neighbors = get_neighbors(state, from, level)
    unless to in neighbors do
      :ets.insert(state.graph, {{from, level}, [to | neighbors]})
    end
  end
  
  # WISDOM: Connection pruning maintains bounded degree
  # Prevents "hub" nodes that slow down search
  defp prune_connections(state, node_id, level) do
    neighbors = get_neighbors(state, node_id, level)
    m = if level == 0, do: state.max_m0, else: state.max_m
    
    if length(neighbors) > m do
      # Keep only M closest neighbors
      [{_, node_data, _}] = :ets.lookup(state.data_table, node_id)
      
      pruned = 
        neighbors
        |> Enum.map(fn n ->
          [{_, n_data, _}] = :ets.lookup(state.data_table, n)
          {state.distance_fn.(node_data, n_data), n}
        end)
        |> Enum.sort()
        |> Enum.take(m)
        |> Enum.map(fn {_, n} -> n end)
      
      :ets.insert(state.graph, {{node_id, level}, pruned})
    end
  end
  
  defp get_m_nearest(candidates, m) do
    candidates
    |> Enum.sort()
    |> Enum.take(m)
  end
  
  defp get_nearest_unvisited(candidates, visited) do
    candidates
    |> Enum.sort()
    |> Enum.find(fn {_, id} -> not MapSet.member?(visited, id) end)
  end
  
  defp get_furthest_distance([]), do: :infinity
  defp get_furthest_distance(w) do
    w
    |> Enum.map(fn {dist, _} -> dist end)
    |> Enum.max()
  end
  
  defp get_node_level(state, node_id) do
    case :ets.lookup(state.level_table, node_id) do
      [{_, level}] -> level
      [] -> 0
    end
  end
  
  defp calculate_memory_usage(state) do
    %{
      graph_size: :ets.info(state.graph, :memory) * :erlang.system_info(:wordsize),
      data_size: :ets.info(state.data_table, :memory) * :erlang.system_info(:wordsize),
      level_size: :ets.info(state.level_table, :memory) * :erlang.system_info(:wordsize)
    }
  end
  
  # WISDOM: Graph compaction removes orphaned nodes and optimizes connections
  # This prevents memory bloat and maintains search performance
  defp compact_graph(state) do
    # Find all active nodes (those with connections or as entry point)
    active_nodes = find_active_nodes(state)
    orphaned_nodes = MapSet.new(0..(state.node_count - 1)) |> MapSet.difference(active_nodes)
    
    # Count optimized connections
    optimized_count = optimize_connections(state)
    
    stats = %{
      removed_nodes: MapSet.size(orphaned_nodes),
      optimized_connections: optimized_count,
      total_nodes: state.node_count
    }
    
    # Remove orphaned nodes from tables
    Enum.each(orphaned_nodes, fn node_id ->
      :ets.delete(state.data_table, node_id)
      :ets.delete(state.level_table, node_id)
      
      # Remove from graph at all levels
      max_level = get_node_level(state, node_id)
      for level <- 0..max_level do
        :ets.delete(state.graph, {node_id, level})
      end
    end)
    
    {state, stats}
  end
  
  defp find_active_nodes(state) do
    # Start with entry point
    active = if state.entry_point, do: MapSet.new([state.entry_point]), else: MapSet.new()
    
    # Add all nodes that have connections
    :ets.foldl(
      fn {{node_id, _level}, neighbors}, acc ->
        # Add node and its neighbors
        acc
        |> MapSet.put(node_id)
        |> MapSet.union(MapSet.new(neighbors))
      end,
      active,
      state.graph
    )
  end
  
  defp optimize_connections(state) do
    # Count nodes with excessive connections that were pruned
    optimized = 0
    
    :ets.foldl(
      fn {{node_id, level}, neighbors}, count ->
        m = if level == 0, do: state.max_m0, else: state.max_m
        
        if length(neighbors) > m * 1.5 do
          # Re-prune connections for over-connected nodes
          prune_connections(state, node_id, level)
          count + 1
        else
          count
        end
      end,
      optimized,
      state.graph
    )
  end
  
  # WISDOM: Pattern expiry removes old patterns based on timestamp
  # Keeps the index focused on recent, relevant patterns
  defp do_prune_old_patterns(state, max_age_ms) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -max_age_ms, :millisecond)
    
    removed_nodes = 
      :ets.foldl(
        fn {node_id, _vector, metadata}, acc ->
          case Map.get(metadata, :inserted_at) do
            nil -> 
              # Keep patterns without timestamp
              acc
              
            inserted_at ->
              if DateTime.compare(inserted_at, cutoff_time) == :lt do
                [node_id | acc]
              else
                acc
              end
          end
        end,
        [],
        state.data_table
      )
    
    # Remove expired nodes
    Enum.each(removed_nodes, fn node_id ->
      # Remove from data and level tables
      :ets.delete(state.data_table, node_id)
      :ets.delete(state.level_table, node_id)
      
      # Remove from graph and update neighbors
      max_level = get_node_level(state, node_id)
      for level <- 0..max_level do
        neighbors = get_neighbors(state, node_id, level)
        :ets.delete(state.graph, {node_id, level})
        
        # Remove this node from its neighbors' connections
        Enum.each(neighbors, fn neighbor ->
          neighbor_connections = get_neighbors(state, neighbor, level)
          updated_connections = List.delete(neighbor_connections, node_id)
          :ets.insert(state.graph, {{neighbor, level}, updated_connections})
        end)
      end
    end)
    
    # Update entry point if it was removed
    new_state = if state.entry_point in removed_nodes do
      # Find new entry point from remaining nodes
      new_entry = find_highest_level_node(state)
      %{state | entry_point: new_entry}
    else
      state
    end
    
    {new_state, length(removed_nodes)}
  end
  
  defp find_highest_level_node(state) do
    # Find node with highest level to use as new entry point
    :ets.foldl(
      fn {node_id, level}, {best_node, best_level} ->
        if level > best_level do
          {node_id, level}
        else
          {best_node, best_level}
        end
      end,
      {nil, -1},
      state.level_table
    ) |> elem(0)
  end
  
end