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
    :prune_max_age,
    :persist_timer,
    :persist_interval,
    # VSM-aware configuration
    :persist_on_shutdown,
    :persist_async,
    :max_patterns,
    :pattern_confidence_threshold,
    :variety_pressure_limit,
    :pain_pattern_retention,
    :eventbus_integration,
    :circuitbreaker_protection,
    :telemetry_enabled,
    :algedonic_integration,
    :backup_retention,
    :corruption_recovery,
    # Adaptive persistence tracking
    :insertion_count,
    :insertion_window_start,
    :adaptive_persist_enabled
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
    * `:persist_interval` - Milliseconds between automatic saves (optional)
    * `:prune_interval` - Milliseconds between automatic pruning (optional)
    * `:prune_max_age` - Max age in ms for patterns before pruning (optional)
  
  Example with automatic persistence and pruning:
      {:ok, index} = HNSWIndex.start_link(
        persist_path: "priv/hnsw_index",
        persist_interval: :timer.minutes(5),
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
  Get recent patterns from the index.
  
  Returns the most recently added patterns with their metadata.
  
  ## Options
    * `:limit` - Maximum number of patterns to return
  
  Returns {:ok, [{pattern_id, metadata}]} or {:error, reason}.
  """
  def get_recent_patterns(server \\ __MODULE__, limit) when is_integer(limit) and limit > 0 do
    GenServer.call(server, {:get_recent_patterns, limit})
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
    # Load configuration from application environment with VSM-aware defaults
    config = Application.get_all_env(:autonomous_opponent_core)
    
    m = opts[:m] || config[:hnsw_m] || @default_m
    ef = opts[:ef] || config[:hnsw_ef] || @default_ef
    
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
    
    # Load VSM-aware configuration with fallbacks
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
      # Core persistence configuration
      persist_path: opts[:persist_path] || config[:hnsw_persist_path],
      persist_interval: opts[:persist_interval] || config[:hnsw_persist_interval] || :timer.minutes(5),
      persist_on_shutdown: opts[:persist_on_shutdown] || config[:hnsw_persist_on_shutdown] || true,
      persist_async: opts[:persist_async] || config[:hnsw_persist_async] || true,
      # Pattern management
      prune_interval: opts[:prune_interval] || config[:hnsw_prune_interval] || :timer.hours(1),
      prune_max_age: opts[:prune_max_age] || config[:hnsw_prune_max_age] || :timer.hours(24),
      max_patterns: opts[:max_patterns] || config[:hnsw_max_patterns] || 100_000,
      pattern_confidence_threshold: opts[:pattern_confidence_threshold] || config[:hnsw_pattern_confidence_threshold] || 0.7,
      variety_pressure_limit: opts[:variety_pressure_limit] || config[:hnsw_variety_pressure_limit] || 0.8,
      pain_pattern_retention: opts[:pain_pattern_retention] || config[:hnsw_pain_pattern_retention] || (7 * 24 * 60 * 60 * 1000),
      # VSM integration
      eventbus_integration: opts[:eventbus_integration] || config[:hnsw_eventbus_integration] || true,
      circuitbreaker_protection: opts[:circuitbreaker_protection] || config[:hnsw_circuitbreaker_protection] || true,
      telemetry_enabled: opts[:telemetry_enabled] || config[:hnsw_telemetry_enabled] || true,
      algedonic_integration: opts[:algedonic_integration] || config[:hnsw_algedonic_integration] || true,
      # Reliability
      backup_retention: opts[:backup_retention] || config[:hnsw_backup_retention] || 3,
      corruption_recovery: opts[:corruption_recovery] || config[:hnsw_corruption_recovery] || true,
      # Adaptive persistence tracking
      insertion_count: 0,
      insertion_window_start: System.monotonic_time(:millisecond),
      adaptive_persist_enabled: opts[:adaptive_persist_enabled] || config[:hnsw_adaptive_persist_enabled] || true
    }
    
    # Validate configuration before proceeding
    case validate_config(state) do
      :ok -> 
        :ok
      {:error, reason} ->
        Logger.error("🧠 VSM S4: Invalid HNSW configuration: #{reason}")
        raise ArgumentError, "Invalid HNSW configuration: #{reason}"
    end
    
    # Restore from persistence if path provided and file exists
    final_state = if state.persist_path do
      alias AutonomousOpponentV2Core.VSM.S4.VectorStore.Persistence
      
      if Persistence.index_exists?(state.persist_path) do
        case Persistence.load_index(state.persist_path) do
          {:ok, loaded_state} ->
            Logger.info("🧠 VSM S4: Restored HNSW index from #{state.persist_path} (#{loaded_state[:node_count] || 0} patterns)")
            
            # Publish EventBus event if integration enabled
            if state.eventbus_integration do
              publish_eventbus_event(:hnsw_restoration_completed, %{
                patterns_loaded: loaded_state[:node_count] || 0,
                path: state.persist_path
              })
            end
            
            Map.merge(state, loaded_state)
          
          {:error, reason} ->
            Logger.warning("🧠 VSM S4: Failed to restore index: #{inspect(reason)}, starting fresh")
            
            if state.eventbus_integration do
              publish_eventbus_event(:hnsw_restoration_failed, %{
                reason: reason,
                path: state.persist_path
              })
            end
            
            state
        end
      else
        state
      end
    else
      state
    end
    
    Logger.info("🧠 VSM S4 Intelligence: HNSW index initialized with M=#{m}, ef=#{ef}, persistence=#{!!state.persist_path}")
    
    # Schedule periodic pruning if configured
    final_state_with_timers = final_state
    
    # Wrap timer creation in try/rescue to ensure cleanup on error
    try do
      final_state_with_timers = 
        if final_state_with_timers.prune_interval && final_state_with_timers.prune_max_age do
          timer_ref = Process.send_after(self(), :prune_tick, final_state_with_timers.prune_interval)
          %{final_state_with_timers | prune_timer: timer_ref}
        else
          final_state_with_timers
        end
      
      # Schedule periodic persistence if configured
      final_state_with_timers = 
        if final_state_with_timers.persist_interval && final_state_with_timers.persist_path do
          timer_ref = Process.send_after(self(), :persist_tick, final_state_with_timers.persist_interval)
          %{final_state_with_timers | persist_timer: timer_ref}
        else
          final_state_with_timers
        end
      
      {:ok, final_state_with_timers}
    rescue
      e ->
        # Cancel any created timers to prevent leaks
        if final_state_with_timers.prune_timer, do: Process.cancel_timer(final_state_with_timers.prune_timer)
        if final_state_with_timers.persist_timer, do: Process.cancel_timer(final_state_with_timers.persist_timer)
        
        Logger.error("🧠 VSM S4: Failed to initialize HNSW timers: #{inspect(e)}")
        reraise e, __STACKTRACE__
    end
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
    
    # Update insertion tracking for adaptive persistence
    new_state_with_tracking = %{new_state | insertion_count: new_state.insertion_count + 1}
    
    # Emit telemetry event
    duration = System.monotonic_time(:microsecond) - start_time
    :telemetry.execute(
      [:hnsw, :insert],
      %{duration: duration, vector_size: length(vector)},
      %{node_id: node_id, level: level, m: state.m}
    )
    
    {:reply, {:ok, node_id}, new_state_with_tracking}
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
      
      # Publish pattern detection events for high-confidence results
      if state.eventbus_integration && length(formatted_results) > 0 do
        Enum.each(formatted_results, fn result ->
          # Only publish patterns with high similarity (low distance)
          if result.distance < 0.3 do  # Threshold for significant patterns
            pattern_data = Map.merge(result.metadata || %{}, %{
              type: :vector_pattern_match,
              pattern_type: result.metadata[:pattern_type] || :similarity_match,
              source: :s4_hnsw_search,
              confidence: 1.0 - result.distance,  # Convert distance to confidence
              timestamp: DateTime.utc_now(),
              vector_distance: result.distance,
              node_id: result.node_id
            })
            
            publish_eventbus_event(:pattern_detected, pattern_data)
          end
        end)
      end
      
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
    result = persist_index(state)
    {:reply, result, state}
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
      
      # Publish pattern detection events for high-confidence results from batch
      if state.eventbus_integration do
        Enum.each(results, fn batch_results ->
          if is_list(batch_results) do
            Enum.each(batch_results, fn result ->
              # Only publish patterns with high similarity (low distance)
              if result.distance < 0.3 do  # Threshold for significant patterns
                pattern_data = Map.merge(result.metadata || %{}, %{
                  type: :vector_pattern_match,
                  pattern_type: result.metadata[:pattern_type] || :similarity_match,
                  source: :s4_hnsw_batch_search,
                  confidence: 1.0 - result.distance,
                  timestamp: DateTime.utc_now(),
                  vector_distance: result.distance,
                  node_id: result.node_id
                })
                
                publish_eventbus_event(:pattern_detected, pattern_data)
              end
            end)
          end
        end)
      end
      
      {:reply, {:ok, results}, state}
    end
  end
  
  @impl true
  def handle_call({:get_recent_patterns, limit}, _from, state) do
    # Get recent patterns sorted by insertion time
    recent_patterns = state.nodes
    |> Map.to_list()
    |> Enum.filter(fn {_id, %{metadata: metadata}} -> 
      Map.has_key?(metadata, :timestamp) or Map.has_key?(metadata, :inserted_at)
    end)
    |> Enum.sort_by(fn {_id, %{metadata: metadata}} ->
      # Use timestamp or inserted_at, whichever is available
      timestamp = Map.get(metadata, :timestamp, Map.get(metadata, :inserted_at, DateTime.utc_now()))
      # Convert to unix timestamp for sorting
      case timestamp do
        %DateTime{} -> DateTime.to_unix(timestamp, :microsecond)
        _ -> 0
      end
    end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {id, %{metadata: metadata}} -> {id, metadata} end)
    
    {:reply, {:ok, recent_patterns}, state}
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
  def handle_info(:persist_tick, state) do
    # Perform periodic persistence with VSM-aware protection
    persist_result = if state.persist_async do
      # Async persistence to avoid blocking S4 operations
      Task.start(fn -> 
        persist_with_protection(state)
      end)
      :ok
    else
      persist_with_protection(state)
    end
    
    case persist_result do
      :ok ->
        Logger.debug("🧠 VSM S4: HNSW index automatically persisted (#{state.node_count} patterns)")
        
        # Publish EventBus event for S5 governance awareness
        if state.eventbus_integration do
          publish_eventbus_event(:hnsw_persistence_completed, %{
            pattern_count: state.node_count,
            memory_usage: calculate_memory_usage(state),
            variety_pressure: calculate_variety_pressure(state)
          })
        end
        
      {:error, reason} ->
        Logger.error("🧠 VSM S4: Failed to persist HNSW index: #{inspect(reason)}")
        
        # Publish algedonic pain signal for critical persistence failures
        if state.algedonic_integration do
          publish_algedonic_signal(:pain, 0.7, :s4_persistence_failure, %{
            reason: reason,
            pattern_count: state.node_count
          })
        end
    end
    
    # Calculate adaptive interval based on insertion rate
    {next_interval, updated_state} = calculate_adaptive_interval(state)
    
    # Schedule next persist with adaptive interval
    timer_ref = Process.send_after(self(), :persist_tick, next_interval)
    
    {:noreply, %{updated_state | persist_timer: timer_ref}}
  end
  
  @impl true
  def handle_info({:telemetry_event, _event_name, _measurements, _metadata}, state) do
    # Handle telemetry events silently - they're for monitoring
    {:noreply, state}
  end
  
  @impl true
  def terminate(reason, state) do
    # Cancel timers
    if state.prune_timer, do: Process.cancel_timer(state.prune_timer)
    if state.persist_timer, do: Process.cancel_timer(state.persist_timer)
    
    # Perform final persistence on graceful shutdown if enabled
    if state.persist_on_shutdown and reason in [:normal, :shutdown] and state.persist_path do
      case persist_with_protection(state) do
        :ok ->
          Logger.info("🧠 VSM S4: HNSW index persisted on shutdown (#{state.node_count} patterns)")
          
          # Publish final EventBus event
          if state.eventbus_integration do
            publish_eventbus_event(:hnsw_shutdown_persistence_completed, %{
              pattern_count: state.node_count,
              shutdown_reason: reason
            })
          end
          
        {:error, error} ->
          Logger.error("🧠 VSM S4: Failed to persist HNSW index on shutdown: #{inspect(error)}")
          
          # Critical algedonic pain - losing patterns is a severe VSM failure
          if state.algedonic_integration do
            publish_algedonic_signal(:pain, 0.9, :s4_shutdown_persistence_failure, %{
              reason: error,
              pattern_count: state.node_count,
              variety_loss: :critical
            })
          end
      end
    end
    
    :ok
  end
  
  # Private Functions
  
  # ============================================================================
  # VSM-AWARE PERSISTENCE WITH CYBERNETIC PROTECTION
  # ============================================================================
  
  defp persist_with_protection(state) do
    if state.circuitbreaker_protection do
      # Use CircuitBreaker to protect against persistence storms
      try do
        case AutonomousOpponentV2Core.CircuitBreaker.call(:hnsw_persistence, fn ->
          persist_index_internal(state)
        end) do
          {:error, :open} ->
            Logger.warning("🧠 VSM S4: CircuitBreaker is open, skipping persistence")
            {:error, :circuit_open}
          result ->
            result
        end
      rescue
        e ->
          Logger.error("🧠 VSM S4: CircuitBreaker failed for persistence: #{inspect(e)}")
          {:error, {:circuitbreaker_failed, e}}
      end
    else
      persist_index_internal(state)
    end
  end
  
  defp persist_index(state) do
    persist_index_internal(state)
  end
  
  defp persist_index_internal(state) do
    # Define variables outside if block so they're accessible in rescue
    start_time = System.monotonic_time(:millisecond)
    variety_pressure = calculate_variety_pressure(state)
    
    if state.persist_path do
      alias AutonomousOpponentV2Core.VSM.S4.VectorStore.Persistence
      
      try do
        
        if variety_pressure > state.variety_pressure_limit do
          Logger.warning("🧠 VSM S4: High variety pressure (#{variety_pressure}), triggering emergency cleanup")
          
          # Emergency pattern pruning to manage variety overflow
          emergency_prune_patterns(state)
        end
        
        # Publish EventBus event for persistence start
        if state.eventbus_integration do
          publish_eventbus_event(:hnsw_persistence_started, %{
            pattern_count: state.node_count,
            variety_pressure: variety_pressure,
            path: state.persist_path
          })
        end
        
        case Persistence.save_index(state.persist_path, state) do
          :ok -> 
            # Calculate persistence metrics
            duration_ms = System.monotonic_time(:millisecond) - start_time
            
            # Get file size if file exists
            file_size = case File.stat(state.persist_path) do
              {:ok, %{size: size}} -> size
              _ -> 0
            end
            
            # Calculate memory usage
            memory_usage = calculate_memory_usage(state)
            
            # Emit comprehensive telemetry if enabled
            if state.telemetry_enabled do
              :telemetry.execute(
                [:hnsw, :persistence, :completed],
                %{
                  duration_ms: duration_ms,
                  file_size_bytes: file_size,
                  pattern_count: state.node_count,
                  variety_pressure: variety_pressure,
                  memory_usage_bytes: memory_usage,
                  insertion_rate: calculate_insertion_rate(state)
                },
                %{
                  path: state.persist_path,
                  adaptive_interval: state.adaptive_persist_enabled,
                  async: state.persist_async
                }
              )
              
              Logger.debug("🧠 VSM S4: Persistence completed in #{duration_ms}ms, " <>
                          "file size: #{div(file_size, 1_048_576)}MB, " <>
                          "patterns: #{state.node_count}")
            end
            :ok
            
          {:error, _} = error -> error
        end
      rescue
        e ->
          Logger.error("🧠 VSM S4: Failed to persist HNSW index: #{inspect(e)}")
          
          # Emit telemetry for persistence failure
          if state.telemetry_enabled do
            duration_ms = System.monotonic_time(:millisecond) - start_time
            
            :telemetry.execute(
              [:hnsw, :persistence, :failed],
              %{
                duration_ms: duration_ms,
                pattern_count: state.node_count,
                variety_pressure: variety_pressure
              },
              %{
                path: state.persist_path,
                error: inspect(e)
              }
            )
          end
          
          {:error, {:persistence_failed, e}}
      end
    else
      {:error, :no_persist_path}
    end
  end
  
  # ============================================================================
  # VSM VARIETY ENGINEERING FUNCTIONS
  # ============================================================================
  
  defp calculate_variety_pressure(state) do
    if state.max_patterns > 0 do
      state.node_count / state.max_patterns
    else
      0.0
    end
  end
  
  defp emergency_prune_patterns(state) do
    try do
      # Emergency pruning based on pattern confidence and age
      cutoff_time = DateTime.add(DateTime.utc_now(), -div(state.prune_max_age, 2), :millisecond)
      
      removed_nodes = 
        :ets.foldl(
          fn {node_id, _vector, metadata}, acc ->
            confidence = Map.get(metadata, :confidence, 1.0)
            inserted_at = Map.get(metadata, :inserted_at)
            
            # Remove low-confidence patterns or old patterns
            should_remove = 
              confidence < state.pattern_confidence_threshold or
              (inserted_at && DateTime.compare(inserted_at, cutoff_time) == :lt)
            
            if should_remove do
              [node_id | acc]
            else
              acc
            end
          end,
          [],
          state.data_table
        )
      
      # Remove the patterns
      Enum.each(removed_nodes, &remove_pattern_from_index(state, &1))
      
      Logger.warning("🧠 VSM S4: Emergency pruned #{length(removed_nodes)} patterns to manage variety overflow")
      
      if state.algedonic_integration and length(removed_nodes) > 0 do
        publish_algedonic_signal(:pain, 0.6, :s4_emergency_pruning, %{
          removed_count: length(removed_nodes),
          variety_pressure: calculate_variety_pressure(state)
        })
      end
    rescue
      e ->
        Logger.error("🧠 VSM S4: Emergency pruning failed: #{inspect(e)}")
        
        # Still publish algedonic pain signal for pruning failure (higher pain level)
        if state.algedonic_integration do
          publish_algedonic_signal(:pain, 0.9, :s4_emergency_pruning_failure, %{
            error: inspect(e),
            variety_pressure: calculate_variety_pressure(state)
          })
        end
    end
  end
  
  defp remove_pattern_from_index(state, node_id) do
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
  end
  
  # ============================================================================
  # VSM EVENTBUS INTEGRATION
  # ============================================================================
  
  defp publish_eventbus_event(event_type, data) do
    try do
      AutonomousOpponentV2Core.EventBus.publish(:s4_intelligence, %{
        type: event_type,
        subsystem: :s4_hnsw,
        data: data,
        timestamp: DateTime.utc_now(),
        hlc_timestamp: generate_hlc_timestamp()
      })
    rescue
      e ->
        Logger.warning("🧠 VSM S4: Failed to publish EventBus event: #{inspect(e)}")
    end
  end
  
  defp publish_algedonic_signal(signal_type, intensity, source, metadata) do
    try do
      AutonomousOpponentV2Core.EventBus.publish(:algedonic_signals, %{
        type: signal_type,
        intensity: intensity,
        source: source,
        subsystem: :s4_intelligence,
        metadata: metadata,
        timestamp: DateTime.utc_now(),
        hlc_timestamp: generate_hlc_timestamp(),
        # VSM Algedonic properties
        urgency: if(intensity > 0.8, do: :immediate, else: :normal),
        bypass_hierarchy: intensity > 0.9,
        target: :s5_governance
      })
    rescue
      e ->
        Logger.warning("🧠 VSM S4: Failed to publish algedonic signal: #{inspect(e)}")
    end
  end
  
  defp generate_hlc_timestamp do
    # Generate HLC timestamp for distributed consistency
    %{
      physical: System.system_time(:millisecond),
      logical: :rand.uniform(1000),
      node_id: Node.self() |> to_string()
    }
  end
  
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
  
  # ============================================================================
  # PERSISTENCE METRICS HELPERS
  # ============================================================================
  
  defp calculate_insertion_rate(state) do
    current_time = System.monotonic_time(:millisecond)
    window_duration = current_time - state.insertion_window_start
    
    if window_duration > 0 do
      Float.round((state.insertion_count * 60_000) / window_duration, 1)
    else
      0.0
    end
  end
  
  # ============================================================================
  # ADAPTIVE PERSISTENCE INTERVALS
  # ============================================================================
  
  defp calculate_adaptive_interval(state) do
    if state.adaptive_persist_enabled do
      # Calculate time window in milliseconds
      current_time = System.monotonic_time(:millisecond)
      window_duration = current_time - state.insertion_window_start
      
      # Calculate insertions per minute
      insertions_per_minute = if window_duration > 0 do
        (state.insertion_count * 60_000) / window_duration
      else
        0.0
      end
      
      # Determine adaptive interval based on insertion rate
      adaptive_interval = cond do
        insertions_per_minute > 1000 ->
          # High rate: persist every minute
          :timer.minutes(1)
        
        insertions_per_minute > 100 ->
          # Medium rate: persist every 3 minutes
          :timer.minutes(3)
        
        true ->
          # Low rate: persist every 5 minutes
          :timer.minutes(5)
      end
      
      # Reset tracking window every hour
      updated_state = if window_duration > :timer.hours(1) do
        %{state | 
          insertion_count: 0,
          insertion_window_start: current_time
        }
      else
        state
      end
      
      # Log if interval changed significantly
      if adaptive_interval != state.persist_interval do
        Logger.info("🧠 VSM S4: Adjusted persistence interval to #{div(adaptive_interval, 60_000)} minutes " <>
                   "(insertion rate: #{Float.round(insertions_per_minute, 1)}/min)")
      end
      
      {adaptive_interval, updated_state}
    else
      # Use static interval when adaptive persistence is disabled
      {state.persist_interval, state}
    end
  end
  
  # ============================================================================
  # CONFIGURATION VALIDATION
  # ============================================================================
  
  defp validate_config(state) do
    cond do
      # Validate M parameter (bidirectional links)
      state.m < 2 or state.m > 200 ->
        {:error, "M parameter must be between 2 and 200, got #{state.m}"}
      
      # Validate ef parameter (search beam width)
      state.ef < state.m or state.ef > 2000 ->
        {:error, "ef parameter must be between M (#{state.m}) and 2000, got #{state.ef}"}
      
      # Validate persistence interval
      state.persist_interval && state.persist_interval < :timer.seconds(30) ->
        {:error, "persist_interval must be at least 30 seconds, got #{state.persist_interval}ms"}
      
      # Validate prune interval
      state.prune_interval && state.prune_interval < :timer.minutes(5) ->
        {:error, "prune_interval must be at least 5 minutes, got #{state.prune_interval}ms"}
      
      # Validate max patterns
      state.max_patterns < 1000 ->
        {:error, "max_patterns must be at least 1000, got #{state.max_patterns}"}
      
      # Validate variety pressure limit
      state.variety_pressure_limit <= 0.5 or state.variety_pressure_limit >= 1.0 ->
        {:error, "variety_pressure_limit must be between 0.5 and 1.0 (exclusive), got #{state.variety_pressure_limit}"}
      
      # Validate pattern confidence threshold
      state.pattern_confidence_threshold < 0.0 or state.pattern_confidence_threshold > 1.0 ->
        {:error, "pattern_confidence_threshold must be between 0.0 and 1.0, got #{state.pattern_confidence_threshold}"}
      
      # Validate backup retention
      state.backup_retention < 1 or state.backup_retention > 10 ->
        {:error, "backup_retention must be between 1 and 10, got #{state.backup_retention}"}
      
      # Validate pain pattern retention (at least 1 day)
      state.pain_pattern_retention < :timer.hours(24) ->
        {:error, "pain_pattern_retention must be at least 24 hours, got #{state.pain_pattern_retention}ms"}
      
      true ->
        :ok
    end
  end
  
end