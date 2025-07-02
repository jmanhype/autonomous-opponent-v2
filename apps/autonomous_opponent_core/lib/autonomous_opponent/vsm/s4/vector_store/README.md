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

## Key Features

### 1. Multi-Layer Graph Structure
- **Layer 0**: Contains all vectors with dense connections
- **Higher Layers**: Progressively sparser for long-range navigation
- **Probabilistic Layer Assignment**: Layer(v) ~ -ln(uniform(0,1)) * mL

### 2. Construction Algorithm (M=16, mL=1/ln(2))
```elixir
def insert(state, vector, metadata) do
  # 1. Assign layer based on exponential decay probability
  node_layer = select_layer(state.ml_factor)
  
  # 2. Find nearest neighbors at each layer
  entry_point = state.entry_point
  nearest = search_layers(state, vector, entry_point, node_layer)
  
  # 3. Insert node and create bidirectional links
  new_node = create_node(vector, metadata, node_layer)
  connect_neighbors(state, new_node, nearest, state.m)
  
  # 4. Prune connections if needed (max M connections per layer)
  prune_connections(state, new_node.neighbors, state.m_max)
end
```

### 3. Search Algorithm (ef=200)
```elixir
def search(state, query_vector, k, ef \\ 200) do
  # 1. Start from entry point at top layer
  candidates = greedy_search_layers(state, query_vector, state.entry_point)
  
  # 2. Search at layer 0 with ef parameter
  w = search_layer_0(state, query_vector, candidates, ef)
  
  # 3. Return k nearest neighbors
  w
  |> Enum.sort_by(fn {distance, _} -> distance end)
  |> Enum.take(k)
end
```

## API Reference

### Core Operations

```elixir
# Start the index with custom parameters
{:ok, index} = HNSWIndex.start_link(
  m: 16,              # Number of bidirectional links per node
  ef_construction: 200, # Size of dynamic candidate list
  ef: 100,            # Search parameter (can be tuned per query)
  distance_metric: :cosine,
  max_elements: 1_000_000
)

# Insert a vector with metadata
vector = [0.1, 0.2, 0.3, ...]  # 128-dimensional
metadata = %{pattern_type: "user_behavior", source: "web_analytics"}
{:ok, node_id} = HNSWIndex.insert(index, vector, metadata)

# Search for k nearest neighbors
query = [0.15, 0.18, 0.32, ...]
{:ok, results} = HNSWIndex.search(index, query, k: 10, ef: 150)
# Returns: [{distance, node_id, vector, metadata}, ...]

# Batch operations for efficiency
vectors_with_metadata = [
  {vector1, metadata1},
  {vector2, metadata2},
  ...
]
{:ok, node_ids} = HNSWIndex.batch_insert(index, vectors_with_metadata)

# Save index to disk
{:ok, path} = HNSWIndex.save(index, "/path/to/index.hnsw")

# Load index from disk
{:ok, loaded_index} = HNSWIndex.load("/path/to/index.hnsw")
```

### Pattern-Specific Operations

```elixir
# Index S4 patterns directly
pattern = %S4Pattern{
  type: :environmental_anomaly,
  features: %{temperature: 0.8, pressure: 0.2, ...},
  timestamp: DateTime.utc_now()
}
{:ok, pattern_id} = PatternIndexer.index_pattern(pattern)

# Search for similar patterns
{:ok, similar_patterns} = PatternIndexer.find_similar(pattern, k: 5)

# Query by pattern characteristics
{:ok, matches} = PatternIndexer.query(%{
  type: :environmental_anomaly,
  time_range: {~U[2024-01-01 00:00:00Z], ~U[2024-01-02 00:00:00Z]},
  min_similarity: 0.85
})
```

## Configuration

### Optimal Parameters by Use Case

#### High Accuracy (Research/Analysis)
```elixir
{:ok, index} = HNSWIndex.start_link(
  m: 32,              # Higher M for better connectivity
  ef: 500,            # Higher ef for better recall
  distance_metric: :cosine
)
```

#### High Speed (Real-time Processing)
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
defmodule S4Integration do
  def process_scan(scan_data) do
    # Convert scan to feature vector
    vector = FeatureExtractor.extract(scan_data)
    
    # Index for future pattern matching
    {:ok, id} = PatternIndexer.index_pattern(%{
      vector: vector,
      type: :environmental_scan,
      metadata: %{
        timestamp: scan_data.timestamp,
        location: scan_data.location,
        sensors: scan_data.sensor_ids
      }
    })
    
    # Check for similar historical patterns
    {:ok, similar} = PatternIndexer.find_similar(vector, k: 10)
    
    # Analyze pattern evolution
    analyze_pattern_drift(similar)
  end
end
```

### VSM Cognitive Loop
The HNSW index serves as the pattern memory for S4's contribution to system-wide cognition:

```elixir
defmodule CognitiveIntegration do
  def cognitive_cycle(state) do
    # 1. Encode current state as vector
    state_vector = StateEncoder.encode(state)
    
    # 2. Retrieve similar past states
    {:ok, similar_states} = HNSWIndex.search(
      state.pattern_index, 
      state_vector, 
      k: 20
    )
    
    # 3. Extract successful action patterns
    successful_patterns = similar_states
    |> Enum.filter(fn {_, _, _, meta} -> meta.outcome == :success end)
    |> Enum.map(fn {_, _, _, meta} -> meta.action_sequence end)
    
    # 4. Synthesize new response
    synthesize_response(successful_patterns, state)
  end
end
```

## Advanced Usage

### Custom Distance Metrics
```elixir
defmodule CustomMetrics do
  def weighted_cosine(v1, v2, weights) do
    # Apply feature weights before cosine similarity
    weighted_v1 = Enum.zip(v1, weights) |> Enum.map(fn {v, w} -> v * w end)
    weighted_v2 = Enum.zip(v2, weights) |> Enum.map(fn {v, w} -> v * w end)
    
    DistanceMetrics.cosine(weighted_v1, weighted_v2)
  end
end

# Use custom metric
{:ok, index} = HNSWIndex.start_link(
  distance_fn: &CustomMetrics.weighted_cosine/3,
  distance_fn_args: [feature_weights]
)
```

### Index Maintenance
```elixir
# Remove old patterns
PatternIndexer.prune_before(~U[2024-01-01 00:00:00Z])

# Rebalance index after many deletions
{:ok, stats} = HNSWIndex.rebalance(index)

# Analyze index quality
{:ok, report} = HNSWIndex.analyze(index)
# Returns connectivity stats, layer distribution, etc.
```

## Implementation Details

### Graph Structure
- **Nodes**: Each vector is a node with metadata
- **Edges**: Bidirectional links between similar vectors
- **Layers**: Hierarchical organization for efficient navigation

### Concurrency Model
- **GenServer**: Single writer, multiple concurrent readers
- **ETS Tables**: Lock-free read operations
- **Batching**: Amortize lock contention for bulk operations

### Persistence Format
```elixir
%{
  version: 2,
  parameters: %{m: 16, ef_construction: 200, ...},
  nodes: %{
    node_id => %{
      vector: [...],
      metadata: %{...},
      layer: 2,
      neighbors: %{
        0 => [id1, id2, ...],  # Layer 0 neighbors
        1 => [id3, id4, ...],  # Layer 1 neighbors
        2 => [id5, id6, ...]   # Layer 2 neighbors
      }
    }
  },
  entry_point: node_id
}
```

## Testing

### Unit Tests
```bash
mix test test/autonomous_opponent/vsm/s4/vector_store/hnsw_index_test.exs
```

### Integration Tests
```bash
mix test test/integration/s4_pattern_indexing_test.exs
```

### Benchmarks
```bash
# Accuracy benchmarks
mix run lib/autonomous_opponent/vsm/s4/vector_store/benchmarks/accuracy_bench.exs

# Performance benchmarks
mix run lib/autonomous_opponent/vsm/s4/vector_store/benchmarks/perf_bench.exs
```

## Troubleshooting

### Common Issues

1. **High Memory Usage**
   - Reduce M parameter
   - Use dimensionality reduction on vectors
   - Enable periodic pruning of old patterns

2. **Poor Recall**
   - Increase ef parameter during search
   - Increase ef_construction during building
   - Verify distance metric matches data distribution

3. **Slow Inserts**
   - Use batch_insert for multiple vectors
   - Reduce ef_construction parameter
   - Consider sharding large indices

4. **Index Corruption**
   - Always use supervised shutdown
   - Enable write-ahead logging
   - Keep backup of critical indices

## References

1. [Efficient and robust approximate nearest neighbor search using Hierarchical Navigable Small World graphs](https://arxiv.org/abs/1603.09320)
2. [HNSW Original Implementation](https://github.com/nmslib/hnswlib)
3. [VSM Theory and S4's Role](../../../docs/vsm_theory.md)

## Changelog

### Version 2.0 (Current)

**New Features:**
- **Telemetry Integration**: Production monitoring with :telemetry events for all operations
- **Batch Search API**: Process multiple queries in parallel for improved throughput
- **Pattern Expiry**: Automatic and manual pruning of old patterns with timestamp tracking
- **Index Compaction**: Remove orphaned nodes and optimize graph connections
- **Index Versioning**: Forward-compatible persistence with automatic migration

**Improvements:**
- Added timestamp metadata to all inserted patterns
- Enhanced error handling in batch operations
- Optimized memory usage in graph traversal
- Better connection pruning for hub prevention

**Breaking Changes:**
- Persistence format updated to v2 (automatic migration supported)
- Insert now adds :inserted_at timestamp to metadata

### Version 1.0

**Initial Implementation:**
- Pure Elixir HNSW algorithm
- Cosine and Euclidean distance metrics
- Incremental index building
- ETS-based persistence
- S4 integration via PatternIndexer
- GenServer architecture for concurrent operations

## Future Enhancements

- [ ] Distributed index across multiple nodes
- [ ] GPU acceleration for distance calculations (NIF)
- [ ] Dynamic M and ef adjustment based on data characteristics
- [ ] Support for additional distance metrics (Manhattan, Hamming)
- [ ] Index merging for federated pattern learning
- [ ] Real-time index statistics dashboard