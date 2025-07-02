# Task 4: Implement Intelligence.VectorStore.HNSWIndex

## Description
Implement Hierarchical Navigable Small World (HNSW) index for S4 environmental scanning and pattern recognition. HNSW is a graph-based approach to approximate nearest neighbor search that provides excellent trade-offs between search quality, time complexity, and space usage.

## VSM Architectural Context

Within the Viable System Model (VSM), the HNSW index serves as a critical component of S4's "environmental memory":

- **S4 Intelligence Role**: S4 continuously scans the external environment for patterns, threats, and opportunities
- **Pattern Recognition**: HNSW enables rapid similarity search across millions of historical patterns
- **Variety Absorption**: High-dimensional indexing handles the complexity of environmental signals
- **Predictive Capability**: Similar past patterns inform predictions about future system states
- **Adaptation Loop**: S4 uses pattern matches to trigger S3 (Control) and S5 (Policy) adjustments

### Integration with VSM Subsystems

1. **S1 (Operations)**: Provides pattern data from operational activities
2. **S2 (Coordination)**: Uses pattern matches to identify coordination needs
3. **S3 (Control)**: Receives pattern-based recommendations for resource allocation
4. **S4 (Intelligence)**: Core location - manages environmental pattern memory
5. **S5 (Policy)**: Pattern trends inform policy adaptations

## Technical Decision: Pure Elixir Implementation

**Decision**: We chose a pure Elixir implementation over Native Implemented Functions (NIFs)

**Rationale**:
- **Fault Tolerance**: NIFs can crash the entire BEAM VM; pure Elixir maintains fault isolation
- **Maintainability**: Easier debugging, hot code reloading, and code comprehension
- **Sufficient Performance**: Benchmarks show <10ms search times are achievable in pure Elixir
- **VSM Alignment**: Follows the "implement rather than architect" principle from CLAUDE.md
- **Gradual Optimization**: Can add NIFs later for specific hot paths if needed

**Trade-offs Accepted**:
- ~2-3x slower than optimized C++ implementation
- Higher memory usage due to Erlang term overhead
- Limited SIMD optimization opportunities

These trade-offs are acceptable given S4's 10-second environmental scan cycle.

## Core Algorithm Overview

### HNSW Structure
- **Multi-layer graph**: Each layer is a proximity graph with different connectivity
- **Layer 0**: Contains all nodes with highest connectivity (M * 2 links)
- **Higher layers**: Progressively fewer nodes, used for efficient navigation
- **Node assignment**: Probabilistic layer assignment following exponential decay

### Key Parameters
- **M**: Number of bidirectional links per node (affects index quality and size)
- **ef_construction**: Size of dynamic candidate list during construction
- **ef**: Size of dynamic candidate list during search
- **mL**: Normalization factor for layer assignment probability (1/ln(2.0))

## Algorithm Complexity Analysis

### Time Complexity
- **Insert**: O(log n × M × ef_construction) where n = number of vectors
  - Layer assignment: O(1) probabilistic selection
  - Neighbor search: O(log n × ef_construction) traversal through layers
  - Connection updates: O(M²) for pruning excess connections
- **Search**: O(log n × ef) for approximate k-NN search
  - Layer descent: O(log n) expected layers to traverse
  - Layer 0 search: O(ef × M) neighbor evaluations
  - Result extraction: O(k × log k) for k nearest neighbors
- **Delete** (rarely used): O(M² × L) where L = number of layers
  - Find node: O(log n) search operation
  - Update neighbors: O(M × L) bidirectional link removal
  - Rebalance: O(M²) connection reconstruction

### Space Complexity
- **Memory per vector**: O(d + M × L) where d = dimensions, L = expected log n layers
  - Vector storage: d × 4 bytes (32-bit floats)
  - Graph connections: M × L × 8 bytes (64-bit node IDs)
  - Metadata overhead: ~100 bytes per node
- **Total index memory**: O(n × (d + M × log n))
  - Example: 1M vectors, 128d, M=16 ≈ 2.5GB total

### Practical Impact
For S4's use case with 100k environmental patterns:
- Insert: ~3-5ms per pattern (acceptable for 10-second scan cycle)
- Search: ~10-12ms for k=20 similar patterns
- Memory: ~300MB for complete index

## Layer Assignment Mathematics

### Probability Distribution
The layer assignment follows an exponential decay distribution:
- **P(layer = 0)** = 1.0 (all nodes exist in base layer)
- **P(layer ≥ l)** = e^(-l/mL) where mL = 1/ln(2.0)
- **Expected max layer** = -ln(n) × mL ≈ log₂(n)

### Why mL = 1/ln(2.0)?
This specific value ensures optimal layer distribution:
```
mL = 1/ln(2.0) ≈ 1.442695
```

This creates a probability where:
- 100% of nodes appear in layer 0
- ~50% of nodes appear in layer 1 (e^(-1/1.44) ≈ 0.5)
- ~25% of nodes appear in layer 2 (e^(-2/1.44) ≈ 0.25)
- ~12.5% of nodes appear in layer 3, and so on...

### Concrete Examples for Different Dataset Sizes
| Dataset Size | Expected Layers | Layer 0 | Layer 1 | Layer 2 | Layer 3 |
|-------------|-----------------|---------|---------|---------|---------|
| 1,000       | ~10            | 1,000   | ~500    | ~250    | ~125    |
| 10,000      | ~13            | 10,000  | ~5,000  | ~2,500  | ~1,250  |
| 100,000     | ~17            | 100,000 | ~50,000 | ~25,000 | ~12,500 |
| 1,000,000   | ~20            | 1M      | ~500K   | ~250K   | ~125K   |

This exponential decay ensures:
1. Efficient long-range navigation in upper layers
2. Dense local connectivity in lower layers
3. Logarithmic hop count for any search path

## Known Failure Modes and Mitigations

### 1. Graph Disconnection
**Risk**: Poor parameter choices or edge cases can create isolated subgraphs, making some vectors unreachable.

**Detection**:
- Monitor average shortest path length between random node pairs
- Track percentage of successful searches reaching all candidates
- Alert if any insert operation creates an isolated component

**Mitigation**:
- Ensure M ≥ 2 (minimum connectivity for robustness)
- Implement connectivity check during insert:
  ```elixir
  if not connected_to_main_graph?(new_node) do
    force_connection_to_entry_point(new_node)
  end
  ```
- Add periodic connectivity verification in background process

### 2. Hub Formation (Over-Connected Nodes)
**Risk**: Popular vectors accumulate excessive connections, becoming bottlenecks that slow down all searches.

**Detection**:
- Track node degree distribution: `degree_stats = calculate_degree_distribution(index)`
- Alert when max_degree > 3 × M × expected_layers
- Monitor search path concentration through specific nodes

**Mitigation**:
- Implement degree-based pruning with diversity heuristic:
  ```elixir
  def prune_connections(node, candidates, m) do
    # Prefer diverse neighbors over closest ones
    candidates
    |> group_by_region()
    |> take_diverse_sample(m)
  end
  ```
- Use soft degree limits: gradually increase distance threshold for hub nodes
- Consider node splitting when degree exceeds 5 × M

### 3. Dimension Curse Effects
**Risk**: In very high dimensions (>500), distance metrics become less meaningful, degrading search quality.

**Detection**:
- Monitor relative contrast: `avg_distance / min_distance` ratio
- Track recall degradation as dimensions increase
- Alert when distance distribution becomes too uniform

**Mitigation**:
- Apply dimensionality reduction before indexing:
  ```elixir
  reduced_vector = PCA.reduce(vector, target_dims: 128)
  ```
- Use learned embeddings that preserve semantic similarity
- Consider product quantization for extreme dimensions

### 4. Memory Exhaustion During Construction
**Risk**: Large batch inserts can cause memory spikes exceeding available RAM.

**Detection**:
- Monitor process memory: `:erlang.memory(:processes)`
- Track ETS table size growth rate
- Set memory usage alerts at 80% of available RAM

**Mitigation**:
- Implement streaming batch inserts with backpressure:
  ```elixir
  vectors
  |> Stream.chunk_every(100)
  |> Stream.map(&insert_batch/1)
  |> Stream.run()
  ```
- Use disk-based buffer for large import operations
- Enable swap space as emergency fallback

### Monitoring Recommendations

Deploy these monitors for production HNSW indices:

1. **Health Metrics**:
   - Graph connectivity percentage
   - Node degree distribution (p50, p95, p99, max)
   - Layer distribution vs. expected theoretical distribution

2. **Performance Metrics**:
   - Insert latency by layer count
   - Search latency by result set size
   - Recall@k for sample queries

3. **Resource Metrics**:
   - Memory usage per vector
   - CPU usage during peak operations
   - Disk I/O for persistence operations

4. **Alerts**:
   - Connectivity < 99.9%
   - Max node degree > 5 × M × layers
   - Search recall < 90%
   - Memory usage > 85% of limit

## Implementation Details

### 1. Core Data Structures

```elixir
defmodule HNSWNode do
  defstruct [
    :id,           # Unique identifier
    :vector,       # Feature vector
    :metadata,     # Associated data
    :neighbors,    # Map of layer => [neighbor_ids]
    :layer         # Highest layer this node appears in
  ]
end

defmodule HNSWIndex do
  defstruct [
    :nodes,              # Map of id => HNSWNode
    :entry_point,        # ID of entry point node
    :m,                  # Max connections per layer
    :ef_construction,    # Dynamic list size for construction
    :ef,                 # Dynamic list size for search
    :ml,                 # Layer assignment normalization
    :distance_metric,    # :cosine or :euclidean
    :level_multiplier,   # For layer assignment probability
    :seed                # Random seed for reproducibility
  ]
end
```

### 2. Algorithm Implementation Steps

#### a. Initialization
- Create empty index with configurable parameters
- Set default M=16, ef_construction=200, ef=200
- Initialize random number generator with seed

#### b. Insert Operation
1. Calculate layer for new node using exponential decay distribution
2. Find nearest neighbors using search algorithm from entry point
3. Connect new node to M nearest neighbors per layer
4. Prune connections of neighbors if they exceed M
5. Update entry point if new node has higher layer

#### c. Search Operation
1. Start from entry point at highest layer
2. Greedily traverse to nearest neighbor until no improvement
3. Move down to next layer and repeat
4. At layer 0, use ef-sized candidate list for final search
5. Return k nearest neighbors

#### d. Distance Calculations
- **Cosine similarity**: 1 - (dot_product(a,b) / (norm(a) * norm(b)))
- **Euclidean distance**: sqrt(sum((a[i] - b[i])^2))
- Implement both with SIMD optimizations where possible

### 3. Pure Elixir Implementation

Start with pure Elixir implementation for maintainability:
- Use `:gb_sets` for priority queues
- Implement concurrent updates with GenServer
- Use ETS tables for large-scale storage
- Add Flow for parallel batch operations

### 4. Performance Optimizations

#### Phase 1: Pure Elixir Optimizations
- Implement vector operations using Nx (Numerical Elixir)
- Use binary pattern matching for vector operations
- Cache frequently accessed neighbors
- Implement lazy loading for large indices

#### Phase 2: NIF Implementation (Future)
- Create C++ NIF for distance calculations
- Implement SIMD vectorized operations
- Use memory-mapped files for persistence
- Add CPU cache-friendly data layouts

### 5. Persistence Strategy

```elixir
defmodule HNSWIndex.Persistence do
  # Binary format for efficient storage
  def save(index, path) do
    # Header: version, parameters, node count
    # Nodes: id, vector_size, vector, layer, neighbors
    # Use :erlang.term_to_binary with compression
  end
  
  def load(path) do
    # Read header, validate version
    # Reconstruct index with memory mapping
    # Verify integrity with checksums
  end
end
```

### 6. Concurrent Processing

- **Insert operations**: Queue-based with batch processing
- **Search operations**: Read-only, fully concurrent
- **Index updates**: Copy-on-write for consistency
- **Pruning**: Background process for connection optimization

## Expected API and Integration Examples

### Core API

```elixir
# Start index with S4-optimized configuration
{:ok, index} = VectorStore.HNSWIndex.start_link(
  name: :s4_pattern_index,
  m: 16,                    # Bidirectional links per node
  ef: 200,                  # Dynamic list size for search
  ef_construction: 200,     # Dynamic list size during construction
  distance_metric: :cosine, # For normalized pattern vectors
  persist_path: "/var/lib/autonomous_opponent/s4_patterns.hnsw",
  max_elements: 10_000_000  # Pre-allocate for 10M patterns
)

# Insert pattern vector with rich metadata
pattern_vector = S4.Intelligence.extract_features(environmental_scan)
{:ok, node_id} = VectorStore.HNSWIndex.insert(index, pattern_vector, %{
  source: :environmental_scan,
  timestamp: DateTime.utc_now(),
  scan_id: scan.id,
  variety_level: calculate_variety(scan),
  confidence: scan.confidence,
  entities_detected: MapSet.size(scan.entities),
  s3_alert_level: get_current_alert_level(),  # Cross-subsystem context
  s5_policy_version: get_active_policy()       # Policy alignment
})

# Search for similar historical patterns
{:ok, neighbors} = VectorStore.HNSWIndex.search(index, query_vector, 20)
# Returns list of: %{id: node_id, distance: float, metadata: map}

# Batch operations for efficiency
vector_batch = Enum.map(patterns, &extract_features/1)
{:ok, node_ids} = VectorStore.HNSWIndex.insert_batch(index, vector_batch)

# Get index statistics
stats = VectorStore.HNSWIndex.stats(index)
# Returns: %{vector_count: integer, memory_bytes: integer, layer_distribution: map}
```

### S4 Environmental Scanning Integration

```elixir
defmodule S4.Intelligence.PatternIndexer do
  @doc """
  Index environmental scan data for future pattern matching.
  This is called every 10 seconds by S4's scan cycle.
  """
  def index_scan(scan_data) do
    # Convert scan to feature vector
    vector = extract_features(scan_data)
    
    # Add to HNSW index with metadata
    HNSWIndex.insert(@index, vector, %{
      timestamp: DateTime.utc_now(),
      scan_type: scan_data.type,
      entities: length(scan_data.entities),
      confidence: scan_data.confidence,
      # VSM cross-subsystem context
      s1_load: get_operational_load(),
      s2_conflicts: count_coordination_issues(),
      s3_resources: get_resource_allocation(),
      s5_constraints: get_active_policies()
    })
  end
  
  @doc """
  Find historical precedents for current situation.
  Used by S4 to predict likely outcomes.
  """
  def find_precedents(current_scan, k \ 50) do
    vector = extract_features(current_scan)
    
    case HNSWIndex.search(@index, vector, k) do
      {:ok, similar_patterns} ->
        # Weight by recency and confidence
        similar_patterns
        |> Enum.map(&weight_by_relevance(&1, current_scan))
        |> Enum.filter(& &1.weight > 0.7)
        |> Enum.sort_by(& &1.weight, :desc)
        |> Enum.take(20)
        
      {:error, reason} ->
        Logger.warn("Pattern search failed: #{inspect(reason)}")
        # Fallback to statistical pattern matching
        S4.Intelligence.statistical_match(current_scan)
    end
  end
end
```

### 2. Pattern Recognition Pipeline
1. Extract features from environmental data
2. Search for similar historical patterns
3. Aggregate results for pattern detection
4. Feed insights back to S4 decision-making

### 3. Real-time Updates
- Subscribe to S4 event bus for new patterns
- Batch insertions for efficiency
- Maintain separate indices for different pattern types
- Periodic rebalancing for optimal performance

## Test Strategy

### 1. Unit Tests
```elixir
# test/hnsw_index_test.exs
- Test insert/search operations
- Verify distance calculations
- Test edge cases (empty index, duplicate vectors)
- Validate layer assignment distribution
- Test concurrent operations
```

### 2. Property-Based Tests
```elixir
# Using StreamData
- Invariant: k-NN search returns k or fewer results
- Property: Distance ordering is preserved
- Property: Recall improves with higher ef
- Property: Memory usage scales with M
```

### 3. Performance Benchmarks
```elixir
# benchmarks/hnsw_bench.exs
- Insert throughput vs. index size
- Search latency vs. index size
- Recall vs. ef parameter
- Memory usage vs. number of vectors
- Comparison with brute-force search
```

### 4. Integration Tests
```elixir
# test/integration/s4_hnsw_test.exs
- Full S4 pattern detection pipeline
- Persistence and recovery
- Event bus integration
- Resource usage under load
```

### 5. Accuracy Validation
- Use standard datasets (SIFT, GIST)
- Measure recall@k for various k
- Compare with reference implementations
- Validate distance calculations

## Memory Usage Projections

| Vectors | Dimensions | M  | Memory (MB) |
|---------|------------|----|-------------|
| 10K     | 128        | 16 | ~25         |
| 100K    | 128        | 16 | ~250        |
| 1M      | 128        | 16 | ~2,500      |
| 10K     | 768        | 16 | ~80         |

## Concrete Performance Requirements

### Latency Requirements
- **Insert latency**: < 5ms for vectors up to 256 dimensions
- **Search latency**: < 10ms for k=10 neighbors in datasets up to 100k vectors
- **Batch insert**: < 100ms for 100 vectors (amortized 1ms per vector)
- **Persistence save**: < 1 second for 100k vectors
- **Index restore**: < 5 seconds for 100k vectors

### Throughput Requirements
- **Concurrent searches**: > 1000 searches/second with 8 concurrent clients
- **Mixed workload**: > 500 searches/second with 10% inserts
- **Sustained insert rate**: > 200 vectors/second for continuous operation

### Accuracy Requirements
- **Recall@10**: > 95% with ef=200 (percentage of true neighbors found)
- **Recall@100**: > 98% with ef=500
- **Precision**: Not critical - false positives filtered by S4 pattern validator

### Resource Requirements
- **Memory usage**: < 5KB per vector including metadata and graph structure
- **CPU usage**: < 50% of single core during normal operation
- **Startup time**: < 100ms for empty index, < 5s for 100k vector restore

### Scalability Requirements
- **Vector capacity**: Support up to 10M vectors in single index
- **Dimension support**: 10 to 1024 dimensions
- **Concurrent clients**: Support 100+ concurrent operations

## Error Handling

### Graceful Degradation
- Fall back to exact search for small indices
- Handle out-of-memory conditions
- Recover from corrupted persistence files
- Validate vector dimensions on insert

### Monitoring
- Track search latency percentiles
- Monitor recall metrics
- Alert on memory pressure
- Log index statistics

## Future Enhancements

### Phase 1 (Current)
- Pure Elixir implementation
- Basic persistence
- S4 integration
- Performance benchmarks

### Phase 2
- NIF for distance calculations
- SIMD optimizations
- Distributed index sharding
- GPU acceleration experiments

### Phase 3
- Dynamic index optimization
- Learned index structures
- Quantum-resistant hashing
- Advanced pruning strategies

## Dependencies
- **Nx**: Numerical computations
- **Flow**: Parallel processing
- **StreamData**: Property-based testing
- **Benchee**: Performance benchmarking

## Implementation Status
This file tracks the implementation of Task 4.

<!-- Triggering CI/CD check with updated OAuth workflows -->

@claude Please implement this task according to the specifications above.
