# HNSW Pattern Storage Configuration

This document describes the configuration options for the HNSW (Hierarchical Navigable Small World) pattern storage system in the Autonomous Opponent v2.

## Overview

The HNSW pattern storage system provides high-performance similarity search for matched patterns. It includes advanced features like backpressure handling, pattern deduplication, and comprehensive monitoring.

## Configuration Options

### PatternHNSWBridge Configuration

The PatternHNSWBridge can be configured with the following options when starting:

```elixir
{:ok, _} = PatternHNSWBridge.start_link(
  name: :custom_bridge,
  hnsw_name: :custom_hnsw,
  indexer_name: :custom_indexer,
  dedup_similarity_threshold: 0.95
)
```

### Backpressure Thresholds

Backpressure is applied when the system is under load to prevent memory exhaustion and maintain stability.

| Configuration | Default Value | Description |
|--------------|---------------|-------------|
| `@max_buffer_size` | 100 | Maximum patterns in buffer before applying backpressure |
| `@max_lag_threshold` | 500 | Maximum difference between received and indexed patterns |
| `@backpressure_log_interval` | 10,000 ms | How often to log backpressure status |

When backpressure is active:
- New patterns are dropped rather than buffered
- Metrics track dropped patterns
- Warnings are logged periodically

### Deduplication Settings

Pattern deduplication prevents redundant patterns from being indexed.

| Configuration | Default Value | Description |
|--------------|---------------|-------------|
| `@dedup_similarity_threshold` | 0.95 | Patterns with similarity > 0.95 are considered duplicates |
| `@pattern_cache_size` | 1000 | Number of recent patterns kept for fast dedup checks |
| `@cache_cleanup_interval` | 60,000 ms | How often to clean up old patterns from cache |

### HNSW Index Parameters

The HNSW index is configured for optimal performance:

| Parameter | Value | Description |
|-----------|-------|-------------|
| `m` | 16 | Number of bi-directional links per node |
| `ef` | 200 | Size of dynamic candidate list |
| `distance_metric` | `:cosine` | Similarity metric for pattern vectors |
| `persist` | `true` | Whether to persist index to disk |

### Processing Parameters

| Configuration | Default Value | Description |
|--------------|---------------|-------------|
| `@vector_dim` | 100 | Dimensionality of pattern vectors |
| `@batch_size` | 10 | Patterns processed per batch |
| `@batch_timeout` | 1000 ms | Maximum time before processing partial batch |

## Monitoring

### Basic Statistics

Access basic statistics using:
```elixir
PatternHNSWBridge.get_stats()
```

Returns:
- Pattern counts (received, indexed, deduplicated, dropped)
- Buffer and cache sizes
- Backpressure status
- HNSW index statistics

### Comprehensive Monitoring

Access detailed monitoring information using:
```elixir
PatternHNSWBridge.get_monitoring_info()
```

Returns comprehensive metrics including:
- Pattern processing rates and success rates
- Backpressure utilization metrics
- Deduplication effectiveness
- System health status and warnings
- Performance recommendations

## Performance Tuning

### High-Volume Scenarios

For high-volume pattern streams:
1. Increase `@max_buffer_size` to 500-1000
2. Increase `@max_lag_threshold` to 2000-5000
3. Increase `@batch_size` to 50-100
4. Decrease `@batch_timeout` to 500ms

### Memory-Constrained Environments

For memory-constrained environments:
1. Decrease `@max_buffer_size` to 50
2. Decrease `@pattern_cache_size` to 500
3. Increase `@cache_cleanup_interval` to 30,000ms
4. Enable more aggressive deduplication (threshold 0.90)

### Low-Latency Requirements

For low-latency pattern indexing:
1. Decrease `@batch_size` to 1-5
2. Decrease `@batch_timeout` to 100-200ms
3. Keep buffers small for faster processing

## Best Practices

1. **Monitor Health Status**: Regularly check `get_monitoring_info()` for warnings and recommendations
2. **Tune Deduplication**: Adjust similarity threshold based on your pattern characteristics
3. **Watch Backpressure**: If frequently active, increase resources or adjust thresholds
4. **Index Maintenance**: HNSW index automatically persists, but consider periodic backups
5. **Pattern Features**: Ensure patterns include rich features for better vector representation

## Troubleshooting

### High Deduplication Rate
- Lower the similarity threshold (e.g., 0.90 or 0.85)
- Check if patterns are too similar in nature
- Review pattern feature extraction

### Frequent Backpressure
- Increase buffer and lag thresholds
- Add more processing resources
- Optimize pattern processing pipeline

### Poor Search Performance
- Check HNSW index size and health
- Verify vector dimensionality matches
- Consider reindexing if index is corrupted

### Memory Growth
- Reduce cache size
- Increase cleanup frequency
- Monitor pattern buffer size