defmodule AutonomousOpponentCore.VSM.S4.Intelligence.VectorStore.Quantizer do
  @moduledoc """
  Vector Quantizer for S4 Intelligence Pattern Recognition
  
  Implements vector quantization for efficient pattern recognition and memory optimization
  in the S4 environmental scanning subsystem. Uses product quantization with k-means
  clustering for vector compression while maintaining search accuracy.
  
  Key features:
  - Product quantization with configurable subspace dimensions
  - K-means clustering with adaptive centroid optimization
  - Scalar and vector quantization methods
  - Dynamic accuracy vs storage trade-off configuration
  - Integration interface for HNSW index (Task 4 dependency)
  
  ## Wisdom Preservation
  
  ### Why Vector Quantization Matters for S4
  S4's environmental scanning generates massive high-dimensional vectors from pattern
  recognition. Without compression, memory explodes and search slows. Vector quantization
  provides 10-100x compression while preserving 90%+ search accuracy. This enables S4
  to maintain larger pattern libraries and search them faster.
  
  ### Design Decisions & Rationale
  
  1. **Product Quantization (PQ)**: Splits vectors into subspaces, quantizes each
     independently. Why? PQ provides exponential compression (2^subspaces) while
     maintaining locality - similar vectors remain similar after quantization.
     
  2. **256 Centroids per Subspace**: 8-bit encoding per subspace. Balance between
     compression (256:1 per subspace) and accuracy. 256 = sweet spot found by
     Facebook's Faiss team for most real-world data.
     
  3. **Adaptive K-means**: Centroids adjust to data distribution over time. Static
     centroids fail when data drifts. Adaptation keeps quantization error low as
     S4's environmental model evolves.
     
  4. **0.9 Default Accuracy Target**: 90% recall at 10. Below this, pattern matching
     degrades. Above 95%, compression suffers badly. 90% = operational sweet spot.
  """
  
  use GenServer
  require Logger
  
  alias AutonomousOpponentV2Core.EventBus
  
  # WISDOM: 256 centroids = 8-bit encoding, optimal for RAM/accuracy trade-off
  @default_centroids_per_subspace 256
  
  # WISDOM: 8 subspaces for 64-dim vectors = 8 bytes per vector after quantization
  @default_subspaces 8
  
  # WISDOM: 1000 vectors triggers re-clustering to adapt to data drift
  @recluster_threshold 1000
  
  # WISDOM: 90% accuracy preserves pattern recognition while enabling 10x compression
  @default_accuracy_target 0.9
  
  defstruct [
    :id,
    :config,
    :codebooks,          # K-means centroids for each subspace
    :vector_buffer,      # Accumulates vectors for adaptive re-clustering
    :quantization_stats, # Tracks compression ratios and accuracy
    :index_interface,    # Future HNSW integration point
    :state
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  @doc """
  Quantize a single vector using the trained codebooks.
  Returns compressed representation and reconstruction error.
  """
  def quantize(server \\ __MODULE__, vector) do
    GenServer.call(server, {:quantize, vector})
  end
  
  @doc """
  Quantize multiple vectors in batch for efficiency.
  """
  def quantize_batch(server \\ __MODULE__, vectors) do
    GenServer.call(server, {:quantize_batch, vectors})
  end
  
  @doc """
  Reconstruct original vector from quantized representation.
  """
  def reconstruct(server \\ __MODULE__, quantized) do
    GenServer.call(server, {:reconstruct, quantized})
  end
  
  @doc """
  Train quantizer on a dataset of vectors.
  """
  def train(server \\ __MODULE__, vectors, opts \\ []) do
    GenServer.call(server, {:train, vectors, opts}, :infinity)
  end
  
  @doc """
  Update accuracy/storage trade-off configuration.
  """
  def configure_tradeoff(server \\ __MODULE__, accuracy_target) do
    GenServer.call(server, {:configure_tradeoff, accuracy_target})
  end
  
  @doc """
  Get current compression statistics.
  """
  def get_stats(server \\ __MODULE__) do
    GenServer.call(server, :get_stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    id = opts[:id] || "s4_vector_quantizer"
    
    config = init_config(opts)
    
    state = %__MODULE__{
      id: id,
      config: config,
      codebooks: init_codebooks(config),
      vector_buffer: [],
      quantization_stats: init_stats(),
      index_interface: init_index_interface(opts),
      state: :initialized
    }
    
    # Subscribe to relevant events
    EventBus.subscribe(:pattern_extracted)
    EventBus.subscribe(:vector_index_update)
    
    Logger.info("S4 Vector Quantizer initialized: #{id}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:quantize, vector}, _from, state) do
    case quantize_vector(vector, state) do
      {:ok, quantized, error} ->
        # Update stats
        new_stats = update_quantization_stats(state.quantization_stats, error)
        new_state = %{state | quantization_stats: new_stats}
        
        # Add to buffer for potential re-clustering
        new_state = add_to_buffer(new_state, vector)
        
        {:reply, {:ok, quantized, error}, new_state}
        
      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:quantize_batch, vectors}, _from, state) do
    {results, new_state} = 
      Enum.map_reduce(vectors, state, fn vector, acc_state ->
        case quantize_vector(vector, acc_state) do
          {:ok, quantized, error} ->
            # Update stats
            new_stats = update_quantization_stats(acc_state.quantization_stats, error)
            new_state = %{acc_state | quantization_stats: new_stats}
            
            # Add to buffer
            new_state = add_to_buffer(new_state, vector)
            
            {{:ok, quantized, error}, new_state}
            
          {:error, _reason} = error ->
            {error, acc_state}
        end
      end)
    
    {:reply, results, new_state}
  end
  
  @impl true
  def handle_call({:reconstruct, quantized}, _from, state) do
    reconstructed = reconstruct_vector(quantized, state)
    {:reply, {:ok, reconstructed}, state}
  end
  
  @impl true
  def handle_call({:train, vectors, opts}, _from, state) do
    Logger.info("Training vector quantizer on #{length(vectors)} vectors")
    
    # Train new codebooks
    case train_codebooks(vectors, state.config, opts) do
      {:ok, new_codebooks} ->
        # Calculate training stats
        {avg_error, compression_ratio} = calculate_training_stats(vectors, new_codebooks, state.config)
        
        # Update state
        new_stats = %{state.quantization_stats | 
          average_error: avg_error,
          compression_ratio: compression_ratio,
          vectors_trained: length(vectors)
        }
        
        new_state = %{state | 
          codebooks: new_codebooks,
          quantization_stats: new_stats,
          state: :trained
        }
        
        # Notify other components
        EventBus.publish(:quantizer_trained, %{
          id: state.id,
          compression_ratio: compression_ratio,
          accuracy: 1.0 - avg_error
        })
        
        {:reply, {:ok, new_stats}, new_state}
        
      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:configure_tradeoff, accuracy_target}, _from, state) do
    # Adjust configuration based on accuracy target
    new_config = adjust_config_for_accuracy(state.config, accuracy_target)
    
    # Retrain if we have vectors
    new_state = if length(state.vector_buffer) > 100 do
      case train_codebooks(state.vector_buffer, new_config, []) do
        {:ok, new_codebooks} ->
          %{state | config: new_config, codebooks: new_codebooks}
        _ ->
          %{state | config: new_config}
      end
    else
      %{state | config: new_config}
    end
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.quantization_stats, %{
      config: state.config,
      state: state.state,
      buffer_size: length(state.vector_buffer)
    })
    
    {:reply, stats, state}
  end
  
  # WISDOM: Pattern extraction creates vectors - quantize them for efficiency
  # S4 pattern extraction generates feature vectors. We quantize these immediately
  # to keep memory usage bounded. The slight accuracy loss (10%) is worth the
  # 10-100x memory savings, enabling larger pattern libraries.
  @impl true
  def handle_info({:event, :pattern_extracted, %{vectors: vectors}}, state) do
    # Quantize newly extracted pattern vectors
    new_state = Enum.reduce(vectors, state, fn vector, acc_state ->
      add_to_buffer(acc_state, vector)
    end)
    
    # Check if we need to retrain
    new_state = maybe_retrain(new_state)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:event, :vector_index_update, %{operation: :search, vector: vector}}, state) do
    # Pre-quantize search vectors for HNSW when it's implemented
    case quantize_vector(vector, state) do
      {:ok, _quantized, _error} ->
        # Future: Forward to HNSW index
        Logger.debug("Pre-quantized search vector for future HNSW integration")
        {:noreply, state}
        
      _ ->
        {:noreply, state}
    end
  end
  
  # Private Functions
  
  defp init_config(opts) do
    %{
      vector_dim: opts[:vector_dim] || 64,
      subspaces: opts[:subspaces] || @default_subspaces,
      centroids_per_subspace: opts[:centroids] || @default_centroids_per_subspace,
      accuracy_target: opts[:accuracy_target] || @default_accuracy_target,
      quantization_type: opts[:type] || :product,  # :product | :scalar
      distance_metric: opts[:metric] || :euclidean, # :euclidean | :cosine
      adaptive: opts[:adaptive] || true
    }
  end
  
  defp init_codebooks(config) do
    # Initialize empty codebooks for each subspace
    subspace_dim = div(config.vector_dim, config.subspaces)
    
    Enum.map(1..config.subspaces, fn _ ->
      %{
        centroids: [],  # Will be populated during training
        subspace_dim: subspace_dim,
        version: 0
      }
    end)
  end
  
  defp init_stats do
    %{
      vectors_quantized: 0,
      average_error: 0.0,
      compression_ratio: 0.0,
      memory_saved_bytes: 0,
      vectors_trained: 0,
      last_retrain: nil
    }
  end
  
  defp init_index_interface(opts) do
    %{
      enabled: false,  # HNSW not implemented yet
      index_name: opts[:index_name] || "s4_pattern_index",
      update_callback: opts[:index_callback]
    }
  end
  
  # WISDOM: Product quantization - divide and conquer for exponential compression
  # Split vector into subspaces, quantize each to nearest centroid. With 8 subspaces
  # and 256 centroids each, we get 256^8 possible encodings using only 8 bytes.
  # Key insight: local structure preserved within subspaces maintains similarity.
  defp quantize_vector(vector, state) when state.state == :trained do
    try do
      # Split vector into subspaces
      subvectors = split_vector(vector, state.config.subspaces)
      
      # Quantize each subspace
      {codes, errors} = 
        subvectors
        |> Enum.zip(state.codebooks)
        |> Enum.map(fn {subvec, codebook} ->
          {code, error} = find_nearest_centroid(subvec, codebook)
          {code, error}
        end)
        |> Enum.unzip()
      
      # Calculate total reconstruction error
      total_error = Enum.sum(errors) / length(errors)
      
      quantized = %{
        codes: codes,
        type: :product_quantized,
        subspaces: state.config.subspaces,
        timestamp: System.monotonic_time(:millisecond)
      }
      
      {:ok, quantized, total_error}
    catch
      error ->
        {:error, error}
    end
  end
  
  defp quantize_vector(_vector, _state) do
    {:error, :not_trained}
  end
  
  defp reconstruct_vector(quantized, state) do
    # Reconstruct by concatenating centroid vectors
    subvectors = 
      quantized.codes
      |> Enum.zip(state.codebooks)
      |> Enum.map(fn {code, codebook} ->
        Enum.at(codebook.centroids, code)
      end)
    
    # Concatenate subvectors
    List.flatten(subvectors)
  end
  
  # WISDOM: K-means training - finding representative centroids
  # Lloyd's algorithm with k-means++ initialization. Why k-means? Simple, fast,
  # and works well for product quantization. The key is good initialization -
  # k-means++ ensures centroids are spread out, avoiding local minima.
  defp train_codebooks(vectors, config, opts) do
    # Validate input
    if Enum.empty?(vectors) do
      {:error, :empty_training_set}
    else
      iterations = opts[:iterations] || 20
      
      try do
        # Split vectors into subspaces
        subspace_vectors = prepare_training_data(vectors, config)
      
      # Train codebook for each subspace
      codebooks = 
        subspace_vectors
        |> Enum.with_index()
        |> Enum.map(fn {subvecs, idx} ->
          centroids = train_kmeans(
            subvecs, 
            config.centroids_per_subspace,
            iterations,
            config.distance_metric
          )
          
          %{
            centroids: centroids,
            subspace_dim: length(hd(subvecs)),
            version: 1,
            subspace_index: idx
          }
        end)
      
        {:ok, codebooks}
      catch
        error ->
          {:error, error}
      end
    end
  end
  
  defp train_kmeans(vectors, k, iterations, metric) do
    # K-means++ initialization
    initial_centroids = kmeans_plus_plus_init(vectors, k, metric)
    
    # Lloyd's algorithm iterations
    final_centroids = 
      Enum.reduce(1..iterations, initial_centroids, fn _i, centroids ->
        # Assignment step
        clusters = assign_to_clusters(vectors, centroids, metric)
        
        # Update step
        update_centroids(clusters)
      end)
    
    final_centroids
  end
  
  # WISDOM: K-means++ initialization - smart centroid seeding
  # Choose first centroid randomly, then each subsequent centroid with probability
  # proportional to squared distance from nearest centroid. This spreads initial
  # centroids out, leading to better final clusters and faster convergence.
  defp kmeans_plus_plus_init(vectors, k, metric) do
    # First centroid is random
    first = Enum.random(vectors)
    
    # Select remaining centroids
    Enum.reduce(2..k, [first], fn _i, centroids ->
      # Calculate distances to nearest centroid for each vector
      distances = 
        Enum.map(vectors, fn v ->
          min_dist = 
            centroids
            |> Enum.map(fn c -> distance(v, c, metric) end)
            |> Enum.min()
          
          {v, min_dist * min_dist}  # Square for probability
        end)
      
      # Select next centroid with weighted probability
      next_centroid = weighted_random_select(distances)
      [next_centroid | centroids]
    end)
    |> Enum.reverse()
  end
  
  defp assign_to_clusters(vectors, centroids, metric) do
    vectors
    |> Enum.group_by(fn vector ->
      # Find nearest centroid
      centroids
      |> Enum.with_index()
      |> Enum.min_by(fn {centroid, _idx} ->
        distance(vector, centroid, metric)
      end)
      |> elem(1)
    end)
  end
  
  defp update_centroids(clusters) do
    0..(map_size(clusters) - 1)
    |> Enum.map(fn idx ->
      case clusters[idx] do
        nil -> 
          # Empty cluster - reinitialize randomly
          Enum.random(Map.values(clusters) |> List.flatten())
          
        cluster_vectors ->
          # Calculate mean of cluster
          calculate_centroid(cluster_vectors)
      end
    end)
  end
  
  defp calculate_centroid(vectors) do
    dim = length(hd(vectors))
    count = length(vectors)
    
    # Sum all vectors
    sum_vector = 
      Enum.reduce(vectors, List.duplicate(0.0, dim), fn vec, acc ->
        Enum.zip(vec, acc)
        |> Enum.map(fn {v, a} -> v + a end)
      end)
    
    # Divide by count
    Enum.map(sum_vector, &(&1 / count))
  end
  
  defp find_nearest_centroid(subvector, codebook) do
    if Enum.empty?(codebook.centroids) do
      {0, 1.0}  # Default when not trained
    else
      {_centroid, idx, dist} = 
        codebook.centroids
        |> Enum.with_index()
        |> Enum.map(fn {centroid, idx} ->
          dist = euclidean_distance(subvector, centroid)
          {centroid, idx, dist}
        end)
        |> Enum.min_by(fn {_, _, dist} -> dist end)
      
      {idx, dist}
    end
  end
  
  defp split_vector(vector, num_subspaces) do
    subspace_size = div(length(vector), num_subspaces)
    
    Enum.chunk_every(vector, subspace_size)
  end
  
  defp prepare_training_data(vectors, config) do
    # Split each vector and group by subspace
    vectors
    |> Enum.map(fn v -> split_vector(v, config.subspaces) end)
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
  end
  
  defp distance(v1, v2, :euclidean), do: euclidean_distance(v1, v2)
  defp distance(v1, v2, :cosine), do: cosine_distance(v1, v2)
  
  defp euclidean_distance(v1, v2) do
    Enum.zip(v1, v2)
    |> Enum.map(fn {a, b} -> :math.pow(a - b, 2) end)
    |> Enum.sum()
    |> :math.sqrt()
  end
  
  defp cosine_distance(v1, v2) do
    dot_product = 
      Enum.zip(v1, v2)
      |> Enum.map(fn {a, b} -> a * b end)
      |> Enum.sum()
    
    norm1 = :math.sqrt(Enum.sum(Enum.map(v1, fn x -> x * x end)))
    norm2 = :math.sqrt(Enum.sum(Enum.map(v2, fn x -> x * x end)))
    
    if norm1 == 0 or norm2 == 0 do
      1.0
    else
      1.0 - (dot_product / (norm1 * norm2))
    end
  end
  
  defp weighted_random_select(weighted_items) do
    total_weight = 
      weighted_items
      |> Enum.map(fn {_, weight} -> weight end)
      |> Enum.sum()
    
    random = :rand.uniform() * total_weight
    
    weighted_items
    |> Enum.reduce_while({random, nil}, fn {item, weight}, {remaining, _} ->
      if remaining <= weight do
        {:halt, {0, item}}
      else
        {:cont, {remaining - weight, nil}}
      end
    end)
    |> elem(1)
  end
  
  defp calculate_training_stats(vectors, codebooks, config) do
    # Calculate average quantization error
    errors = 
      Enum.map(vectors, fn vector ->
        subvectors = split_vector(vector, config.subspaces)
        
        subvectors
        |> Enum.zip(codebooks)
        |> Enum.map(fn {subvec, codebook} ->
          {_code, error} = find_nearest_centroid(subvec, codebook)
          error
        end)
        |> Enum.sum()
        |> Kernel./(config.subspaces)
      end)
    
    avg_error = Enum.sum(errors) / length(errors)
    
    # Calculate compression ratio
    original_size = length(vectors) * config.vector_dim * 4  # 4 bytes per float
    compressed_size = length(vectors) * config.subspaces  # 1 byte per subspace code
    compression_ratio = original_size / compressed_size
    
    {avg_error, compression_ratio}
  end
  
  defp update_quantization_stats(stats, error) do
    %{stats |
      vectors_quantized: stats.vectors_quantized + 1,
      average_error: running_average(stats.average_error, error, stats.vectors_quantized)
    }
  end
  
  defp running_average(current_avg, new_value, count) do
    (current_avg * count + new_value) / (count + 1)
  end
  
  # WISDOM: Adaptive retraining - keeping up with data drift
  # Environmental patterns change over time. Static quantization degrades as
  # data drifts from training distribution. Buffer 1000 vectors, then retrain.
  # This maintains compression quality as S4's worldview evolves.
  defp add_to_buffer(state, vector) do
    new_buffer = [vector | state.vector_buffer] |> Enum.take(@recluster_threshold)
    %{state | vector_buffer: new_buffer}
  end
  
  defp maybe_retrain(state) do
    if length(state.vector_buffer) >= @recluster_threshold and state.config.adaptive do
      Logger.info("Retraining quantizer with #{length(state.vector_buffer)} buffered vectors")
      
      case train_codebooks(state.vector_buffer, state.config, [iterations: 10]) do
        {:ok, new_codebooks} ->
          %{state | 
            codebooks: new_codebooks,
            vector_buffer: [],
            quantization_stats: %{state.quantization_stats | last_retrain: DateTime.utc_now()}
          }
          
        _ ->
          state
      end
    else
      state
    end
  end
  
  # WISDOM: Accuracy-driven configuration - quality when needed, speed when not
  # Different use cases need different trade-offs. Critical pattern matching needs
  # high accuracy (more centroids, more subspaces). Bulk storage can sacrifice
  # accuracy for compression. This function translates accuracy targets to configs.
  defp adjust_config_for_accuracy(config, accuracy_target) do
    cond do
      accuracy_target >= 0.95 ->
        # High accuracy: more centroids, fewer subspaces
        %{config | 
          centroids_per_subspace: 512,
          subspaces: max(4, div(config.vector_dim, 16))
        }
        
      accuracy_target >= 0.9 ->
        # Balanced: standard configuration
        %{config | 
          centroids_per_subspace: 256,
          subspaces: @default_subspaces
        }
        
      accuracy_target >= 0.8 ->
        # Favor compression: fewer centroids
        %{config | 
          centroids_per_subspace: 128,
          subspaces: min(16, div(config.vector_dim, 4))
        }
        
      true ->
        # Maximum compression: minimal centroids
        %{config | 
          centroids_per_subspace: 64,
          subspaces: min(32, div(config.vector_dim, 2))
        }
    end
  end
end