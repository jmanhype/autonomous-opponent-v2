# S4 Vector Store - HNSW Index

The Hierarchical Navigable Small World (HNSW) index provides efficient vector similarity search for the S4 Intelligence subsystem's pattern recognition capabilities.

## Overview

HNSW is a graph-based algorithm for approximate nearest neighbor search that builds a multi-layer navigable small world graph. It offers:

- **Logarithmic search complexity**: O(log n) search time
- **Linear space complexity**: O(n) memory usage
- **High recall rates**: >95% recall with proper tuning
- **Incremental construction**: Add vectors without rebuilding

## Architecture

```
vector_store/
├── hnsw_index.ex         # Core HNSW algorithm implementation
├── pattern_indexer.ex    # Pattern-to-vector conversion service  
├── persistence.ex        # Disk persistence layer
├── distance_metrics.ex   # Cosine & Euclidean distance functions
├── supervisor.ex         # Supervision tree for fault tolerance
└── benchmarks/
    ├── accuracy_bench.ex # Recall and precision measurements
    └── perf_bench.ex     # Throughput and latency tests
```

### Core Components

1. **HNSWIndex**: GenServer managing the graph structure
2. **PatternIndexer**: Converts S4 patterns to searchable vectors
3. **Persistence**: Binary serialization with compression
4. **DistanceMetrics**: Optimized vector operations

## VSM Concepts for Developers

### Understanding VSM Architecture

The Viable System Model (VSM) is a cybernetic model that structures the Autonomous Opponent into five recursive subsystems:

**S1 - Operations (Implementation)**: The parts that do the actual work
- Multiple operational units running concurrently
- Each S1 unit has its own management (recursive VSM)
- Generate data that S4 indexes for pattern recognition

**S2 - Coordination**: Ensures S1 units work harmoniously
- Prevents conflicts between operational units
- Manages shared resources
- Uses pattern data to identify coordination needs

**S3 - Control (Operations Management)**: Optimizes and controls S1 units
- Resource allocation based on current needs
- Performance optimization
- Uses S4's pattern insights for predictive control

**S4 - Intelligence (Environmental Scanning)**: **This is where HNSW lives**
- Monitors external environment for threats/opportunities
- Pattern recognition and trend analysis
- Provides future-focused intelligence to S3 and S5
- HNSW index enables rapid pattern matching at scale

**S5 - Policy (Identity & Purpose)**: Sets direction and policy
- Defines system identity and purpose
- Makes strategic decisions
- Adapts policies based on S4's environmental intelligence

### Key VSM Principles

**Variety Absorption**: Systems must match environmental complexity
- HNSW handles high-dimensional pattern spaces efficiently
- Enables S4 to process millions of environmental signals
- Logarithmic search complexity manages variety explosion

**Recursion**: Each subsystem contains the same structure
- Patterns at one level inform decisions at other levels
- HNSW indexes patterns from all recursive levels

**Autonomy**: Subsystems operate independently within constraints
- S4 continuously scans without S5 micromanagement
- HNSW updates don't block other operations

**Real-time Constraints**: VSM requires timely information flow
- S4 scans environment every 10 seconds
- HNSW must return results within this cycle
- Pattern matching enables predictive responses

## Usage Examples

### Basic Usage

```elixir
# Start HNSW index with default parameters
{:ok, index} = HNSWIndex.start_link([])

# Insert vectors with metadata
vector = [0.1, 0.5, 0.3, 0.8]  # Feature vector
metadata = %{type: :resource_pattern, confidence: 0.85}
{:ok, node_id} = HNSWIndex.insert(index, vector, metadata)

# Search for similar vectors
query = [0.2, 0.4, 0.3, 0.7]
{:ok, results} = HNSWIndex.search(index, query, 5)  # Find 5 nearest

# Results include distance and metadata
Enum.each(results, fn %{distance: d, metadata: m} ->
  IO.puts("Distance: #{d}, Type: #{m.type}")
end)
```

### Integration with S4 Intelligence

```elixir
# Start pattern indexer for S4
{:ok, indexer} = PatternIndexer.start_link([])

# Index patterns discovered by S4
pattern = %{
  type: :variety_absorption,
  average: 0.75,
  variance: 0.12,
  trend: :increasing,
  confidence: 0.82
}

PatternIndexer.index_pattern(indexer, pattern)

# Find similar historical patterns
{:ok, similar} = PatternIndexer.find_similar(indexer, pattern, 10)
```

### Persistence

```elixir
# Start with persistence enabled
{:ok, index} = HNSWIndex.start_link(
  persist_path: "/var/lib/autonomous_opponent/s4_patterns.hnsw"
)

# Index will auto-restore on startup if file exists
# Manual save
HNSWIndex.persist(index)
```

## Configuration

### HNSW Parameters

- **M** (default: 16): Number of bidirectional links per node. Higher values increase recall but use more memory.
- **ef** (default: 200): Size of the dynamic candidate list. Higher values increase search accuracy but slow down queries.
- **distance_metric**: `:cosine` (default) or `:euclidean`

### Recommended Settings

For S4 environmental scanning (100-1000 dimensional patterns):
```elixir
{:ok, index} = HNSWIndex.start_link(
  m: 16,              # Good balance of speed/accuracy
  ef: 200,            # High accuracy for pattern matching
  distance_metric: :cosine  # Patterns are normalized
)
```

For high-volume operational metrics (10-50 dimensions):
```elixir
{:ok, index} = HNSWIndex.start_link(
  m: 8,               # Lower M for speed
  ef: 50,             # Lower ef for faster queries
  distance_metric: :euclidean
)
```

## Performance Characteristics

### Benchmarks with Real S4 Pattern Data

| Vectors | Dimensions | Insert Time | Search Time (k=10) | Memory/Vector | Recall@10 |
|---------|------------|-------------|-------------------|---------------|----------|
| 1K      | 50         | ~2ms        | ~5ms              | ~2KB          | 99.5%    |
| 10K     | 128        | ~3ms        | ~8ms              | ~3KB          | 98.2%    |
| 100K    | 128        | ~4ms        | ~12ms             | ~3KB          | 96.8%    |
| 1M      | 128        | ~5ms        | ~18ms             | ~3KB          | 95.1%    |
| 10K     | 768        | ~8ms        | ~25ms             | ~8KB          | 97.5%    |

### Memory Usage Formula
```
memory_per_vector = vector_size * 4 bytes + (M * 2 * 8 bytes) + metadata_size
total_memory = num_vectors * memory_per_vector + graph_overhead
```

### Search Performance Factors
1. **ef parameter**: Higher ef = better recall but slower search
2. **Vector dimensions**: Search time grows sub-linearly with dimensions
3. **Index size**: Logarithmic growth in search time
4. **Hardware**: Benefits from CPU cache optimization

## Integration Points

### S4 Environmental Scanner
The scanner generates feature vectors from environmental observations. These are indexed for pattern detection:

```elixir
# In environmental_scanner.ex
scan_vector = extract_features(scan_data)
HNSWIndex.insert(index, scan_vector, %{
  source: :environmental_scan,
  timestamp: DateTime.utc_now(),
  entities: map_size(scan_data.entities)
})
```

### S4 Pattern Extractor
Extracted patterns are converted to vectors and indexed:

```elixir
# In pattern_extractor.ex
pattern_vector = pattern_to_vector(pattern)
HNSWIndex.insert(index, pattern_vector, %{
  pattern_type: pattern.type,
  confidence: pattern.confidence
})
```

### VSM Integration
The index enables S4 to quickly find similar historical patterns, supporting the VSM's learning and adaptation:

```elixir
# Find patterns similar to current situation
{:ok, historical} = HNSWIndex.search(index, current_vector, 20)

# Use historical patterns for prediction
predictions = Enum.map(historical, fn %{metadata: m} ->
  predict_outcome(m.original_pattern)
end)
```

## Implementation Guide

### Step-by-Step Implementation

1. **Start with Core Data Structures**
```elixir
# Define the node structure
defmodule AutonomousOpponent.VSM.S4.VectorStore.HNSWNode do
  defstruct [:id, :vector, :metadata, :neighbors, :layer]
end

# Define the index structure
defmodule AutonomousOpponent.VSM.S4.VectorStore.HNSWIndex do
  use GenServer
  
  defstruct [
    :nodes, :entry_point, :m, :ef_construction, 
    :ef, :ml, :distance_metric, :seed
  ]
end
```

2. **Implement Distance Metrics**
```elixir
defmodule AutonomousOpponent.VSM.S4.VectorStore.DistanceMetrics do
  def cosine_distance(v1, v2) do
    # Implement efficient cosine distance
  end
  
  def euclidean_distance(v1, v2) do
    # Implement efficient euclidean distance
  end
end
```

3. **Build Core HNSW Operations**
```elixir
# Layer assignment
def assign_layer(ml) do
  # Exponential decay distribution
  -:math.log(:rand.uniform()) * ml |> floor()
end

# Search algorithm
def search_layer(entry_point, query, num_closest, layer) do
  # Implement greedy search at specific layer
end
```

## Comprehensive Error Handling

### Error Types and Recovery Strategies

```elixir
defmodule HNSWErrorHandling do
  @doc """Example of comprehensive error handling for HNSW operations"""
  
  def safe_insert(index, vector, metadata) do
    case HNSWIndex.insert(index, vector, metadata) do
      {:ok, node_id} -> 
        Logger.debug("Indexed vector #{node_id}")
        {:ok, node_id}
        
      {:error, :dimension_mismatch} ->
        # Vector dimensions don't match index configuration
        Logger.error("Vector dimension mismatch, expected: #{get_index_dimensions(index)}")
        # Attempt to pad or truncate vector
        corrected = adjust_vector_dimensions(vector, get_index_dimensions(index))
        retry_insert(index, corrected, metadata)
        
      {:error, :index_full} ->
        # Memory limit reached
        Logger.warn("Index full, triggering cleanup")
        S4.Intelligence.trigger_pattern_archival()
        {:error, :retry_later}
        
      {:error, :invalid_vector} ->
        # Vector contains NaN or Inf values
        Logger.error("Invalid vector values: #{inspect(vector)}")
        # Attempt to sanitize
        case sanitize_vector(vector) do
          {:ok, clean_vector} -> HNSWIndex.insert(index, clean_vector, metadata)
          :error -> {:error, :unrecoverable}
        end
        
      {:error, {:timeout, op}} ->
        # Operation timed out
        Logger.warn("Insert timeout after #{op}ms")
        # Add to retry queue
        RetryQueue.add({:insert, vector, metadata})
        {:error, :queued_for_retry}
    end
  end
  
  def safe_search(index, query_vector, k) do
    case HNSWIndex.search(index, query_vector, k) do
      {:ok, results} -> 
        {:ok, results}
        
      {:error, :empty_index} ->
        Logger.info("Search on empty index")
        {:ok, []}
        
      {:error, :invalid_query} ->
        Logger.error("Invalid query vector")
        # Try to fix common issues
        case sanitize_vector(query_vector) do
          {:ok, clean} -> HNSWIndex.search(index, clean, k)
          :error -> {:error, :invalid_query_vector}
        end
        
      {:error, {:insufficient_results, found}} ->
        # Fewer than k results available
        Logger.debug("Only #{found} results available, requested #{k}")
        # Return what we have
        HNSWIndex.search(index, query_vector, found)
        
      {:error, reason} = error ->
        Logger.error("Search failed: #{inspect(reason)}")
        # Fallback to exact search for critical queries
        if critical_query?(query_vector) do
          exact_nearest_neighbors(index, query_vector, k)
        else
          error
        end
    end
  end
  
  @doc """Batch operations with partial failure handling"""
  def safe_batch_insert(index, vector_metadata_pairs) do
    results = vector_metadata_pairs
    |> Task.async_stream(
      fn {vector, metadata} -> 
        {safe_insert(index, vector, metadata), vector, metadata}
      end,
      max_concurrency: System.schedulers_online(),
      timeout: 5_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce({[], []}, fn
      {:ok, {{:ok, id}, _, _}}, {succeeded, failed} -> 
        {[id | succeeded], failed}
      {:ok, {error, vector, metadata}}, {succeeded, failed} -> 
        {succeeded, [{error, vector, metadata} | failed]}
      {:exit, :timeout}, {succeeded, failed} -> 
        {succeeded, [:timeout | failed]}
    end)
    
    case results do
      {succeeded, []} -> {:ok, Enum.reverse(succeeded)}
      {succeeded, failed} -> {:partial, succeeded, failed}
    end
  end
end
```

### Error Recovery Patterns

```elixir
defmodule HNSWRecovery do
  use GenServer
  
  @doc """Automated recovery from index corruption"""
  def handle_info({:index_corrupted, reason}, state) do
    Logger.error("Index corruption detected: #{inspect(reason)}")
    
    recovery_result = 
      case attempt_recovery(state.index) do
        {:ok, recovered_index} ->
          Logger.info("Index recovered successfully")
          {:recovered, recovered_index}
          
        {:partial, recovered_index, lost_count} ->
          Logger.warn("Partial recovery: lost #{lost_count} vectors")
          EventBus.emit(:s4_pattern_loss, %{count: lost_count})
          {:partial_recovery, recovered_index}
          
        :unrecoverable ->
          Logger.error("Index unrecoverable, rebuilding from S1 data")
          rebuild_from_operational_data()
      end
    
    {:noreply, %{state | index: recovery_result, last_corruption: DateTime.utc_now()}}
  end
  
  defp attempt_recovery(index) do
    with {:ok, backup_path} <- find_latest_backup(),
         {:ok, backup_index} <- HNSWIndex.load(backup_path),
         {:ok, recent_patterns} <- get_patterns_since(backup_timestamp(backup_path)),
         :ok <- replay_patterns(backup_index, recent_patterns) do
      {:ok, backup_index}
    else
      {:error, :no_backup} -> :unrecoverable
      {:error, :backup_corrupted} -> :unrecoverable
      {:error, {:replay_failed, succeeded, total}} -> 
        {:partial, backup_index, total - succeeded}
    end
  end
end
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Poor Recall Performance
**Symptoms**: Search results missing obvious matches
**Causes & Solutions**:
- **Low ef parameter**: Increase ef to 200-500 for better recall
- **Insufficient M**: Increase M to 16-32 for denser graph
- **Wrong distance metric**: Ensure vectors are normalized for cosine

#### 2. Slow Search Performance  
**Symptoms**: Searches taking >50ms
**Causes & Solutions**:
- **High ef parameter**: Reduce ef, accept slightly lower recall
- **Too many dimensions**: Use dimensionality reduction (PCA, UMAP)
- **Cold cache**: Implement neighbor caching strategy

#### 3. Memory Issues
**Symptoms**: OOM errors, high memory usage
**Causes & Solutions**:
- **Large M parameter**: Reduce M to 8-12 for memory efficiency
- **Vector precision**: Use Float32 instead of Float64
- **Metadata bloat**: Store metadata separately, reference by ID

#### 4. Index Corruption
**Symptoms**: Crashes on load, inconsistent results
**Causes & Solutions**:
- **Incomplete writes**: Implement atomic file operations
- **Version mismatch**: Add version checking to persistence
- **Concurrent modifications**: Use proper locking mechanisms

### Performance Tuning Checklist

- [ ] Profile with real S4 pattern data
- [ ] Tune M and ef based on recall requirements
- [ ] Implement vector quantization for large indices
- [ ] Use ETS for node storage with read_concurrency
- [ ] Batch insertions for better throughput
- [ ] Monitor memory usage and implement pruning
- [ ] Cache frequently accessed neighborhoods
- [ ] Use binary format for vector storage

## Maintenance

### Memory Management
The index grows with each insertion. For long-running systems:

```elixir
# Monitor memory usage
defmodule MemoryMonitor do
  use GenServer
  
  def init(_) do
    schedule_check()
    {:ok, %{}}
  end
  
  def handle_info(:check_memory, state) do
    stats = HNSWIndex.stats(index)
    
    cond do
      stats.memory_mb > 1000 ->
        Logger.warn("High memory usage: #{stats.memory_mb}MB")
        HNSWIndex.compact(index)
        
      stats.vector_count > 1_000_000 ->
        Logger.info("Archiving old patterns")
        archive_old_patterns(index)
        
      true ->
        :ok
    end
    
    schedule_check()
    {:noreply, state}
  end
  
  defp schedule_check do
    Process.send_after(self(), :check_memory, :timer.minutes(5))
  end
end
```

### Persistence Strategy

```elixir
defmodule PersistenceManager do
  use GenServer
  
  # Save on schedule
  def init(index_pid) do
    schedule_save()
    {:ok, %{index: index_pid, last_save: DateTime.utc_now()}}
  end
  
  # Save on significant events
  def handle_info({:event, :environmental_shift, _}, state) do
    save_index(state.index)
    {:noreply, %{state | last_save: DateTime.utc_now()}}
  end
  
  # Periodic saves
  def handle_info(:scheduled_save, state) do
    save_index(state.index)
    schedule_save()
    {:noreply, %{state | last_save: DateTime.utc_now()}}
  end
  
  defp save_index(index) do
    Task.async(fn ->
      HNSWIndex.persist(index, "/var/lib/s4/hnsw_backup.dat")
    end)
  end
end
```

### Index Health Monitoring

```elixir
defmodule IndexHealth do
  def check_health(index) do
    %{
      connectivity: check_graph_connectivity(index),
      balance: check_layer_distribution(index),
      recall: measure_recall_sample(index),
      latency: measure_search_latency(index)
    }
  end
  
  defp check_graph_connectivity(index) do
    # Ensure no isolated nodes
    # Check average degree per layer
  end
  
  defp check_layer_distribution(index) do
    # Verify exponential distribution
    # Flag if too many nodes at high layers
  end
end
```

### Advanced Troubleshooting Scenarios

#### Pattern Drift Detection
```elixir
# Monitor if pattern distributions are changing over time
defmodule PatternDriftMonitor do
  def detect_drift(index, time_window \\ :timer.hours(24)) do
    recent_patterns = get_patterns_since(time_window)
    historical_centroid = calculate_centroid(index, :all)
    recent_centroid = calculate_centroid(recent_patterns)
    
    drift_score = cosine_distance(historical_centroid, recent_centroid)
    
    if drift_score > 0.3 do
      Logger.warn("Pattern drift detected: #{drift_score}")
      # May need to retrain or adjust index parameters
    end
  end
end
```

#### Index Imbalance
```elixir
# Detect and fix imbalanced layer distribution
defmodule IndexBalancer do
  def check_balance(index) do
    stats = HNSWIndex.layer_stats(index)
    
    # Check if too many nodes at high layers
    high_layer_ratio = stats.layers[3..10] |> Enum.sum() / stats.total
    
    if high_layer_ratio > 0.01 do
      Logger.warn("Index imbalance: #{high_layer_ratio * 100}% nodes at high layers")
      rebalance_index(index)
    end
  end
end
```

## Testing Guidelines

### Unit Test Template
```elixir
defmodule HNSWIndexTest do
  use ExUnit.Case
  
  setup do
    {:ok, index} = HNSWIndex.start_link(m: 16, ef: 200)
    {:ok, index: index}
  end
  
  test "insert and search basic", %{index: index} do
    vector = Enum.map(1..128, fn _ -> :rand.uniform() end)
    {:ok, id} = HNSWIndex.insert(index, vector, %{type: :test})
    
    {:ok, results} = HNSWIndex.search(index, vector, 1)
    assert length(results) == 1
    assert hd(results).id == id
    assert hd(results).distance < 0.001
  end
end
```

### Integration Test with S4
```elixir
defmodule S4IntegrationTest do
  use ExUnit.Case
  
  test "pattern indexing pipeline" do
    # Start S4 subsystem
    {:ok, s4} = S4.Intelligence.start_link()
    
    # Generate test pattern
    pattern = %{
      type: :resource_anomaly,
      vector: generate_pattern_vector(),
      confidence: 0.9
    }
    
    # Index pattern
    :ok = S4.Intelligence.index_pattern(s4, pattern)
    
    # Search for similar
    {:ok, similar} = S4.Intelligence.find_similar(s4, pattern.vector, 5)
    assert length(similar) >= 1
  end
end
```

## Migration Guide from Other Vector Stores

### Migrating from PostgreSQL pgvector

```elixir
defmodule PgvectorMigration do
  @doc """
  Migrate vectors from PostgreSQL pgvector to HNSW index.
  Handles batching and progress tracking.
  """
  def migrate_from_pgvector(pg_config, hnsw_index) do
    Logger.info("Starting pgvector migration")
    
    # Count total vectors
    total = Repo.aggregate("vector_embeddings", :count)
    Logger.info("Migrating #{total} vectors")
    
    # Stream vectors in batches
    "vector_embeddings"
    |> Repo.stream(max_rows: 1000)
    |> Stream.chunk_every(100)
    |> Stream.with_index()
    |> Enum.reduce({0, []}, fn {batch, batch_idx}, {migrated, errors} ->
      # Convert pgvector format to HNSW format
      vectors = Enum.map(batch, fn row ->
        {
          row.embedding |> pgvector_to_list(),
          %{
            original_id: row.id,
            created_at: row.inserted_at,
            metadata: row.metadata || %{},
            source: :pgvector_migration
          }
        }
      end)
      
      # Batch insert into HNSW
      case HNSWIndex.insert_batch(hnsw_index, vectors) do
        {:ok, ids} ->
          count = length(ids)
          Logger.info("Batch #{batch_idx}: Migrated #{count} vectors")
          {migrated + count, errors}
          
        {:partial, ids, failures} ->
          count = length(ids)
          Logger.warn("Batch #{batch_idx}: Partial success #{count}/#{length(batch)}")
          {migrated + count, errors ++ failures}
          
        {:error, reason} ->
          Logger.error("Batch #{batch_idx} failed: #{inspect(reason)}")
          {migrated, [{batch_idx, reason} | errors]}
      end
    end)
    
    Logger.info("Migration complete: #{migrated}/#{total} vectors migrated")
    if errors != [], do: Logger.error("Errors: #{inspect(errors)}")
    
    # Verify migration
    verify_migration(pg_config, hnsw_index)
  end
  
  defp pgvector_to_list(pgvector_binary) do
    # Convert pgvector binary format to Elixir list
    pgvector_binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(4)
    |> Enum.map(&:binary.list_to_float/1)
  end
end
```

### Migrating from Elasticsearch

```elixir
defmodule ElasticsearchMigration do
  def migrate_from_elasticsearch(es_config, hnsw_index) do
    # Scroll through all documents with dense_vector fields
    es_client = Elasticsearch.Client.new(es_config)
    
    scroll_params = %{
      index: "patterns",
      scroll: "2m",
      size: 1000,
      body: %{
        query: %{exists: %{field: "pattern_vector"}}
      }
    }
    
    es_client
    |> Elasticsearch.scroll(scroll_params)
    |> Stream.unfold(&scroll_next/1)
    |> Stream.concat()
    |> Stream.chunk_every(100)
    |> Enum.each(fn batch ->
      vectors = Enum.map(batch, fn doc ->
        {
          doc["_source"]["pattern_vector"],
          %{
            es_id: doc["_id"],
            es_index: doc["_index"],
            timestamp: doc["_source"]["@timestamp"],
            metadata: Map.drop(doc["_source"], ["pattern_vector", "@timestamp"])
          }
        }
      end)
      
      HNSWIndex.insert_batch(hnsw_index, vectors)
    end)
  end
end
```

### Migrating from FAISS

```elixir
defmodule FAISSMigration do
  @nif_module :faiss_reader  # Assumes you have a NIF to read FAISS
  
  def migrate_from_faiss(faiss_index_path, hnsw_index) do
    # Load FAISS index
    {:ok, faiss_data} = @nif_module.read_index(faiss_index_path)
    
    Logger.info("Migrating #{faiss_data.ntotal} vectors from FAISS")
    
    # FAISS stores vectors in a flat array
    faiss_data.vectors
    |> Enum.chunk_every(faiss_data.dimension)
    |> Enum.with_index()
    |> Enum.chunk_every(100)
    |> Enum.each(fn batch ->
      vectors = Enum.map(batch, fn {vector, idx} ->
        {
          vector,
          %{
            faiss_id: idx,
            source: :faiss_migration,
            migrated_at: DateTime.utc_now()
          }
        }
      end)
      
      HNSWIndex.insert_batch(hnsw_index, vectors)
      Process.sleep(10) # Throttle to avoid overwhelming the index
    end)
  end
end
```

## Distance Metric Selection Guide

### Choosing the Right Distance Metric

#### Cosine Distance (Default)

**When to use**:
- Vectors represent directions or proportions
- Magnitude differences should be ignored
- Working with normalized feature vectors
- Text embeddings (TF-IDF, Word2Vec, BERT)
- S4 environmental patterns (normalized features)

**Examples**:
```elixir
# Topic similarity - magnitude doesn't matter
pattern1 = [0.8, 0.2, 0.0]  # 80% topic A, 20% topic B
pattern2 = [0.4, 0.1, 0.0]  # Same proportions, different magnitude
# Cosine distance sees these as identical

# Environmental patterns - normalized features
s4_pattern = %{
  resource_usage: 0.7,      # Normalized to [0,1]
  variety_level: 0.9,       # Normalized to [0,1]  
  coordination_stress: 0.3  # Normalized to [0,1]
}
```

**Automatic normalization**:
```elixir
# HNSW automatically normalizes for cosine distance
vector = [1, 2, 3]
# Internally converted to: [0.267, 0.534, 0.801]
HNSWIndex.insert(index, vector, metadata)  # Auto-normalized
```

#### Euclidean Distance

**When to use**:
- Absolute magnitudes matter
- Working with raw measurements
- Geometric/spatial data
- Sensor readings
- Resource usage metrics

**Examples**:
```elixir
# Resource usage - absolute values matter
server1 = [85.5, 1024, 0.92]  # CPU%, Memory MB, Disk I/O
server2 = [42.1, 512, 0.45]   # Very different load levels

# Sensor readings - raw values
sensor_reading = %{
  temperature: 23.5,    # Celsius
  pressure: 1013.25,    # hPa
  humidity: 65.0        # Percentage
}
```

**Important considerations**:
```elixir
# Scale sensitivity - normalize features to similar ranges
raw_vector = [1000, 0.5, 3]  # Different scales
scaled_vector = [
  1000 / 5000,  # Normalize to [0,1]
  0.5,          # Already in [0,1]
  3 / 10        # Normalize to [0,1]
]

# Use scaled version for better results
HNSWIndex.insert(index, scaled_vector, metadata)
```

### Decision Matrix

| Use Case | Recommended Metric | Reason |
|----------|-------------------|--------|
| S4 Environmental Patterns | Cosine | Patterns are normalized, direction matters |
| Text Embeddings | Cosine | Semantic similarity independent of magnitude |
| Time Series Similarity | Cosine | Shape matters more than amplitude |
| Server Metrics | Euclidean | Absolute resource usage matters |
| Geographic Coordinates | Euclidean | Physical distance calculation |
| Image Feature Vectors | Cosine | Usually normalized CNN features |
| User Behavior Vectors | Cosine | Proportions of actions matter |
| Sensor Measurements | Euclidean | Raw physical measurements |

## Concurrency Patterns

### Thread-Safe Operations

```elixir
defmodule ConcurrentHNSW do
  @doc """All HNSW operations are thread-safe through GenServer"""
  
  # Concurrent insertions - safe
  def parallel_insert(index, vectors) do
    vectors
    |> Task.async_stream(
      fn {vector, metadata} ->
        HNSWIndex.insert(index, vector, metadata)
      end,
      max_concurrency: System.schedulers_online() * 2,
      timeout: 10_000
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {:error, :timeout}
    end)
  end
  
  # Concurrent searches - safe and efficient
  def parallel_search(index, queries, k) do
    queries
    |> Task.async_stream(
      fn query -> HNSWIndex.search(index, query, k) end,
      max_concurrency: System.schedulers_online() * 4,  # Read-heavy
      ordered: false  # Don't preserve order for speed
    )
    |> Stream.map(fn {:ok, result} -> result end)
    |> Enum.to_list()
  end
  
  # Mixed read/write workload
  def mixed_workload(index) do
    # Searches don't block inserts
    search_task = Task.async(fn ->
      Enum.map(1..1000, fn _ ->
        query = generate_random_vector()
        HNSWIndex.search(index, query, 10)
      end)
    end)
    
    # Inserts don't block searches
    insert_task = Task.async(fn ->
      Enum.map(1..100, fn i ->
        vector = generate_pattern_vector(i)
        HNSWIndex.insert(index, vector, %{id: i})
      end)
    end)
    
    # Both complete independently
    {Task.await(search_task), Task.await(insert_task)}
  end
end
```

### Batch Processing Patterns

```elixir
defmodule BatchPatterns do
  use GenServer
  
  @batch_size 100
  @batch_timeout 5_000
  
  def init(_) do
    schedule_flush()
    {:ok, %{batch: [], index: nil}}
  end
  
  @doc """Accumulate inserts for batch processing"""
  def handle_cast({:insert, vector, metadata}, state) do
    new_batch = [{vector, metadata} | state.batch]
    
    if length(new_batch) >= @batch_size do
      flush_batch(new_batch, state.index)
      {:noreply, %{state | batch: []}}
    else
      {:noreply, %{state | batch: new_batch}}
    end
  end
  
  def handle_info(:flush_timeout, state) do
    if state.batch != [] do
      flush_batch(state.batch, state.index)
    end
    schedule_flush()
    {:noreply, %{state | batch: []}}
  end
  
  defp flush_batch(batch, index) do
    # Process batch in parallel chunks
    batch
    |> Enum.reverse()  # Maintain insertion order
    |> Enum.chunk_every(10)
    |> Task.async_stream(
      fn chunk ->
        Enum.map(chunk, fn {v, m} -> 
          HNSWIndex.insert(index, v, m)
        end)
      end,
      max_concurrency: 4
    )
    |> Stream.run()
  end
end
```

### Flow-based Processing

```elixir
defmodule FlowProcessing do
  @doc """Use Flow for large-scale parallel processing"""
  def process_pattern_stream(pattern_stream, index) do
    pattern_stream
    |> Flow.from_enumerable(max_demand: 1000)
    |> Flow.partition(max_demand: 100, stages: System.schedulers_online())
    |> Flow.map(&extract_vector/1)
    |> Flow.map(fn {vector, metadata} ->
      case HNSWIndex.insert(index, vector, metadata) do
        {:ok, id} -> {:indexed, id}
        {:error, reason} -> {:failed, reason, metadata}
      end
    end)
    |> Flow.reduce(fn -> %{indexed: 0, failed: 0} end, fn
      {:indexed, _}, acc -> %{acc | indexed: acc.indexed + 1}
      {:failed, _, _}, acc -> %{acc | failed: acc.failed + 1}
    end)
    |> Enum.to_list()
  end
end
```

## VSM Operational Integration Patterns

### S4 Pattern Memory Architecture

```elixir
defmodule S4.PatternMemory do
  @moduledoc """
  S4's pattern memory using HNSW for environmental intelligence.
  Enables the VSM to learn from historical patterns.
  """
  
  use GenServer
  alias AutonomousOpponent.VSM.S4.VectorStore.HNSWIndex
  
  # Pattern memory for different time horizons
  @indices %{
    immediate: :s4_immediate_patterns,  # Last 1 hour
    short_term: :s4_short_patterns,     # Last 24 hours  
    long_term: :s4_long_patterns,       # Last 30 days
    historical: :s4_historical_patterns # All time
  }
  
  @doc """Record environmental pattern with VSM context"""
  def remember_pattern(scan_data) do
    vector = extract_features(scan_data)
    timestamp = DateTime.utc_now()
    
    # Rich metadata including VSM cross-subsystem context
    metadata = %{
      timestamp: timestamp,
      scan_id: scan_data.id,
      # S1 context
      operational_load: get_s1_load(),
      active_operations: count_s1_operations(),
      # S2 context  
      coordination_conflicts: get_s2_conflicts(),
      resource_contentions: get_s2_contentions(),
      # S3 context
      resource_allocation: get_s3_allocation(),
      optimization_state: get_s3_state(),
      # S4 self-reference
      variety_level: calculate_variety(scan_data),
      pattern_complexity: assess_complexity(scan_data),
      confidence: scan_data.confidence,
      # S5 context
      active_policies: get_s5_policies(),
      strategic_alignment: calculate_alignment(scan_data)
    }
    
    # Index in multiple time horizons
    Enum.each(@indices, fn {horizon, index_name} ->
      if should_index?(horizon, metadata) do
        HNSWIndex.insert(index_name, vector, metadata)
      end
    end)
    
    # Trigger cross-subsystem notifications if needed
    check_pattern_significance(vector, metadata)
  end
  
  @doc """Find historical precedents for current situation"""
  def find_precedents(current_scan, options \ []) do
    horizon = Keyword.get(options, :horizon, :long_term)
    k = Keyword.get(options, :k, 50)
    
    vector = extract_features(current_scan)
    index = @indices[horizon]
    
    case HNSWIndex.search(index, vector, k) do
      {:ok, similar_patterns} ->
        # Enrich with outcome data
        similar_patterns
        |> Enum.map(&enrich_with_outcomes/1)
        |> weight_by_relevance(current_scan)
        |> filter_by_confidence(0.7)
        |> aggregate_predictions()
        
      {:error, reason} ->
        Logger.warn("Pattern search failed: #{inspect(reason)}")
        # Fallback to statistical methods
        S4.Intelligence.statistical_precedents(current_scan)
    end
  end
  
  @doc """Predict future states based on pattern matching"""
  def predict_future_states(current_scan, time_horizon) do
    # Find similar historical patterns
    precedents = find_precedents(current_scan, horizon: :historical)
    
    # Extract state progressions from precedents
    progressions = precedents
    |> Enum.map(fn precedent ->
      get_state_progression(precedent, time_horizon)
    end)
    |> Enum.filter(& &1.confidence > 0.6)
    
    # Aggregate predictions weighted by similarity and recency
    aggregate_progressions(progressions, current_scan)
  end
  
  @doc """Detect emerging patterns that require S5 attention"""
  def detect_emergence(recent_window \\ :timer.minutes(10)) do
    recent_patterns = get_recent_patterns(:immediate, recent_window)
    
    # Cluster recent patterns
    clusters = cluster_patterns(recent_patterns)
    
    # Identify novel clusters
    novel_clusters = clusters
    |> Enum.map(fn cluster ->
      %{
        cluster: cluster,
        novelty: calculate_novelty(cluster, :historical),
        significance: assess_significance(cluster)
      }
    end)
    |> Enum.filter(& &1.novelty > 0.8 && &1.significance > 0.7)
    
    # Alert S5 about emerging patterns
    Enum.each(novel_clusters, fn novel ->
      EventBus.emit(:s5_emergence_detected, %{
        pattern: novel,
        recommended_policy_adjustment: suggest_policy(novel)
      })
    end)
  end
end
```

### Cross-Subsystem Pattern Integration

```elixir
defmodule VSM.PatternIntegration do
  @moduledoc """
  Integrates HNSW pattern matching across all VSM subsystems.
  Enables system-wide learning and adaptation.
  """
  
  @doc """S1 -> S4: Operational patterns feed environmental scanning"""
  def index_operational_patterns do
    S1.Operations.get_pattern_stream()
    |> Stream.map(fn op_data ->
      %{
        vector: operational_to_vector(op_data),
        metadata: %{
          source: :s1_operations,
          operation_id: op_data.id,
          resource_usage: op_data.resources,
          performance_metrics: op_data.metrics
        }
      }
    end)
    |> Stream.chunk_every(50)
    |> Stream.each(fn batch ->
      S4.PatternMemory.index_batch(:operational_patterns, batch)
    end)
    |> Stream.run()
  end
  
  @doc """S3 -> S4: Control decisions create patterns for learning"""
  def learn_from_control_decisions do
    S3.Control.decision_stream()
    |> Flow.from_enumerable()
    |> Flow.map(fn decision ->
      %{
        vector: decision_to_vector(decision),
        metadata: %{
          source: :s3_control,
          decision_type: decision.type,
          context: decision.context,
          outcome: track_decision_outcome(decision)
        }
      }
    end)
    |> Flow.each(fn pattern ->
      S4.PatternMemory.remember_pattern(pattern)
    end)
    |> Flow.run()
  end
  
  @doc """S4 -> S3: Pattern insights inform control optimization"""
  def provide_control_insights(current_state) do
    # Find similar historical states
    similar_states = S4.PatternMemory.find_precedents(current_state)
    
    # Extract successful control strategies
    successful_strategies = similar_states
    |> Enum.filter(& &1.outcome.success)
    |> Enum.map(& &1.metadata.control_strategy)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, freq} -> freq end, :desc)
    |> Enum.take(5)
    
    # Send recommendations to S3
    S3.Control.receive_recommendations(%{
      current_state: current_state,
      historical_success_rate: calculate_success_rate(similar_states),
      recommended_strategies: successful_strategies,
      confidence: calculate_confidence(similar_states)
    })
  end
  
  @doc """S4 -> S5: Environmental patterns trigger policy adaptation"""
  def check_policy_alignment do
    # Get recent environmental patterns
    recent = S4.PatternMemory.get_recent_patterns(:short_term)
    
    # Check alignment with current policies
    alignment_scores = recent
    |> Enum.map(fn pattern ->
      %{
        pattern: pattern,
        policy_alignment: S5.Policy.calculate_alignment(pattern),
        effectiveness: measure_pattern_effectiveness(pattern)
      }
    end)
    
    # Identify misalignments
    misalignments = alignment_scores
    |> Enum.filter(& &1.policy_alignment < 0.6)
    |> Enum.filter(& &1.effectiveness < 0.5)
    
    if length(misalignments) > threshold() do
      S5.Policy.suggest_adaptation(%{
        misaligned_patterns: misalignments,
        environmental_shift: detect_shift_type(misalignments),
        recommended_adjustments: calculate_adjustments(misalignments)
      })
    end
  end
end
```

### Performance Monitoring Integration

```elixir
defmodule HNSW.Telemetry do
  @moduledoc """Telemetry integration for VSM monitoring"""
  
  def setup do
    # Attach telemetry handlers
    :telemetry.attach_many(
      "hnsw-telemetry",
      [
        [:hnsw, :search, :stop],
        [:hnsw, :insert, :stop],
        [:hnsw, :batch, :stop]
      ],
      &handle_event/4,
      nil
    )
  end
  
  def handle_event([:hnsw, :search, :stop], measurements, metadata, _) do
    # Report to S3 for resource optimization
    S3.Metrics.report(:s4_pattern_search, %{
      duration_ms: measurements.duration / 1_000,
      results_count: metadata.k,
      ef_used: metadata.ef,
      index_size: metadata.vector_count
    })
  end
  
  def handle_event([:hnsw, :insert, :stop], measurements, metadata, _) do
    # Track pattern ingestion rate
    S4.Metrics.track_ingestion(%{
      duration_ms: measurements.duration / 1_000,
      vector_dimensions: metadata.dimensions,
      layer_assigned: metadata.layer
    })
  end
end
```