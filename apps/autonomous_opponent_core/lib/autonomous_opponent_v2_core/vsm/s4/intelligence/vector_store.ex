defmodule AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore do
  @moduledoc """
  Vector Store Integration for S4 Intelligence
  
  This module provides the integration layer between S4 Intelligence pattern recognition
  and the Vector Store components (Quantizer and future HNSW index). It manages the
  lifecycle of pattern vectors, from extraction through quantization to indexing.
  
  ## Architecture
  
  The Vector Store acts as a memory-efficient pattern library for S4:
  
  1. **Pattern Vectorization**: Converts extracted patterns to high-dimensional vectors
  2. **Quantization**: Compresses vectors using product quantization (10-100x compression)
  3. **Indexing**: Stores quantized vectors in HNSW structure for fast similarity search
  4. **Retrieval**: Finds similar historical patterns for scenario modeling
  
  ## Integration with S4 Intelligence
  
  S4 Intelligence extracts patterns → Vector Store compresses and indexes them →
  Future scans can quickly find similar historical patterns → Better predictions
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore.Quantizer
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
  
  defstruct [
    :id,
    :quantizer,
    :index_ref,
    :vector_dim,
    :pattern_vectors,
    :metrics
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Store a pattern as a vector in the vector store.
  """
  def store_pattern(server \\ __MODULE__, pattern, metadata \\ %{}) do
    GenServer.call(server, {:store_pattern, pattern, metadata})
  end
  
  @doc """
  Find k most similar patterns to the query pattern.
  """
  def find_similar_patterns(server \\ __MODULE__, query_pattern, k \\ 10) do
    GenServer.call(server, {:find_similar, query_pattern, k})
  end
  
  @doc """
  Get vector store statistics.
  """
  def get_stats(server \\ __MODULE__) do
    GenServer.call(server, :get_stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    id = opts[:id] || "s4_vector_store"
    vector_dim = opts[:vector_dim] || 64
    
    # Start quantizer
    {:ok, quantizer} = Quantizer.start_link(
      id: "#{id}_quantizer",
      vector_dim: vector_dim,
      subspaces: opts[:subspaces] || 8,
      accuracy_target: opts[:accuracy_target] || 0.9
    )
    
    # Start HNSW index with persistence if configured
    hnsw_ref = if opts[:hnsw_enabled] do
      hnsw_name = :"#{id}_hnsw"
      persist_path = opts[:persist_path] || "priv/vector_store/#{id}_hnsw"
      
      {:ok, hnsw_pid} = HNSWIndex.start_link(
        name: hnsw_name,
        m: opts[:hnsw_m] || 16,
        ef: opts[:hnsw_ef] || 200,
        distance_metric: :cosine,
        persist_path: persist_path,
        persist_interval: opts[:persist_interval] || :timer.minutes(5),
        persist_on_shutdown: opts[:persist_on_shutdown] || true,
        persist_async: opts[:persist_async] || true,
        max_patterns: opts[:max_patterns] || 100_000,
        pattern_confidence_threshold: opts[:pattern_confidence_threshold] || 0.7,
        variety_pressure_limit: opts[:variety_pressure_limit] || 0.8,
        pain_pattern_retention: opts[:pain_pattern_retention] || :timer.days(7),
        eventbus_integration: opts[:eventbus_integration] || true,
        circuitbreaker_protection: opts[:circuitbreaker_protection] || true,
        telemetry_enabled: opts[:telemetry_enabled] || true,
        algedonic_integration: opts[:algedonic_integration] || true,
        backup_retention: opts[:backup_retention] || 3,
        corruption_recovery: opts[:corruption_recovery] || true,
        prune_interval: opts[:prune_interval] || :timer.hours(1),
        prune_max_age: opts[:prune_max_age] || :timer.hours(24),
        prune_low_confidence_age: opts[:prune_low_confidence_age] || :timer.hours(6),
        checkpoint_size_threshold: opts[:checkpoint_size_threshold] || 50_000_000
      )
      hnsw_pid
    else
      nil
    end
    
    state = %__MODULE__{
      id: id,
      quantizer: quantizer,
      index_ref: hnsw_ref,
      vector_dim: vector_dim,
      pattern_vectors: %{},
      metrics: init_metrics()
    }
    
    # Subscribe to pattern extraction events
    EventBus.subscribe(:patterns_extracted)
    
    Logger.info("S4 Vector Store initialized: #{id}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:store_pattern, pattern, metadata}, _from, state) do
    # Convert pattern to vector
    vector = pattern_to_vector(pattern, state.vector_dim)
    
    # Quantize the vector
    case Quantizer.quantize(state.quantizer, vector) do
      {:ok, quantized, error} ->
        # Generate pattern ID
        pattern_id = generate_pattern_id(pattern)
        
        # Store pattern info
        pattern_info = %{
          pattern: pattern,
          vector: vector,
          quantized: quantized,
          metadata: metadata,
          error: error,
          timestamp: DateTime.utc_now()
        }
        
        new_patterns = Map.put(state.pattern_vectors, pattern_id, pattern_info)
        
        # Update metrics
        new_metrics = update_store_metrics(state.metrics, error)
        
        # Future: Add to HNSW index when implemented
        # HNSWInterface.add_vector(state.index_ref, quantized, pattern_id, state.quantizer)
        
        new_state = %{state | 
          pattern_vectors: new_patterns,
          metrics: new_metrics
        }
        
        {:reply, {:ok, pattern_id}, new_state}
        
      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:find_similar, query_pattern, k}, _from, state) do
    # Convert query pattern to vector
    query_vector = pattern_to_vector(query_pattern, state.vector_dim)
    
    # For now, do brute force search until HNSW is implemented
    similar_patterns = find_similar_brute_force(query_vector, state.pattern_vectors, k)
    
    # Future: Use HNSW for efficient search
    # case HNSWInterface.search(state.index_ref, query_vector, k, state.quantizer) do
    #   {:ok, results} -> format_search_results(results, state)
    #   error -> error
    # end
    
    {:reply, {:ok, similar_patterns}, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    quantizer_stats = Quantizer.get_stats(state.quantizer)
    
    stats = %{
      patterns_stored: map_size(state.pattern_vectors),
      vector_dim: state.vector_dim,
      quantizer_stats: quantizer_stats,
      metrics: state.metrics
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info({:event, :patterns_extracted, %{patterns: patterns}}, state) do
    # Automatically store extracted patterns
    new_state = Enum.reduce(patterns, state, fn pattern, acc_state ->
      vector = pattern_to_vector(pattern, acc_state.vector_dim)
      
      case Quantizer.quantize(acc_state.quantizer, vector) do
        {:ok, quantized, error} ->
          pattern_id = generate_pattern_id(pattern)
          
          pattern_info = %{
            pattern: pattern,
            vector: vector,
            quantized: quantized,
            metadata: %{source: :auto_extracted},
            error: error,
            timestamp: DateTime.utc_now()
          }
          
          new_patterns = Map.put(acc_state.pattern_vectors, pattern_id, pattern_info)
          new_metrics = update_store_metrics(acc_state.metrics, error)
          
          %{acc_state | 
            pattern_vectors: new_patterns,
            metrics: new_metrics
          }
          
        _ ->
          acc_state
      end
    end)
    
    # Train quantizer if we have enough new patterns
    if map_size(new_state.pattern_vectors) > 100 and 
       rem(map_size(new_state.pattern_vectors), 100) == 0 do
      
      # Extract vectors for training
      training_vectors = 
        new_state.pattern_vectors
        |> Map.values()
        |> Enum.map(& &1.vector)
      
      Quantizer.train(new_state.quantizer, training_vectors)
    end
    
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp init_metrics do
    %{
      patterns_stored: 0,
      average_quantization_error: 0.0,
      searches_performed: 0,
      average_search_time_ms: 0.0
    }
  end
  
  defp pattern_to_vector(pattern, vector_dim) do
    # Convert pattern to fixed-dimension vector representation
    # This is a simplified example - real implementation would use
    # sophisticated feature extraction
    
    features = extract_pattern_features(pattern)
    
    # Pad or truncate to match vector dimension
    cond do
      length(features) == vector_dim ->
        features
        
      length(features) < vector_dim ->
        # Pad with zeros
        features ++ List.duplicate(0.0, vector_dim - length(features))
        
      true ->
        # Truncate
        Enum.take(features, vector_dim)
    end
  end
  
  defp extract_pattern_features(pattern) do
    # Extract numerical features from pattern
    # Real implementation would vary based on pattern type
    
    base_features = [
      pattern[:confidence] || 0.5,
      pattern_type_to_number(pattern[:type]),
      pattern_subtype_to_number(pattern[:subtype])
    ]
    
    # Add pattern-specific features
    specific_features = case pattern[:type] do
      :statistical ->
        [
          pattern[:mean] || 0.0,
          pattern[:variance] || 0.0,
          pattern[:correlation] || 0.0
        ]
        
      :temporal ->
        [
          trend_to_number(pattern[:direction]),
          pattern[:strength] || 0.0,
          pattern[:period] || 0.0
        ]
        
      :structural ->
        [
          pattern[:cluster_count] || 0.0,
          pattern[:density] || 0.0,
          pattern[:levels] || 0.0
        ]
        
      :behavioral ->
        [
          pattern[:frequency] || 0.0,
          severity_to_number(pattern[:severity]),
          pattern[:count] || 0.0
        ]
        
      _ ->
        [0.0, 0.0, 0.0]
    end
    
    # Normalize features to [0, 1] range
    (base_features ++ specific_features)
    |> Enum.map(&normalize_feature/1)
  end
  
  defp pattern_type_to_number(type) do
    case type do
      :statistical -> 0.2
      :temporal -> 0.4
      :structural -> 0.6
      :behavioral -> 0.8
      _ -> 0.0
    end
  end
  
  defp pattern_subtype_to_number(subtype) do
    case subtype do
      :distribution -> 0.1
      :correlation -> 0.2
      :trend -> 0.3
      :seasonality -> 0.4
      :clustering -> 0.5
      :hierarchy -> 0.6
      :sequence -> 0.7
      :anomaly -> 0.8
      _ -> 0.0
    end
  end
  
  defp trend_to_number(trend) do
    case trend do
      :increasing -> 1.0
      :stable -> 0.5
      :decreasing -> 0.0
      _ -> 0.5
    end
  end
  
  defp severity_to_number(severity) do
    case severity do
      :critical -> 1.0
      :high -> 0.75
      :medium -> 0.5
      :low -> 0.25
      _ -> 0.0
    end
  end
  
  defp normalize_feature(value) when is_number(value) do
    # Simple min-max normalization
    # In practice, would track feature statistics
    cond do
      value < 0 -> 0.0
      value > 1 -> 1.0
      true -> value
    end
  end
  
  defp normalize_feature(_), do: 0.0
  
  defp generate_pattern_id(pattern) do
    # Generate unique ID for pattern
    data = :erlang.term_to_binary(pattern)
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end
  
  defp find_similar_brute_force(query_vector, pattern_vectors, k) do
    # Temporary brute force search until HNSW is implemented
    pattern_vectors
    |> Enum.map(fn {id, info} ->
      distance = euclidean_distance(query_vector, info.vector)
      {id, info, distance}
    end)
    |> Enum.sort_by(fn {_, _, distance} -> distance end)
    |> Enum.take(k)
    |> Enum.map(fn {id, info, distance} ->
      %{
        pattern_id: id,
        pattern: info.pattern,
        distance: distance,
        metadata: info.metadata
      }
    end)
  end
  
  defp euclidean_distance(v1, v2) do
    Enum.zip(v1, v2)
    |> Enum.map(fn {a, b} -> :math.pow(a - b, 2) end)
    |> Enum.sum()
    |> :math.sqrt()
  end
  
  defp update_store_metrics(metrics, error) do
    %{metrics |
      patterns_stored: metrics.patterns_stored + 1,
      average_quantization_error: running_average(
        metrics.average_quantization_error,
        error,
        metrics.patterns_stored
      )
    }
  end
  
  defp running_average(current_avg, new_value, count) do
    (current_avg * count + new_value) / (count + 1)
  end
end