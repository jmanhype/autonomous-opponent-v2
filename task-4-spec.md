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

### Visual Algorithm Representation

```
Multi-Layer Graph Structure (HNSW):

Layer 3: O-------O                    (Sparse, long-range connections)
         |       |
Layer 2: O---O---O---O                (Medium density connections)
         |   |   |   |
Layer 1: O-O-O-O-O-O-O-O              (Denser connections)
         | | | | | | | |
Layer 0: O-O-O-O-O-O-O-O-O-O-O-O-O    (All nodes, dense connections)

Search Path Example:
Entry → L3: Jump to nearest neighbor → L2: Refine search → L1: Get closer → L0: Find exact k-NN

Key Properties:
- Higher layers: Fewer nodes, longer jumps (highway)
- Lower layers: More nodes, local refinement (streets)
- Layer 0: Contains ALL vectors (neighborhood)
```

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

### Capacity Planning for Production

Based on S4's operational requirements and 10-second environmental scan cycle:

**Daily Pattern Volume:**
- Scans per day: 8,640 (24 hours × 60 minutes × 6 per minute)
- With pattern detection rate ~30%: ~2,600 patterns/day
- Peak hours may see 2-3x average: ~500 patterns/hour peak

**Monthly and Yearly Projections:**
- Monthly accumulation: ~78,000 patterns (2,600 × 30)
- Quarterly accumulation: ~234,000 patterns
- Yearly capacity needed: ~950,000 patterns

**Memory Requirements by Time Horizon:**
| Retention Period | Pattern Count | Memory Usage | Disk Space (with metadata) |
|-----------------|---------------|--------------|---------------------------|
| 1 week          | ~18,200       | ~55MB        | ~150MB                   |
| 1 month         | ~78,000       | ~235MB       | ~650MB                   |
| 3 months        | ~234,000      | ~700MB       | ~2GB                     |
| 6 months        | ~468,000      | ~1.4GB       | ~4GB                     |
| 1 year          | ~950,000      | ~2.8GB       | ~8GB                     |

**Recommendations:**
1. **Default Configuration**: 3-month retention with automatic archival
   - Provides sufficient history for pattern analysis
   - Manageable memory footprint (~700MB)
   - Allows for seasonal pattern detection

2. **Archival Strategy**: 
   - Keep full vectors for 3 months
   - Archive older patterns with compressed representations
   - Maintain metadata and pattern signatures indefinitely

3. **Scaling Triggers**:
   - At 500K patterns: Consider index sharding
   - At 1M patterns: Implement distributed indexing
   - At 5M patterns: Move to specialized vector database

4. **Hardware Planning**:
   - Minimum: 4GB RAM for 3-month retention + system overhead
   - Recommended: 8GB RAM for comfortable operation
   - SSD storage: 20GB for index + backups + growth buffer

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

### Visual Layer Distribution Graph

Expected layer distribution for a 100,000 node HNSW index:

```
Layer 6: █                                        312 nodes   (0.3%)
Layer 5: ██                                       625 nodes   (0.6%)
Layer 4: ████                                    1,250 nodes  (1.3%)
Layer 3: ████████                                2,500 nodes  (2.5%)
Layer 2: ████████████████                        5,000 nodes  (5.0%)
Layer 1: ████████████████████████████████       10,000 nodes  (10%)
Layer 0: ████████████████████████████████████   100,000 nodes (100%)

         0    20K   40K   60K   80K   100K
         └─────┴─────┴─────┴─────┴─────┘
                 Number of Nodes
```

This exponential distribution ensures:
- Efficient highway routing through sparse upper layers
- Detailed local search in dense lower layers
- Logarithmic path length between any two nodes
- Balanced memory usage across layers

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

### Distance Metric Selection Guide

#### Comprehensive Decision Matrix

| Metric    | Speed | Memory | Scale Invariant | Sparse Data | High Dimensions | Use When |
|-----------|-------|--------|-----------------|-------------|-----------------|----------|
| Cosine    | 8/10  | Same   | ✓ Yes          | ✓ Excellent | ✓ Good         | Text/Normalized vectors |
| Euclidean | 10/10 | Same   | ✗ No           | ✗ Poor      | ⚠ OK           | Raw measurements |
| Manhattan | 9/10  | Same   | ✗ No           | ⚠ OK        | ✓ Good         | Grid-based data |
| Hamming   | 10/10 | Less   | ✓ Yes          | ✓ Excellent | ✓ Excellent    | Binary/Categorical |

#### Detailed Selection Guide by Data Type

| Data Type | Recommended Metric | Rationale | Example |
|-----------|-------------------|-----------|---------|
| Normalized text embeddings | Cosine | Direction matters more than magnitude | Word2Vec, BERT |
| Raw sensor readings | Euclidean | Absolute differences are meaningful | Temperature, pressure |
| Binary features | Hamming (future) | Bit differences indicate dissimilarity | Feature flags |
| Probability distributions | JS Divergence (future) | Statistical distance for distributions | Topic models |
| Geographic coordinates | Euclidean | Physical distance correlation | Lat/long pairs |
| User preferences | Cosine | Relative preferences matter | Rating vectors |
| Time series patterns | DTW (future) | Temporal alignment needed | Stock prices |

#### Concrete Distance Metric Examples with Environmental Sensor Data

```elixir
# Example 1: Raw sensor readings - Use Euclidean distance
sensor_data = %{
  temperature_c: 22.5,      # Celsius
  humidity_pct: 65.0,       # Percentage (0-100)
  pressure_hpa: 1013.25,    # Hectopascals
  air_quality_idx: 0.8,     # Index (0-1)
  wind_speed_ms: 3.2        # Meters per second
}

# Problem: Different scales! Temperature ~20, pressure ~1000
# Solution: Normalize by scale before using Euclidean distance
def normalize_sensor_data(data) do
  %{
    temperature_c: data.temperature_c / 50.0,      # Typical range: -10 to 40°C
    humidity_pct: data.humidity_pct / 100.0,       # Already percentage
    pressure_hpa: (data.pressure_hpa - 1000) / 50, # Typical range: 950-1050
    air_quality_idx: data.air_quality_idx,         # Already normalized
    wind_speed_ms: data.wind_speed_ms / 20.0       # Typical max: 20 m/s
  }
end

# Convert to vector for HNSW
sensor_vector = normalize_sensor_data(sensor_data) |> Map.values()
# Result: [0.45, 0.65, 0.265, 0.8, 0.16]

# Example 2: Pattern proportions - Use Cosine distance
pattern_data = %{
  anomaly_signatures: 15,
  normal_behaviors: 285,
  coordination_conflicts: 7,
  resource_warnings: 3
}

# For proportional data, magnitude doesn't matter - only relative ratios
total = Enum.sum(Map.values(pattern_data))
pattern_vector = pattern_data
  |> Map.values()
  |> Enum.map(& &1 / total)
# Result: [0.048, 0.919, 0.023, 0.010] - automatically normalized by cosine

# Example 3: S4 Environmental Scan - Mixed features require careful encoding
scan_data = %{
  # Continuous values - normalize by expected range
  variety_level: 0.73,              # Already 0-1
  entropy_measure: 4.2,             # Normalize by max entropy ~10
  pattern_density: 156,             # Patterns per scan, normalize by 1000
  
  # Categorical features - one-hot encode
  threat_level: :medium,            # Convert to [0, 1, 0] for [low, medium, high]
  scan_region: :north_america,      # Convert to binary vector
  
  # Temporal features - cyclical encoding
  hour_of_day: 14,                  # Convert to sin/cos pair
  day_of_week: 3                    # Wednesday, convert to sin/cos
}

def encode_environmental_scan(scan) do
  continuous = [
    scan.variety_level,
    scan.entropy_measure / 10.0,
    scan.pattern_density / 1000.0
  ]
  
  threat_encoding = case scan.threat_level do
    :low -> [1, 0, 0]
    :medium -> [0, 1, 0]
    :high -> [0, 0, 1]
  end
  
  # Cyclical encoding preserves circular nature of time
  hour_sin = :math.sin(2 * :math.pi * scan.hour_of_day / 24)
  hour_cos = :math.cos(2 * :math.pi * scan.hour_of_day / 24)
  day_sin = :math.sin(2 * :math.pi * scan.day_of_week / 7)
  day_cos = :math.cos(2 * :math.pi * scan.day_of_week / 7)
  
  continuous ++ threat_encoding ++ [hour_sin, hour_cos, day_sin, day_cos]
end

# Insert into HNSW with appropriate metadata
vector = encode_environmental_scan(scan_data)
HNSWIndex.insert(index, vector, %{
  timestamp: DateTime.utc_now(),
  raw_data: scan_data,
  encoding_version: "v2.1",
  distance_metric: :cosine  # Best for mixed normalized features
})
```

**Key Insights:**
1. **Scale Normalization is Critical**: Raw sensor values often have vastly different ranges
2. **Choose Metric Based on Meaning**: Euclidean for absolute differences, Cosine for proportions
3. **Categorical Encoding Matters**: One-hot encoding preserves distance semantics
4. **Temporal Features Need Special Care**: Cyclical encoding prevents artificial boundaries

For S4 environmental patterns, we default to **cosine** since patterns are normalized feature vectors where relative proportions matter more than absolute values.

#### Decision Process Flowchart:
```
Start → Is data normalized? 
         ├─ Yes → Use Cosine (scale-invariant)
         └─ No → Do absolute values matter?
                  ├─ Yes → Is data high-dimensional (>100)?
                  │        ├─ Yes → Consider dimension reduction + Euclidean
                  │        └─ No → Use Euclidean
                  └─ No → Normalize first, then use Cosine
```

#### Performance Characteristics:
| Metric | Computation | Cache Efficiency | SIMD Potential |
|--------|-------------|------------------|----------------|
| Euclidean | n multiplications + n additions + 1 sqrt | High | Excellent |
| Cosine | 3n multiplications + 2n additions + 1 sqrt | Medium | Good |
| Manhattan | n subtractions + n abs | Very High | Good |

**Implementation Notes:**
- Euclidean is ~20% faster than Cosine (no normalization overhead)
- Cosine is more robust to scale differences between features
- Both metrics benefit from SIMD optimizations in future NIF implementation
- For sparse vectors with >90% zeros, consider specialized sparse implementations

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

### 6. S4 Integration Testing Examples

```elixir
defmodule S4IntegrationTest do
  use ExUnit.Case
  alias VectorStore.HNSWIndex
  alias S4.Intelligence.PatternIndexer
  
  @doc """
  Test complete pattern detection pipeline within S4's 10-second scan cycle
  """
  test "detects environmental anomalies within scan cycle time constraints" do
    # Setup: Insert historical anomaly patterns
    {:ok, index} = HNSWIndex.start_link(name: :test_index, m: 16, ef: 200)
    
    # Generate 100 known anomaly patterns
    anomaly_patterns = for i <- 1..100 do
      %{
        vector: generate_anomaly_pattern(i),
        metadata: %{
          type: :environmental_anomaly,
          severity: Enum.random([:low, :medium, :high]),
          timestamp: DateTime.add(DateTime.utc_now(), -i * 3600, :second),
          detected_by: "sensor_#{rem(i, 10)}"
        }
      }
    end
    
    # Index all historical patterns
    Enum.each(anomaly_patterns, fn pattern ->
      {:ok, _} = HNSWIndex.insert(index, pattern.vector, pattern.metadata)
    end)
    
    # Simulate new environmental scan with potential anomaly
    new_scan = %{
      vector: generate_test_anomaly_vector(),
      timestamp: DateTime.utc_now(),
      sensors: ["sensor_1", "sensor_2", "sensor_5"],
      readings: %{temperature: 45.2, pressure: 1.5, humidity: 0.85}
    }
    
    # Measure detection time - MUST complete within S4's cycle
    {time_μs, result} = :timer.tc(fn ->
      {:ok, similar_patterns} = HNSWIndex.search(index, new_scan.vector, k: 10)
      
      # Process results to identify anomaly type
      anomaly_detected = similar_patterns
      |> Enum.filter(fn {distance, _, _, meta} -> 
        meta.type == :environmental_anomaly && distance < 0.1
      end)
      |> length() > 0
      
      {anomaly_detected, similar_patterns}
    end)
    
    # Assert timing constraints
    assert time_μs < 10_000_000, "Detection took #{time_μs/1000}ms, exceeding 10s limit"
    assert time_μs < 5_000_000, "Detection should complete well within 5s for safety margin"
    
    # Assert detection accuracy
    {anomaly_detected, similar_patterns} = result
    assert anomaly_detected, "Failed to detect known anomaly pattern"
    assert length(similar_patterns) == 10, "Should return exactly k=10 results"
  end
  
  @doc """
  Test pattern indexing throughput for continuous S4 scanning
  """
  test "maintains indexing throughput under continuous load" do
    {:ok, index} = HNSWIndex.start_link(name: :throughput_test, m: 16, ef: 200)
    
    # S4 generates ~6 scans per minute, test 10 minutes of operation
    scan_count = 60
    scan_interval = 10_000  # 10 seconds in milliseconds
    
    # Track indexing times
    indexing_times = for scan_num <- 1..scan_count do
      scan_data = generate_environmental_scan(scan_num)
      
      {time_μs, _} = :timer.tc(fn ->
        PatternIndexer.index_scan(index, scan_data)
      end)
      
      # Simulate scan interval
      remaining_time = scan_interval - div(time_μs, 1000)
      if remaining_time > 0, do: Process.sleep(remaining_time)
      
      time_μs
    end
    
    # Calculate statistics
    avg_time = Enum.sum(indexing_times) / length(indexing_times)
    max_time = Enum.max(indexing_times)
    p99_time = Enum.at(Enum.sort(indexing_times), round(0.99 * scan_count))
    
    # Assert performance requirements
    assert avg_time < 1_000_000, "Average indexing time #{avg_time/1000}ms exceeds 1s"
    assert max_time < 5_000_000, "Max indexing time #{max_time/1000}ms exceeds 5s"
    assert p99_time < 3_000_000, "P99 indexing time #{p99_time/1000}ms exceeds 3s"
    
    # Verify index growth
    stats = HNSWIndex.stats(index)
    assert stats.vector_count >= scan_count * 0.3, "Too few patterns indexed"
    assert stats.vector_count <= scan_count, "Unexpected pattern duplication"
  end
  
  @doc """
  Test cross-subsystem pattern correlation
  """
  test "correlates patterns across VSM subsystems" do
    {:ok, index} = HNSWIndex.start_link(name: :correlation_test, m: 16, ef: 200)
    
    # Insert patterns from different VSM subsystems
    s1_pattern = %{
      vector: encode_operational_metrics(%{efficiency: 0.65, errors: 15}),
      metadata: %{source: :s1_operations, timestamp: DateTime.utc_now()}
    }
    
    s2_pattern = %{
      vector: encode_conflict_data(%{subsystems: [:manufacturing, :shipping]}),
      metadata: %{source: :s2_coordination, timestamp: DateTime.utc_now()}
    }
    
    s3_pattern = %{
      vector: encode_resource_usage(%{cpu: 0.92, memory: 0.88}),
      metadata: %{source: :s3_control, timestamp: DateTime.utc_now()}
    }
    
    # Index all patterns
    {:ok, s1_id} = HNSWIndex.insert(index, s1_pattern.vector, s1_pattern.metadata)
    {:ok, s2_id} = HNSWIndex.insert(index, s2_pattern.vector, s2_pattern.metadata)
    {:ok, s3_id} = HNSWIndex.insert(index, s3_pattern.vector, s3_pattern.metadata)
    
    # Search for correlations from S1 pattern
    {:ok, correlations} = HNSWIndex.search(index, s1_pattern.vector, k: 10)
    
    # Should find patterns from other subsystems if they're correlated
    sources = correlations
    |> Enum.map(fn {_, _, _, meta} -> meta.source end)
    |> Enum.uniq()
    
    # In a properly functioning system, operational issues (S1) should correlate
    # with resource constraints (S3) and coordination conflicts (S2)
    assert length(sources) >= 2, "Should find cross-subsystem correlations"
  end
  
  @doc """
  Test pattern persistence and recovery
  """
  test "recovers index after system restart" do
    persist_path = "/tmp/test_hnsw_#{:os.system_time(:nanosecond)}.index"
    
    # Create and populate index
    {:ok, index} = HNSWIndex.start_link(
      name: :persist_test,
      m: 16,
      ef: 200,
      persist_path: persist_path
    )
    
    # Insert test patterns
    patterns = for i <- 1..1000 do
      %{
        vector: :rand.uniform() |> List.duplicate(128),
        metadata: %{id: i, timestamp: DateTime.utc_now()}
      }
    end
    
    Enum.each(patterns, fn p ->
      HNSWIndex.insert(index, p.vector, p.metadata)
    end)
    
    # Save index
    :ok = HNSWIndex.save(index, persist_path)
    stats_before = HNSWIndex.stats(index)
    
    # Stop the index process
    GenServer.stop(index)
    
    # Load index in new process
    {:ok, recovered_index} = HNSWIndex.load(persist_path)
    stats_after = HNSWIndex.stats(recovered_index)
    
    # Verify recovery
    assert stats_after.vector_count == stats_before.vector_count
    assert stats_after.parameters == stats_before.parameters
    
    # Test search functionality after recovery
    test_vector = :rand.uniform() |> List.duplicate(128)
    {:ok, results} = HNSWIndex.search(recovered_index, test_vector, k: 10)
    assert length(results) == 10
    
    # Cleanup
    File.rm!(persist_path)
  end
  
  # Helper functions
  defp generate_anomaly_pattern(seed) do
    :rand.seed(:exsss, {seed, seed, seed})
    # Anomaly patterns have specific characteristics
    base = :rand.uniform() |> List.duplicate(64)
    spike = List.duplicate(0.9 + :rand.uniform() * 0.1, 64)
    base ++ spike
  end
  
  defp generate_test_anomaly_vector do
    # Similar to training anomalies but with slight variation
    base = :rand.uniform() |> List.duplicate(64)
    spike = List.duplicate(0.95, 64)
    base ++ spike
  end
  
  defp generate_environmental_scan(scan_num) do
    %{
      scan_id: scan_num,
      timestamp: DateTime.utc_now(),
      patterns_detected: :rand.uniform(3),
      vector: :rand.uniform() |> List.duplicate(128),
      confidence: 0.7 + :rand.uniform() * 0.3
    }
  end
  
  defp encode_operational_metrics(metrics) do
    # Simple encoding for testing
    [metrics.efficiency] ++ List.duplicate(metrics.errors / 100, 127)
  end
  
  defp encode_conflict_data(conflict) do
    # Hash subsystems to vector
    hash = :erlang.phash2(conflict.subsystems)
    Float.rem(hash / 1000, 1.0) |> List.duplicate(128)
  end
  
  defp encode_resource_usage(usage) do
    [usage.cpu, usage.memory] ++ List.duplicate(0.5, 126)
  end
end
```

## Memory Usage Projections

| Vectors | Dimensions | M  | Memory (MB) |
|---------|------------|----|-------------|
| 10K     | 128        | 16 | ~25         |
| 100K    | 128        | 16 | ~250        |
| 1M      | 128        | 16 | ~2,500      |
| 10K     | 768        | 16 | ~80         |

### Memory Profiling Example

Monitor and profile memory usage during index operations:

```elixir
defmodule HNSWMemoryProfiler do
  @doc """
  Profile memory usage during batch vector insertion
  """
  def profile_memory_usage(index, vector_count \\ 1000, dimensions \\ 128) do
    # Capture initial memory state
    :erlang.garbage_collect()
    Process.sleep(100)  # Let GC settle
    
    initial_memory = %{
      total: :erlang.memory(:total),
      processes: :erlang.memory(:processes),
      ets: :erlang.memory(:ets),
      binary: :erlang.memory(:binary)
    }
    
    # Get initial index stats
    initial_stats = HNSWIndex.stats(index)
    
    # Insert batch of vectors
    vectors = for i <- 1..vector_count do
      vector = :rand.uniform() |> List.duplicate(dimensions)
      metadata = %{
        batch_id: :profile_batch,
        index: i,
        timestamp: DateTime.utc_now()
      }
      {vector, metadata}
    end
    
    # Time the insertion
    {time_us, _} = :timer.tc(fn ->
      Enum.each(vectors, fn {vec, meta} ->
        HNSWIndex.insert(index, vec, meta)
      end)
    end)
    
    # Capture final memory state
    :erlang.garbage_collect()
    Process.sleep(100)
    
    final_memory = %{
      total: :erlang.memory(:total),
      processes: :erlang.memory(:processes),
      ets: :erlang.memory(:ets),
      binary: :erlang.memory(:binary)
    }
    
    final_stats = HNSWIndex.stats(index)
    
    # Calculate memory usage
    memory_delta = %{
      total: final_memory.total - initial_memory.total,
      processes: final_memory.processes - initial_memory.processes,
      ets: final_memory.ets - initial_memory.ets,
      binary: final_memory.binary - initial_memory.binary
    }
    
    vectors_added = final_stats.vector_count - initial_stats.vector_count
    
    # Generate report
    %{
      vectors_inserted: vectors_added,
      time_ms: time_us / 1000,
      throughput_per_sec: vectors_added * 1_000_000 / time_us,
      memory_per_vector_bytes: memory_delta.total / vectors_added,
      memory_breakdown: %{
        ets_per_vector: memory_delta.ets / vectors_added,
        process_per_vector: memory_delta.processes / vectors_added,
        binary_per_vector: memory_delta.binary / vectors_added
      },
      efficiency_metrics: %{
        bytes_per_dimension: memory_delta.total / (vectors_added * dimensions),
        overhead_ratio: memory_delta.total / (vectors_added * dimensions * 4), # 4 bytes per float
        graph_memory_pct: memory_delta.ets / memory_delta.total * 100
      }
    }
  end
  
  @doc """
  Monitor memory growth over time during continuous operation
  """
  def monitor_memory_growth(index, duration_seconds \\ 60) do
    end_time = System.monotonic_time(:second) + duration_seconds
    
    Stream.unfold(0, fn counter ->
      if System.monotonic_time(:second) < end_time do
        # Insert some vectors
        batch_size = 10
        for _ <- 1..batch_size do
          vector = :rand.uniform() |> List.duplicate(128)
          HNSWIndex.insert(index, vector, %{monitor_batch: counter})
        end
        
        # Collect memory stats
        stats = %{
          timestamp: DateTime.utc_now(),
          vector_count: HNSWIndex.stats(index).vector_count,
          memory_total: :erlang.memory(:total),
          memory_ets: :erlang.memory(:ets),
          memory_processes: :erlang.memory(:processes)
        }
        
        Process.sleep(1000)  # 1 second interval
        {stats, counter + 1}
      else
        nil
      end
    end)
    |> Enum.to_list()
    |> analyze_growth_pattern()
  end
  
  defp analyze_growth_pattern(samples) do
    # Calculate growth rate and detect memory leaks
    first = List.first(samples)
    last = List.last(samples)
    
    vectors_added = last.vector_count - first.vector_count
    memory_added = last.memory_total - first.memory_total
    time_elapsed = DateTime.diff(last.timestamp, first.timestamp)
    
    %{
      duration_seconds: time_elapsed,
      vectors_added: vectors_added,
      memory_growth_mb: memory_added / 1_048_576,
      avg_memory_per_vector: memory_added / vectors_added,
      growth_rate_mb_per_hour: memory_added / 1_048_576 * 3600 / time_elapsed,
      samples: length(samples),
      memory_trend: calculate_trend(samples)
    }
  end
  
  defp calculate_trend(samples) do
    # Simple linear regression on memory usage
    x_values = 0..(length(samples) - 1) |> Enum.to_list()
    y_values = Enum.map(samples, & &1.memory_total)
    
    n = length(samples)
    sum_x = Enum.sum(x_values)
    sum_y = Enum.sum(y_values)
    sum_xy = Enum.zip(x_values, y_values) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
    sum_x2 = Enum.map(x_values, & &1 * &1) |> Enum.sum()
    
    slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
    intercept = (sum_y - slope * sum_x) / n
    
    %{
      slope_bytes_per_second: slope,
      baseline_bytes: intercept,
      projected_1h_growth_mb: slope * 3600 / 1_048_576
    }
  end
end

# Usage example:
{:ok, index} = HNSWIndex.start_link(m: 16, ef: 200)

# Profile single batch
profile = HNSWMemoryProfiler.profile_memory_usage(index, 1000, 128)
IO.inspect(profile, label: "Memory Profile")

# Monitor continuous growth
growth = HNSWMemoryProfiler.monitor_memory_growth(index, 60)
IO.inspect(growth, label: "Growth Analysis")

# Typical output:
# Memory Profile: %{
#   memory_per_vector_bytes: 3842,
#   memory_breakdown: %{
#     ets_per_vector: 2956,      # ~77% for graph structure
#     process_per_vector: 486,    # ~13% for process state
#     binary_per_vector: 400      # ~10% for metadata
#   },
#   efficiency_metrics: %{
#     bytes_per_dimension: 30,    # 3842 / 128
#     overhead_ratio: 7.5,        # vs raw 4 bytes/float
#     graph_memory_pct: 77.0
#   }
# }
```

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

### Enhanced Error Recovery Examples

```elixir
defmodule S4.Intelligence.ErrorRecovery do
  @doc """
  Comprehensive error handling for HNSW operations with fallback strategies
  """
  def handle_search_failure(query, error, options \\ []) do
    case error do
      :timeout ->
        # Search timeout - reduce ef parameter for faster results
        Logger.warn("HNSW search timeout, reducing ef parameter")
        reduced_ef = Keyword.get(options, :ef, 200) |> div(4)
        
        HNSWIndex.search(:s4_pattern_index, query, 
          k: 10, 
          ef: max(reduced_ef, 10),
          timeout: 5_000
        )
      
      :corrupted_index ->
        # Index corruption - attempt recovery then fallback
        Logger.error("HNSW index corruption detected")
        
        case attempt_index_recovery() do
          {:ok, recovered_index} ->
            HNSWIndex.search(recovered_index, query, k: 10)
          
          {:error, :recovery_failed} ->
            # Fall back to brute force search
            Logger.warn("Recovery failed, using exact search")
            S4.ExactSearch.find_nearest(query, k: 10)
        end
      
      :empty_index ->
        # No patterns indexed yet - bootstrap with synthetic data
        Logger.info("Empty index, bootstrapping with synthetic patterns")
        
        # Generate representative patterns for cold start
        synthetic_patterns = S4.PatternGenerator.create_bootstrap_patterns(
          count: 100,
          dimensions: length(query),
          distribution: :environmental_baseline
        )
        
        # Index synthetic patterns
        Enum.each(synthetic_patterns, fn pattern ->
          HNSWIndex.insert(:s4_pattern_index, pattern.vector, pattern.metadata)
        end)
        
        # Return empty result for now
        {:ok, []}
      
      {:dimension_mismatch, expected, actual} ->
        # Dimension mismatch - attempt to fix query vector
        Logger.warn("Dimension mismatch: expected #{expected}, got #{actual}")
        
        fixed_query = case {expected, actual} do
          {exp, act} when act < exp ->
            # Pad with zeros
            query ++ List.duplicate(0.0, exp - act)
          
          {exp, act} when act > exp ->
            # Truncate
            Enum.take(query, exp)
        end
        
        HNSWIndex.search(:s4_pattern_index, fixed_query, k: 10)
      
      :memory_exhausted ->
        # Out of memory - trigger emergency cleanup
        Logger.error("Memory exhausted during HNSW operation")
        
        # Free memory by pruning old patterns
        {:ok, pruned_count} = HNSWIndex.prune_old_patterns(
          :s4_pattern_index,
          max_age_ms: :timer.hours(24)
        )
        
        Logger.info("Pruned #{pruned_count} old patterns")
        
        # Trigger garbage collection
        :erlang.garbage_collect()
        
        # Retry with reduced batch size
        HNSWIndex.search(:s4_pattern_index, query, k: 5, ef: 50)
    end
  end
  
  @doc """
  Attempt to recover a corrupted index
  """
  defp attempt_index_recovery do
    backup_paths = [
      "/var/lib/autonomous_opponent/s4_patterns.hnsw.backup",
      "/var/lib/autonomous_opponent/s4_patterns.hnsw.1",
      "/backup/hnsw/latest/s4_patterns.hnsw"
    ]
    
    Enum.find_value(backup_paths, {:error, :recovery_failed}, fn path ->
      if File.exists?(path) do
        case HNSWIndex.load(path) do
          {:ok, index} -> 
            Logger.info("Successfully recovered index from #{path}")
            {:ok, index}
          _ -> nil
        end
      end
    end)
  end
end

@doc """
Error handling for batch operations with partial success tracking
"""
def handle_batch_insert_errors(vectors_with_metadata, index) do
  results = vectors_with_metadata
  |> Enum.map(fn {vector, metadata} ->
    try do
      case HNSWIndex.insert(index, vector, metadata) do
        {:ok, id} -> {:ok, id}
        {:error, reason} -> {:error, {vector, reason}}
      end
    rescue
      error -> {:error, {vector, error}}
    end
  end)
  
  {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))
  
  # Log failure patterns for analysis
  if length(failures) > 0 do
    failure_reasons = failures
    |> Enum.map(fn {:error, {_vector, reason}} -> reason end)
    |> Enum.frequencies()
    
    Logger.warn("Batch insert had #{length(failures)} failures: #{inspect(failure_reasons)}")
  end
  
  %{
    succeeded: length(successes),
    failed: length(failures),
    success_ids: Enum.map(successes, fn {:ok, id} -> id end),
    failure_details: failures,
    success_rate: length(successes) / length(vectors_with_metadata)
  }
end
```

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
