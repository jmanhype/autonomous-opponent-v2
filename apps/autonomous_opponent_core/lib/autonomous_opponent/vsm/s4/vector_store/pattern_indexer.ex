defmodule AutonomousOpponent.VSM.S4.VectorStore.PatternIndexer do
  @moduledoc """
  Pattern indexing service for S4 Intelligence subsystem.
  
  Bridges the gap between S4's pattern extraction and HNSW vector indexing.
  Converts extracted patterns into vector representations and maintains
  the vector index for efficient similarity search.
  
  ## Wisdom Preservation
  
  ### Why Pattern Indexing?
  S4 discovers patterns continuously - in operations, environment, and behavior.
  Without indexing, each new pattern requires linear comparison with all previous
  patterns. The Pattern Indexer enables logarithmic search complexity, allowing
  S4 to scale to millions of patterns while maintaining real-time performance.
  
  ### Design Decisions
  
  1. **Automatic vectorization**: Patterns have different structures (variety,
     coordination, resource). The indexer automatically converts each to a
     standard vector representation, preserving semantic meaning.
     
  2. **Confidence filtering**: Only patterns with confidence >= 0.7 are indexed.
     Below this threshold, patterns are likely noise. This matches S4's
     pattern_threshold parameter.
     
  3. **Temporal decay**: Older patterns gradually lose relevance. The indexer
     supports time-based pruning to keep the index focused on recent patterns.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponent.VSM.S4.VectorStore.HNSWIndex
  
  # WISDOM: 100-dimensional vectors balance expressiveness with efficiency
  # Enough dimensions to capture pattern nuance, not so many that distance
  # calculations dominate search time
  @vector_dimensions 100
  
  # WISDOM: Batch insertions every 100 patterns or 5 seconds
  # Reduces index update overhead while maintaining reasonable latency
  @batch_size 100
  @batch_timeout 5_000
  
  defstruct [
    :hnsw_index,
    :vector_dimensions,
    :pattern_buffer,
    :batch_timer,
    :statistics
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Indexes a pattern for similarity search.
  """
  def index_pattern(server \\ __MODULE__, pattern) do
    GenServer.cast(server, {:index_pattern, pattern})
  end
  
  @doc """
  Indexes multiple patterns in batch.
  """
  def index_patterns(server \\ __MODULE__, patterns) when is_list(patterns) do
    GenServer.cast(server, {:index_patterns, patterns})
  end
  
  @doc """
  Finds patterns similar to the query pattern.
  """
  def find_similar(server \\ __MODULE__, pattern, k \\ 10) do
    GenServer.call(server, {:find_similar, pattern, k})
  end
  
  @doc """
  Searches by vector directly.
  """
  def search_vector(server \\ __MODULE__, vector, k \\ 10) when is_list(vector) do
    GenServer.call(server, {:search_vector, vector, k})
  end
  
  @doc """
  Returns indexer statistics.
  """
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Start HNSW index
    hnsw_opts = [
      m: opts[:m] || 16,
      ef: opts[:ef] || 200,
      distance_metric: :cosine  # Patterns are normalized, cosine works well
    ]
    
    {:ok, hnsw} = HNSWIndex.start_link(hnsw_opts)
    
    state = %__MODULE__{
      hnsw_index: hnsw,
      vector_dimensions: opts[:dimensions] || @vector_dimensions,
      pattern_buffer: [],
      batch_timer: nil,
      statistics: %{
        patterns_indexed: 0,
        patterns_rejected: 0,
        searches_performed: 0,
        batch_flushes: 0
      }
    }
    
    Logger.info("Pattern Indexer initialized with #{state.vector_dimensions} dimensions")
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:index_pattern, pattern}, state) do
    state = add_to_buffer(state, [pattern])
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:index_patterns, patterns}, state) do
    state = add_to_buffer(state, patterns)
    {:noreply, state}
  end
  
  @impl true
  def handle_call({:find_similar, pattern, k}, _from, state) do
    # Convert pattern to vector
    vector = pattern_to_vector(pattern, state.vector_dimensions)
    
    # Search in HNSW
    {:ok, results} = HNSWIndex.search(state.hnsw_index, vector, k)
    
    # Update statistics
    new_stats = Map.update!(state.statistics, :searches_performed, &(&1 + 1))
    new_state = %{state | statistics: new_stats}
    
    {:reply, {:ok, results}, new_state}
  end
  
  @impl true
  def handle_call({:search_vector, vector, k}, _from, state) do
    {:ok, results} = HNSWIndex.search(state.hnsw_index, vector, k)
    
    new_stats = Map.update!(state.statistics, :searches_performed, &(&1 + 1))
    new_state = %{state | statistics: new_stats}
    
    {:reply, {:ok, results}, new_state}
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    hnsw_stats = HNSWIndex.stats(state.hnsw_index)
    
    stats = Map.merge(state.statistics, %{
      buffer_size: length(state.pattern_buffer),
      index_size: hnsw_stats.node_count,
      memory_usage: hnsw_stats.memory_usage
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info(:flush_buffer, state) do
    new_state = flush_buffer(%{state | batch_timer: nil})
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp add_to_buffer(state, patterns) do
    # Filter patterns by confidence
    valid_patterns = Enum.filter(patterns, fn p ->
      Map.get(p, :confidence, 0) >= 0.7
    end)
    
    new_buffer = state.pattern_buffer ++ valid_patterns
    
    cond do
      # Flush if buffer is full
      length(new_buffer) >= @batch_size ->
        flush_buffer(%{state | pattern_buffer: new_buffer})
        
      # Start timer if this is first pattern in buffer
      length(state.pattern_buffer) == 0 and length(valid_patterns) > 0 ->
        timer = Process.send_after(self(), :flush_buffer, @batch_timeout)
        %{state | pattern_buffer: new_buffer, batch_timer: timer}
        
      # Just add to buffer
      true ->
        %{state | pattern_buffer: new_buffer}
    end
  end
  
  defp flush_buffer(state) do
    if length(state.pattern_buffer) > 0 do
      # Cancel timer if exists
      if state.batch_timer do
        Process.cancel_timer(state.batch_timer)
      end
      
      # Index all patterns in buffer
      indexed_count = Enum.reduce(state.pattern_buffer, 0, fn pattern, count ->
        vector = pattern_to_vector(pattern, state.vector_dimensions)
        metadata = pattern_to_metadata(pattern)
        
        case HNSWIndex.insert(state.hnsw_index, vector, metadata) do
          {:ok, _} -> count + 1
          {:error, _} -> count
        end
      end)
      
      # Update statistics
      new_stats = state.statistics
      |> Map.update!(:patterns_indexed, &(&1 + indexed_count))
      |> Map.update!(:patterns_rejected, &(&1 + length(state.pattern_buffer) - indexed_count))
      |> Map.update!(:batch_flushes, &(&1 + 1))
      
      %{state | pattern_buffer: [], batch_timer: nil, statistics: new_stats}
    else
      state
    end
  end
  
  # WISDOM: Pattern vectorization - the art of encoding meaning
  # Different pattern types have different "signatures" in vector space.
  # The encoding preserves semantic similarity: similar patterns yield
  # similar vectors, enabling meaningful nearest-neighbor search.
  defp pattern_to_vector(pattern, dimensions) do
    # Base encoding by pattern type
    type_encoding = encode_pattern_type(pattern[:type])
    
    # Statistical features
    stats_encoding = [
      normalize_value(pattern[:average] || 0.5, 0, 1),
      normalize_value(pattern[:variance] || 0.1, 0, 1),
      normalize_value(pattern[:confidence] || 0.7, 0, 1),
      encode_trend(pattern[:trend])
    ]
    
    # Temporal features if available
    temporal_encoding = encode_temporal_features(pattern)
    
    # Domain-specific features
    domain_encoding = encode_domain_features(pattern)
    
    # Combine all encodings
    base_vector = type_encoding ++ stats_encoding ++ temporal_encoding ++ domain_encoding
    
    # Pad or truncate to target dimensions
    vector = if length(base_vector) < dimensions do
      base_vector ++ List.duplicate(0.0, dimensions - length(base_vector))
    else
      Enum.take(base_vector, dimensions)
    end
    
    # Normalize to unit vector for cosine similarity
    normalize_vector(vector)
  end
  
  defp encode_pattern_type(type) do
    # One-hot encoding for major pattern types
    types = [
      :variety_absorption, :coordination, :resource, :environmental,
      :behavioral, :anomaly, :cross_domain
    ]
    
    Enum.map(types, fn t ->
      if t == type, do: 1.0, else: 0.0
    end)
  end
  
  defp encode_trend(trend) do
    case trend do
      :increasing -> 1.0
      :decreasing -> -1.0
      :stable -> 0.0
      :cyclic -> 0.5
      _ -> 0.0
    end
  end
  
  defp encode_temporal_features(pattern) do
    # Encode time-based characteristics
    features = []
    
    # Recency (how recent is this pattern)
    features = if pattern[:timestamp] do
      age = System.monotonic_time(:millisecond) - pattern[:timestamp]
      recency = :math.exp(-age / 3_600_000)  # Exponential decay over 1 hour
      [recency | features]
    else
      [0.5 | features]
    end
    
    # Periodicity if detected
    features = if pattern[:period] do
      # Encode period on log scale
      period_encoding = :math.log(pattern[:period] + 1) / 10
      [period_encoding | features]
    else
      [0.0 | features]
    end
    
    features
  end
  
  defp encode_domain_features(pattern) do
    # Encode domain-specific features based on pattern source
    case pattern[:source] do
      :s1_metrics ->
        # Operational patterns
        [
          normalize_value(pattern[:absorption_rate] || 0.5, 0, 1),
          normalize_value(pattern[:resource_efficiency] || 0.5, 0, 1)
        ]
        
      :environmental ->
        # Environmental patterns
        [
          normalize_value(pattern[:change_magnitude] || 0.0, -1, 1),
          normalize_value(pattern[:stability_score] || 0.5, 0, 1)
        ]
        
      _ ->
        [0.0, 0.0]
    end
  end
  
  defp normalize_value(value, min, max) do
    cond do
      value <= min -> 0.0
      value >= max -> 1.0
      true -> (value - min) / (max - min)
    end
  end
  
  defp normalize_vector(vector) do
    magnitude = :math.sqrt(Enum.reduce(vector, 0, fn x, sum -> sum + x * x end))
    
    if magnitude > 0 do
      Enum.map(vector, fn x -> x / magnitude end)
    else
      vector
    end
  end
  
  defp pattern_to_metadata(pattern) do
    # Extract relevant metadata for storage
    %{
      type: pattern[:type],
      source: pattern[:source],
      confidence: pattern[:confidence],
      timestamp: pattern[:timestamp] || System.monotonic_time(:millisecond),
      trend: pattern[:trend],
      original_pattern: pattern  # Store full pattern for retrieval
    }
  end
end