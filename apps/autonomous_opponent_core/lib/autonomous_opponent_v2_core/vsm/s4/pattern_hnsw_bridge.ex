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
    :stats
  ]
  
  @vector_dim 100
  @batch_size 10
  @batch_timeout 1000  # 1 second
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  def get_stats(server \\ __MODULE__) do
    GenServer.call(server, :get_stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Start HNSW index if not already running
    hnsw_name = opts[:hnsw_name] || AutonomousOpponentV2Core.VSM.S4.HNSWIndex
    case Process.whereis(hnsw_name) do
      nil ->
        {:ok, _} = HNSWIndex.start_link(
          name: hnsw_name,
          m: 16,
          ef: 200,
          distance_metric: :cosine,
          persist: true
        )
      pid when is_pid(pid) ->
        Logger.info("HNSW index already running: #{inspect(pid)}")
    end
    
    # Start pattern indexer if not already running
    indexer_name = opts[:indexer_name] || AutonomousOpponentV2Core.VSM.S4.PatternIndexer
    case Process.whereis(indexer_name) do
      nil ->
        {:ok, _} = PatternIndexer.start_link(
          name: indexer_name,
          hnsw_server: hnsw_name,
          vector_dimensions: @vector_dim
        )
      pid when is_pid(pid) ->
        Logger.info("Pattern indexer already running: #{inspect(pid)}")
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
        last_indexed_at: nil
      }
    }
    
    # Subscribe to pattern match events
    EventBus.subscribe(:pattern_matched)
    EventBus.subscribe(:patterns_extracted)
    
    # Schedule batch processing
    schedule_batch_processing()
    
    Logger.info("Pattern HNSW Bridge initialized - connecting pattern matching to vector indexing")
    
    {:ok, state}
  end
  
  @impl true
  def handle_info({:event_bus_hlc, %{type: :pattern_matched} = event}, state) do
    # Handle pattern matched events from Goldrush
    pattern_data = extract_pattern_data(event.data)
    
    if pattern_data do
      # Add to buffer for batch processing
      new_buffer = [pattern_data | state.pattern_buffer]
      new_state = %{state | 
        pattern_buffer: new_buffer,
        stats: Map.update!(state.stats, :patterns_received, &(&1 + 1))
      }
      
      # Process immediately if buffer is full
      if length(new_buffer) >= @batch_size do
        {:noreply, process_pattern_batch(new_state)}
      else
        {:noreply, new_state}
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
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      buffer_size: length(state.pattern_buffer),
      hnsw_stats: get_hnsw_stats(state.hnsw_index),
      indexer_stats: get_indexer_stats(state.pattern_indexer)
    })
    
    {:reply, stats, state}
  end
  
  # Private Functions
  
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
    
    # Index patterns
    indexed_count = Enum.reduce(patterns_to_index, 0, fn pattern, count ->
      case PatternIndexer.index_pattern(state.pattern_indexer, pattern) do
        :ok ->
          # Record metric
          Metrics.counter("vsm.s4.patterns_indexed", 1, %{source: to_string(pattern.source)})
          count + 1
        error ->
          Logger.error("Failed to index pattern: #{inspect(error)}")
          Metrics.counter("vsm.s4.indexing_errors", 1)
          count
      end
    end)
    
    # Update stats
    new_stats = state.stats
    |> Map.update!(:patterns_indexed, &(&1 + indexed_count))
    |> Map.update!(:indexing_errors, &(&1 + (length(patterns_to_index) - indexed_count)))
    |> Map.put(:last_indexed_at, DateTime.utc_now())
    
    # Publish indexing complete event
    if indexed_count > 0 do
      EventBus.publish(:patterns_indexed, %{
        count: indexed_count,
        source: :pattern_hnsw_bridge
      })
    end
    
    %{state | pattern_buffer: [], stats: new_stats}
  end
  
  defp schedule_batch_processing do
    Process.send_after(self(), :process_batch, @batch_timeout)
  end
  
  defp generate_pattern_id(pattern) do
    pattern
    |> :erlang.term_to_binary()
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
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
end