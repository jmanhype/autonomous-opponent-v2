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
    :hnsw_index,
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
    
    # Start HNSW index with persistence configuration
    hnsw_name = :"#{id}_hnsw"
    persist_path = opts[:persist_path] || "priv/vector_store/#{id}_hnsw"
    
    {:ok, _} = HNSWIndex.start_link(
      name: hnsw_name,
      m: opts[:hnsw_m] || 16,
      ef: opts[:hnsw_ef] || 200,
      distance_metric: :cosine,
      persist: true,
      persist_path: persist_path,
      persist_interval: opts[:persist_interval] || :timer.minutes(5),
      persist_on_shutdown: opts[:persist_on_shutdown] || true,
      persist_async: opts[:persist_async] || true,
      max_patterns: opts[:max_patterns] || 100_000,
      pattern_confidence_threshold: opts[:pattern_confidence_threshold] || 0.7,
      variety_pressure_limit: opts[:variety_pressure_limit] || 0.8,
      pain_pattern_retention: opts[:pain_pattern_retention] || 7 * 24 * 60 * 60 * 1000,
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
    
    state = %__MODULE__{
      id: id,
      quantizer: quantizer,
      hnsw_index: hnsw_name,
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
        
        # Add to HNSW index
        case HNSWIndex.add_vector(state.hnsw_index, vector, pattern_id) do
          :ok ->
            Logger.debug("Pattern #{pattern_id} added to HNSW index")
          error ->
            Logger.error("Failed to add pattern to HNSW: #{inspect(error)}")
        end
        
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
    
    # Use HNSW for efficient search
    case HNSWIndex.search(state.hnsw_index, query_vector, k) do
      {:ok, results} ->
        # Enrich results with pattern data
        enriched_results = Enum.map(results, fn {pattern_id, distance} ->
          pattern_info = Map.get(state.pattern_vectors, pattern_id)
          %{
            pattern_id: pattern_id,
            distance: distance,
            pattern: pattern_info[:pattern],
            metadata: pattern_info[:metadata],
            timestamp: pattern_info[:timestamp]
          }
        end)
        
        {:reply, {:ok, enriched_results}, state}
        
      {:error, _reason} = error ->
        # Fallback to brute force if HNSW fails
        Logger.warn("HNSW search failed, falling back to brute force")
        similar_patterns = find_similar_brute_force(query_vector, state.pattern_vectors, k)
        {:reply, {:ok, similar_patterns}, state}
    end
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
    # Enhanced to use more dimensions with statistical moments and temporal features
    
    base_features = [
      pattern[:confidence] || 0.5,
      pattern_type_to_number(pattern[:type]),
      pattern_subtype_to_number(pattern[:subtype]),
      # Add timestamp features
      extract_time_of_day_feature(pattern[:timestamp]),
      extract_day_of_week_feature(pattern[:timestamp]),
      extract_recency_feature(pattern[:timestamp])
    ]
    
    # Add pattern-specific features with enhanced statistical analysis
    specific_features = case pattern[:type] do
      :statistical ->
        [
          pattern[:mean] || 0.0,
          pattern[:variance] || 0.0,
          pattern[:correlation] || 0.0,
          pattern[:skewness] || 0.0,          # Statistical moment 3
          pattern[:kurtosis] || 0.0,          # Statistical moment 4
          pattern[:min] || 0.0,
          pattern[:max] || 0.0,
          pattern[:median] || 0.0,
          pattern[:std_dev] || 0.0,
          pattern[:percentile_25] || 0.0,
          pattern[:percentile_75] || 0.0,
          pattern[:iqr] || 0.0,               # Interquartile range
          pattern[:outlier_count] || 0.0,
          pattern[:zero_crossing_rate] || 0.0,
          pattern[:autocorrelation] || 0.0
        ]
        
      :temporal ->
        [
          trend_to_number(pattern[:direction]),
          pattern[:strength] || 0.0,
          pattern[:period] || 0.0,
          pattern[:phase] || 0.0,
          pattern[:amplitude] || 0.0,
          pattern[:frequency] || 0.0,
          pattern[:duty_cycle] || 0.0,
          pattern[:rise_time] || 0.0,
          pattern[:fall_time] || 0.0,
          pattern[:jitter] || 0.0,
          pattern[:drift_rate] || 0.0,
          pattern[:acceleration] || 0.0,
          pattern[:seasonality_strength] || 0.0,
          pattern[:trend_break_count] || 0.0,
          pattern[:cycle_variance] || 0.0
        ]
        
      :structural ->
        [
          pattern[:cluster_count] || 0.0,
          pattern[:density] || 0.0,
          pattern[:levels] || 0.0,
          pattern[:connectivity] || 0.0,
          pattern[:modularity] || 0.0,
          pattern[:hierarchy_depth] || 0.0,
          pattern[:branching_factor] || 0.0,
          pattern[:diameter] || 0.0,
          pattern[:centrality] || 0.0,
          pattern[:clustering_coefficient] || 0.0,
          pattern[:path_length] || 0.0,
          pattern[:node_count] || 0.0,
          pattern[:edge_count] || 0.0,
          pattern[:component_count] || 0.0,
          pattern[:spectral_gap] || 0.0
        ]
        
      :behavioral ->
        [
          pattern[:frequency] || 0.0,
          severity_to_number(pattern[:severity]),
          pattern[:count] || 0.0,
          pattern[:duration] || 0.0,
          pattern[:recurrence_interval] || 0.0,
          pattern[:burst_length] || 0.0,
          pattern[:inter_arrival_time] || 0.0,
          pattern[:state_transitions] || 0.0,
          pattern[:entropy] || 0.0,
          pattern[:predictability] || 0.0,
          pattern[:stability] || 0.0,
          pattern[:volatility] || 0.0,
          pattern[:momentum] || 0.0,
          pattern[:acceleration] || 0.0,
          pattern[:consistency] || 0.0
        ]
        
      _ ->
        # Default features for unknown types
        List.duplicate(0.0, 15)
    end
    
    # Add cross-pattern relationship features
    cross_pattern_features = [
      pattern[:correlation_with_previous] || 0.0,
      pattern[:similarity_to_baseline] || 0.0,
      pattern[:deviation_from_mean] || 0.0,
      pattern[:relative_importance] || 0.0,
      pattern[:interaction_strength] || 0.0,
      pattern[:causality_score] || 0.0,
      pattern[:lag_correlation] || 0.0,
      pattern[:mutual_information] || 0.0,
      pattern[:transfer_entropy] || 0.0,
      pattern[:granger_causality] || 0.0
    ]
    
    # Add metadata features
    metadata_features = [
      pattern[:source_reliability] || 0.5,
      pattern[:data_quality] || 0.8,
      pattern[:sample_size] || 0.0,
      pattern[:noise_level] || 0.0,
      pattern[:missing_data_ratio] || 0.0
    ]
    
    # Combine all features
    all_features = base_features ++ specific_features ++ cross_pattern_features ++ metadata_features
    
    # Normalize features to [0, 1] range
    normalized = all_features |> Enum.map(&normalize_feature/1)
    
    # Ensure we have exactly vector_dim features
    # Pad with derived features if necessary
    if length(normalized) < 100 do
      padding_needed = 100 - length(normalized)
      derived_features = generate_derived_features(normalized, padding_needed)
      normalized ++ derived_features
    else
      Enum.take(normalized, 100)
    end
  end
  
  defp extract_time_of_day_feature(nil), do: 0.5
  defp extract_time_of_day_feature(timestamp) do
    # Convert timestamp to time of day (0.0 = midnight, 0.5 = noon, 1.0 = 11:59pm)
    case timestamp do
      %DateTime{hour: hour, minute: minute} ->
        (hour * 60 + minute) / (24 * 60)
      _ ->
        0.5
    end
  end
  
  defp extract_day_of_week_feature(nil), do: 0.5
  defp extract_day_of_week_feature(timestamp) do
    # Convert to day of week (0.0 = Monday, 1.0 = Sunday)
    case timestamp do
      %DateTime{} = dt ->
        Date.day_of_week(DateTime.to_date(dt)) / 7.0
      _ ->
        0.5
    end
  end
  
  defp extract_recency_feature(nil), do: 0.5
  defp extract_recency_feature(timestamp) do
    # Calculate recency (1.0 = now, 0.0 = very old)
    case timestamp do
      %DateTime{} = dt ->
        now = DateTime.utc_now()
        diff_seconds = DateTime.diff(now, dt)
        # Normalize using exponential decay (half-life of 1 hour)
        :math.exp(-diff_seconds / 3600.0)
      _ ->
        0.5
    end
  end
  
  defp generate_derived_features(base_features, count) do
    # Generate additional features through combinations and transformations
    derived = []
    
    # Polynomial features (squared terms)
    squared = base_features 
    |> Enum.take(div(count, 3))
    |> Enum.map(fn x -> x * x end)
    
    # Interaction features (products of pairs)
    interactions = for i <- 0..(length(base_features) - 2),
                      j <- (i + 1)..(length(base_features) - 1),
                      i < div(count, 3) do
      Enum.at(base_features, i, 0.0) * Enum.at(base_features, j, 0.0)
    end
    |> Enum.take(div(count, 3))
    
    # Trigonometric transformations
    trig = base_features
    |> Enum.take(div(count, 3))
    |> Enum.map(fn x -> :math.sin(x * :math.pi()) / 2.0 + 0.5 end)
    
    all_derived = squared ++ interactions ++ trig
    
    # Pad with zeros if still needed
    if length(all_derived) < count do
      all_derived ++ List.duplicate(0.0, count - length(all_derived))
    else
      Enum.take(all_derived, count)
    end
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