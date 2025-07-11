defmodule AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge do
  @moduledoc """
  Bridge between Pattern Matching and HNSW Vector Indexing.
  
  This module connects the Goldrush pattern matcher to the HNSW vector index,
  enabling fast similarity search on matched patterns. It subscribes to pattern
  match events and automatically indexes them for future retrieval.
  
  ## Architecture Flow
  
  1. EventProcessor matches patterns → publishes :pattern_matched events
  2. PatternHNSWBridge receives events → converts patterns to vectors
  3. HNSW index stores vectors → enables similarity search
  4. S4 Intelligence queries similar patterns → improves predictions
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.PatternIndexer
  alias AutonomousOpponentV2Core.Core.Metrics
  
  defstruct [
    :hnsw_index,
    :pattern_indexer,
    :vector_dim,
    :pattern_buffer,
    :stats,
    :backpressure_active,
    :patterns_dropped,
    :last_backpressure_log,
    :pattern_cache,           # Recent patterns for deduplication
    :dedup_similarity_threshold
  ]
  
  @vector_dim 100
  @batch_size 10
  @batch_timeout 1000  # 1 second
  
  # Backpressure thresholds
  @max_buffer_size 100     # Maximum patterns in buffer before applying backpressure
  @max_lag_threshold 500   # Maximum difference between received and indexed
  @backpressure_log_interval 10_000  # Log backpressure status every 10 seconds
  
  # Deduplication settings
  @dedup_similarity_threshold 0.95  # Patterns with similarity > 0.95 are considered duplicates
  @pattern_cache_size 1000          # Keep last N patterns for fast dedup checks
  @cache_cleanup_interval 60_000    # Clean cache every minute
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  def get_stats(server \\ __MODULE__) do
    GenServer.call(server, :get_stats)
  end
  
  @doc """
  Get detailed monitoring information for HNSW pattern storage.
  
  Returns comprehensive metrics including:
  - Pattern processing statistics
  - HNSW index health and performance
  - Backpressure and deduplication metrics
  - System resource utilization
  """
  def get_monitoring_info(server \\ __MODULE__) do
    GenServer.call(server, :get_monitoring_info)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Get references to the HNSW index and pattern indexer (started by supervisor)
    hnsw_name = opts[:hnsw_name] || :hnsw_index
    indexer_name = opts[:indexer_name] || AutonomousOpponentV2Core.VSM.S4.PatternIndexer
    
    # Wait briefly for supervisor to start them
    Process.sleep(100)
    
    # Verify they're running
    unless Process.whereis(hnsw_name) do
      Logger.error("HNSW index not found: #{inspect(hnsw_name)}")
    end
    
    unless Process.whereis(indexer_name) do
      Logger.error("Pattern indexer not found: #{inspect(indexer_name)}")
    end
    
    state = %__MODULE__{
      hnsw_index: hnsw_name,
      pattern_indexer: indexer_name,
      vector_dim: @vector_dim,
      pattern_buffer: [],
      stats: %{
        patterns_received: 0,
        patterns_indexed: 0,
        indexing_errors: 0,
        patterns_deduplicated: 0,
        last_indexed_at: nil
      },
      backpressure_active: false,
      patterns_dropped: 0,
      last_backpressure_log: System.monotonic_time(:millisecond),
      pattern_cache: :queue.new(),
      dedup_similarity_threshold: opts[:dedup_similarity_threshold] || @dedup_similarity_threshold
    }
    
    # Subscribe to pattern match events
    EventBus.subscribe(:pattern_matched)
    EventBus.subscribe(:patterns_extracted)
    
    # Schedule batch processing
    schedule_batch_processing()
    
    # Schedule cache cleanup
    schedule_cache_cleanup()
    
    Logger.info("Pattern HNSW Bridge initialized - connecting pattern matching to vector indexing")
    
    {:ok, state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :pattern_matched} = event}, state) do
    # Handle pattern matched events from Goldrush
    pattern_data = extract_pattern_data(event.data)
    
    if pattern_data do
      # Update received count
      updated_stats = Map.update!(state.stats, :patterns_received, &(&1 + 1))
      state_with_stats = %{state | stats: updated_stats}
      
      # Check backpressure
      if should_apply_backpressure?(state_with_stats) do
        # Drop pattern and increment counter
        new_state = %{state_with_stats | 
          patterns_dropped: state.patterns_dropped + 1,
          backpressure_active: true
        }
        
        # Record metric
        Metrics.counter("vsm.s4.patterns_dropped", 1, %{reason: "backpressure"})
        
        # Maybe log backpressure status
        new_state = maybe_log_backpressure(new_state, true)
        
        {:noreply, new_state}
      else
        # Add to buffer for batch processing
        new_buffer = [pattern_data | state.pattern_buffer]
        new_state = %{state_with_stats | 
          pattern_buffer: new_buffer,
          backpressure_active: false
        }
        
        # Maybe log if backpressure was resolved
        new_state = if state.backpressure_active and not new_state.backpressure_active do
          maybe_log_backpressure(new_state, false)
        else
          new_state
        end
        
        # Process immediately if buffer is full
        if length(new_buffer) >= @batch_size do
          {:noreply, process_pattern_batch(new_state)}
        else
          {:noreply, new_state}
        end
      end
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :patterns_extracted} = event}, state) do
    # Handle bulk patterns from S4 Intelligence
    patterns = event.data[:patterns] || []
    
    valid_patterns = patterns
    |> Enum.map(&extract_pattern_data/1)
    |> Enum.filter(&(&1 != nil))
    
    if length(valid_patterns) > 0 do
      new_buffer = valid_patterns ++ state.pattern_buffer
      new_state = %{state |
        pattern_buffer: new_buffer,
        stats: Map.update!(state.stats, :patterns_received, &(&1 + length(valid_patterns)))
      }
      
      # Process immediately since we have bulk patterns
      {:noreply, process_pattern_batch(new_state)}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:process_batch, state) do
    # Periodic batch processing
    new_state = if length(state.pattern_buffer) > 0 do
      process_pattern_batch(state)
    else
      state
    end
    
    schedule_batch_processing()
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:cleanup_cache, state) do
    # Cleanup old patterns from cache to prevent unbounded growth
    cache_size = :queue.len(state.pattern_cache)
    
    new_cache = if cache_size > @pattern_cache_size do
      # Remove oldest patterns
      to_remove = cache_size - @pattern_cache_size
      Enum.reduce(1..to_remove, state.pattern_cache, fn _, cache ->
        case :queue.out(cache) do
          {{:value, _}, new_cache} -> new_cache
          {:empty, cache} -> cache
        end
      end)
    else
      state.pattern_cache
    end
    
    schedule_cache_cleanup()
    {:noreply, %{state | pattern_cache: new_cache}}
  end
  
  @impl true
  def handle_call({:query_patterns, vector, k}, _from, state) do
    # Query the HNSW index for similar patterns
    case HNSWIndex.search(state.hnsw_index, vector, k) do
      {:ok, results} ->
        # Transform results to include pattern data
        patterns = Enum.map(results, fn result ->
          # Handle both tuple and map formats
          case result do
            {pattern_id, distance} ->
              # Old format - simple tuple
              pattern = %{
                id: pattern_id,
                distance: distance,
                similarity: 1.0 - distance
              }
              {pattern, 1.0 - distance}
              
            %{metadata: metadata, distance: distance} ->
              # New format with metadata
              pattern = Map.merge(metadata, %{
                distance: distance,
                similarity: 1.0 - distance
              })
              {pattern, 1.0 - distance}
              
            _ ->
              # Unknown format
              Logger.warning("Unknown HNSW result format: #{inspect(result)}")
              {%{id: "unknown", distance: 1.0, similarity: 0.0}, 0.0}
          end
        end)
        
        {:reply, {:ok, patterns}, state}
        
      {:error, reason} ->
        Logger.error("Failed to query patterns: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      buffer_size: length(state.pattern_buffer),
      patterns_dropped: state.patterns_dropped,
      backpressure_active: state.backpressure_active,
      indexing_lag: state.stats.patterns_received - state.stats.patterns_indexed,
      cache_size: :queue.len(state.pattern_cache),
      dedup_threshold: state.dedup_similarity_threshold,
      hnsw_stats: get_hnsw_stats(state.hnsw_index),
      indexer_stats: get_indexer_stats(state.pattern_indexer)
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:get_monitoring_info, _from, state) do
    # Comprehensive monitoring information
    monitoring_info = %{
      # Pattern processing metrics
      pattern_metrics: %{
        total_received: state.stats.patterns_received,
        total_indexed: state.stats.patterns_indexed,
        total_deduplicated: state.stats.patterns_deduplicated,
        total_dropped: state.patterns_dropped,
        indexing_errors: state.stats.indexing_errors,
        last_indexed_at: state.stats.last_indexed_at,
        processing_rate: calculate_processing_rate(state),
        success_rate: calculate_success_rate(state)
      },
      
      # Backpressure monitoring
      backpressure: %{
        active: state.backpressure_active,
        buffer_size: length(state.pattern_buffer),
        buffer_utilization: length(state.pattern_buffer) / @max_buffer_size,
        indexing_lag: state.stats.patterns_received - state.stats.patterns_indexed,
        lag_utilization: (state.stats.patterns_received - state.stats.patterns_indexed) / @max_lag_threshold,
        thresholds: %{
          max_buffer_size: @max_buffer_size,
          max_lag: @max_lag_threshold
        }
      },
      
      # Deduplication monitoring
      deduplication: %{
        cache_size: :queue.len(state.pattern_cache),
        cache_utilization: :queue.len(state.pattern_cache) / @pattern_cache_size,
        similarity_threshold: state.dedup_similarity_threshold,
        dedup_rate: calculate_dedup_rate(state),
        cache_settings: %{
          max_size: @pattern_cache_size,
          cleanup_interval_ms: @cache_cleanup_interval
        }
      },
      
      # HNSW index monitoring
      hnsw: get_detailed_hnsw_stats(state.hnsw_index),
      
      # Pattern indexer monitoring
      indexer: get_detailed_indexer_stats(state.pattern_indexer),
      
      # System health
      health: %{
        status: determine_health_status(state),
        warnings: collect_warnings(state),
        recommendations: generate_recommendations(state)
      },
      
      # Configuration
      configuration: %{
        vector_dimensions: @vector_dim,
        batch_size: @batch_size,
        batch_timeout_ms: @batch_timeout,
        backpressure_log_interval_ms: @backpressure_log_interval
      }
    }
    
    {:reply, monitoring_info, state}
  end
  
  # Private Functions
  
  defp should_apply_backpressure?(state) do
    buffer_size = length(state.pattern_buffer)
    indexing_lag = state.stats.patterns_received - state.stats.patterns_indexed
    
    buffer_size > @max_buffer_size or indexing_lag > @max_lag_threshold
  end
  
  defp maybe_log_backpressure(state, is_dropping) do
    now = System.monotonic_time(:millisecond)
    
    if now - state.last_backpressure_log > @backpressure_log_interval do
      if is_dropping do
        Logger.warn("""
        Pattern HNSW Bridge backpressure active:
        - Buffer size: #{length(state.pattern_buffer)}/#{@max_buffer_size}
        - Indexing lag: #{state.stats.patterns_received - state.stats.patterns_indexed}/#{@max_lag_threshold}
        - Patterns dropped: #{state.patterns_dropped}
        """)
      else
        Logger.info("Pattern HNSW Bridge backpressure resolved")
      end
      
      %{state | last_backpressure_log: now}
    else
      state
    end
  end
  
  defp extract_pattern_data(%{pattern_id: id, match_context: context} = data) do
    %{
      id: id,
      pattern: data[:matched_event] || %{},
      context: context,
      confidence: context[:confidence] || 0.8,
      timestamp: data[:triggered_at] || DateTime.utc_now(),
      source: :pattern_matcher
    }
  end
  
  defp extract_pattern_data(%{type: type, confidence: confidence} = pattern) do
    %{
      id: generate_pattern_id(pattern),
      pattern: pattern,
      context: %{type: type},
      confidence: confidence,
      timestamp: pattern[:timestamp] || DateTime.utc_now(),
      source: :s4_intelligence
    }
  end
  
  defp extract_pattern_data(_), do: nil
  
  defp process_pattern_batch(state) do
    patterns_to_index = Enum.reverse(state.pattern_buffer)
    
    # Process patterns with deduplication
    {final_state, indexed_count, dedup_count} = 
      Enum.reduce(patterns_to_index, {state, 0, 0}, fn pattern, {acc_state, indexed, deduped} ->
        if is_duplicate_pattern?(pattern, acc_state) do
          # Pattern is duplicate, skip indexing
          Metrics.counter("vsm.s4.patterns_deduplicated", 1, %{source: to_string(pattern.source)})
          {acc_state, indexed, deduped + 1}
        else
          # Index the pattern
          case PatternIndexer.index_pattern(acc_state.pattern_indexer, pattern) do
            :ok ->
              # Record metric
              Metrics.counter("vsm.s4.patterns_indexed", 1, %{source: to_string(pattern.source)})
              # Add to cache for future deduplication
              new_state = add_to_pattern_cache(pattern, acc_state)
              {new_state, indexed + 1, deduped}
            error ->
              Logger.error("Failed to index pattern: #{inspect(error)}")
              Metrics.counter("vsm.s4.indexing_errors", 1)
              {acc_state, indexed, deduped}
          end
        end
      end)
    
    # Update stats
    new_stats = final_state.stats
    |> Map.update!(:patterns_indexed, &(&1 + indexed_count))
    |> Map.update!(:patterns_deduplicated, &(&1 + dedup_count))
    |> Map.update!(:indexing_errors, &(&1 + (length(patterns_to_index) - indexed_count - dedup_count)))
    |> Map.put(:last_indexed_at, DateTime.utc_now())
    
    # Publish indexing complete event
    if indexed_count > 0 do
      EventBus.publish(:patterns_indexed, %{
        count: indexed_count,
        deduplicated: dedup_count,
        source: :pattern_hnsw_bridge
      })
    end
    
    %{final_state | pattern_buffer: [], stats: new_stats}
  end
  
  defp schedule_batch_processing do
    Process.send_after(self(), :process_batch, @batch_timeout)
  end
  
  defp schedule_cache_cleanup do
    Process.send_after(self(), :cleanup_cache, @cache_cleanup_interval)
  end
  
  defp is_duplicate_pattern?(pattern, state) do
    # Check if pattern is duplicate using HNSW similarity search
    case PatternIndexer.pattern_to_vector(state.pattern_indexer, pattern) do
      {:ok, vector} ->
        # First check cache for exact matches
        cache_list = :queue.to_list(state.pattern_cache)
        
        # Quick check in cache using pattern ID
        pattern_id = generate_pattern_id(pattern)
        cache_has_exact = Enum.any?(cache_list, fn cached ->
          cached.id == pattern_id
        end)
        
        if cache_has_exact do
          true
        else
          # Check HNSW for similar patterns
          case HNSWIndex.search(state.hnsw_index, vector, 1) do
            {:ok, [{_id, distance}]} when distance > state.dedup_similarity_threshold ->
              # Very similar pattern found (cosine similarity > threshold)
              true
            _ ->
              false
          end
        end
        
      _ ->
        # If we can't convert to vector, assume not duplicate
        false
    end
  end
  
  defp add_to_pattern_cache(pattern, state) do
    # Add pattern to cache for future deduplication
    new_cache = :queue.in(pattern, state.pattern_cache)
    %{state | pattern_cache: new_cache}
  end
  
  defp generate_pattern_id(pattern) do
    # Generate unique ID with timestamp and random component for guaranteed uniqueness
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    random_bytes = :crypto.strong_rand_bytes(8)
    
    # Include pattern data for content-based component
    pattern_data = pattern
    |> Map.drop([:timestamp, :id])  # Exclude mutable fields
    |> :erlang.term_to_binary()
    
    # Combine all components
    combined = <<
      timestamp::64,
      random_bytes::binary,
      pattern_data::binary
    >>
    
    # Generate hash
    :crypto.hash(:sha256, combined)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 32)  # Use more characters for better uniqueness
  end
  
  defp get_hnsw_stats(hnsw_server) do
    try do
      HNSWIndex.stats(hnsw_server)
    rescue
      _ -> %{}
    end
  end
  
  defp get_indexer_stats(indexer_server) do
    try do
      PatternIndexer.stats(indexer_server)
    rescue
      _ -> %{}
    end
  end
  
  # Monitoring helper functions
  
  defp calculate_processing_rate(state) do
    # Calculate patterns per second over last minute
    if state.stats.last_indexed_at do
      time_diff = DateTime.diff(DateTime.utc_now(), state.stats.last_indexed_at)
      if time_diff > 0 do
        state.stats.patterns_indexed / time_diff
      else
        0.0
      end
    else
      0.0
    end
  end
  
  defp calculate_success_rate(state) do
    total_processed = state.stats.patterns_indexed + state.stats.indexing_errors
    if total_processed > 0 do
      state.stats.patterns_indexed / total_processed
    else
      1.0
    end
  end
  
  defp calculate_dedup_rate(state) do
    total_considered = state.stats.patterns_indexed + state.stats.patterns_deduplicated
    if total_considered > 0 do
      state.stats.patterns_deduplicated / total_considered
    else
      0.0
    end
  end
  
  defp get_detailed_hnsw_stats(hnsw_server) do
    try do
      stats = HNSWIndex.stats(hnsw_server)
      Map.merge(stats, %{
        health: if(stats[:size] > 0, do: :healthy, else: :empty),
        performance: %{
          avg_search_time_ms: stats[:avg_search_time] || 0.0,
          search_count: stats[:searches_performed] || 0,
          index_size: stats[:size] || 0
        }
      })
    rescue
      _ -> %{health: :unavailable}
    end
  end
  
  defp get_detailed_indexer_stats(indexer_server) do
    try do
      stats = PatternIndexer.stats(indexer_server)
      Map.merge(stats, %{
        health: :healthy,
        performance: %{
          patterns_indexed: stats[:patterns_indexed] || 0,
          avg_indexing_time_ms: stats[:avg_indexing_time] || 0.0
        }
      })
    rescue
      _ -> %{health: :unavailable}
    end
  end
  
  defp determine_health_status(state) do
    cond do
      state.backpressure_active -> :degraded
      state.stats.indexing_errors > state.stats.patterns_indexed * 0.1 -> :warning
      state.stats.patterns_indexed == 0 and state.stats.patterns_received > 0 -> :error
      true -> :healthy
    end
  end
  
  defp collect_warnings(state) do
    warnings = []
    
    warnings = if state.backpressure_active do
      ["Backpressure is active - patterns are being dropped" | warnings]
    else
      warnings
    end
    
    warnings = if state.stats.indexing_errors > 10 do
      ["High number of indexing errors: #{state.stats.indexing_errors}" | warnings]
    else
      warnings
    end
    
    warnings = if :queue.len(state.pattern_cache) > @pattern_cache_size * 0.9 do
      ["Pattern cache is near capacity" | warnings]
    else
      warnings
    end
    
    warnings
  end
  
  defp generate_recommendations(state) do
    recommendations = []
    
    recommendations = if state.backpressure_active do
      ["Consider increasing buffer size or processing resources" | recommendations]
    else
      recommendations
    end
    
    dedup_rate = calculate_dedup_rate(state)
    recommendations = if dedup_rate > 0.5 do
      ["High deduplication rate (#{Float.round(dedup_rate * 100, 1)}%) - consider adjusting similarity threshold" | recommendations]
    else
      recommendations
    end
    
    recommendations = if state.stats.indexing_errors > 0 do
      ["Investigate indexing errors in logs" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
end