# S4 Vector Store - HNSW Index

The Hierarchical Navigable Small World (HNSW) index provides efficient vector similarity search for the S4 Intelligence subsystem's pattern recognition capabilities.

## Architecture

```
vector_store/
├── hnsw_index.ex      # Core HNSW algorithm implementation
├── pattern_indexer.ex # Pattern-to-vector conversion service
└── persistence.ex     # Disk persistence layer
```

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

Based on benchmarks with 1000 vectors:

| Dimensions | Insert Time | Search Time (k=10) | Memory/Vector |
|------------|-------------|-------------------|---------------|
| 50         | ~2ms        | ~5ms              | ~2KB          |
| 128        | ~3ms        | ~8ms              | ~3KB          |
| 256        | ~5ms        | ~12ms             | ~4KB          |

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

## Maintenance

### Memory Management
The index grows with each insertion. For long-running systems:

```elixir
# Periodically check memory usage
stats = HNSWIndex.stats(index)
if stats.memory_usage.total > threshold do
  # Rebuild index with only recent/high-confidence patterns
end
```

### Persistence Strategy
Save index periodically or on significant events:

```elixir
# After environmental shift detected
EventBus.subscribe(:environmental_shift)

receive do
  {:event, :environmental_shift, _} ->
    HNSWIndex.persist(index)
end
```