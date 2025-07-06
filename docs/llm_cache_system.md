# LLM Response Caching System

## Overview

The LLM Response Caching System is a production-ready caching solution that dramatically reduces API calls to Large Language Model providers (OpenAI, Anthropic, Google AI, etc.) by caching responses based on prompt content and parameters.

## Features

### Core Functionality
- **In-Memory Caching**: Uses ETS for high-performance, concurrent access
- **TTL Support**: Configurable time-to-live for cached entries
- **Disk Persistence**: Automatic saving and loading of cache to/from disk
- **Cache Warming**: Pre-load cache on startup from persisted data
- **Smart Key Generation**: Cache keys include model, temperature, and other parameters
- **Automatic Eviction**: LRU (Least Recently Used) eviction when cache is full
- **Statistics & Telemetry**: Track cache hits, misses, and performance metrics

### Production Features
- **Thread-Safe**: Concurrent access with read optimizations
- **Configurable Limits**: Set maximum cache size and TTL per environment
- **Periodic Persistence**: Automatically save cache to disk at intervals
- **Expired Entry Pruning**: Regular cleanup of expired entries
- **Telemetry Integration**: Emits events for monitoring and alerting

## Architecture

### Components

1. **LLMCache GenServer** (`llm_cache.ex`)
   - Manages ETS tables for cache storage
   - Handles persistence and cache warming
   - Provides statistics and monitoring

2. **LLMBridge Integration** (`llm_bridge.ex`)
   - Transparently checks cache before API calls
   - Stores successful responses
   - Configurable cache bypass

### Data Flow

```
User Request → LLMBridge → Check Cache
                              ↓
                         Cache Hit? 
                         Yes ↓   ↓ No
                    Return Cached   Call LLM API
                         Response      ↓
                              ↑     Store in Cache
                              └────────┘
```

## Configuration

### Development (`config/dev.exs`)
```elixir
config :autonomous_opponent_core,
  llm_cache_enabled: true,
  llm_cache_config: [
    max_size: 1000,           # Maximum cached entries
    ttl: 3_600_000,          # 1 hour TTL
    warm_on_start: true,      # Load cache from disk
    persist_interval: 300_000 # Save every 5 minutes
  ]
```

### Production (`config/prod.exs`)
```elixir
config :autonomous_opponent_core,
  llm_cache_enabled: true,
  llm_cache_config: [
    max_size: 5000,           # Larger cache for production
    ttl: 7_200_000,          # 2 hour TTL
    warm_on_start: true,
    persist_interval: 600_000 # Save every 10 minutes
  ]
```

### Test (`config/test.exs`)
```elixir
config :autonomous_opponent_core,
  llm_cache_enabled: false,   # Disable in tests
  llm_cache_config: [
    warm_on_start: false,
    persist_interval: :infinity
  ]
```

## API Usage

### Basic Usage
```elixir
# Cache is used automatically by LLMBridge
{:ok, response} = LLMBridge.call_llm_api(
  "What is consciousness?",
  :analysis,
  provider: :openai
)
```

### Cache Control
```elixir
# Get cache statistics
{:ok, stats} = LLMBridge.get_cache_stats()
# Returns: %{hits: 42, misses: 8, size: 50, hit_rate: 84.0, ...}

# Clear cache
{:ok, count} = LLMBridge.clear_cache()

# Enable/disable cache at runtime
LLMBridge.set_cache_enabled(false)

# Warm cache from disk
{:ok, loaded} = LLMBridge.warm_cache()

# Bypass cache for specific request
{:ok, response} = LLMBridge.call_llm_api(
  prompt,
  :analysis,
  use_cache: false
)
```

### Direct Cache Access
```elixir
# Get cached response
case LLMCache.get(prompt, opts) do
  {:hit, response, metadata} -> # Use cached response
  {:miss, reason} -> # Make API call
end

# Store response
LLMCache.put(prompt, response, 
  model: "gpt-4",
  temperature: 0.7,
  ttl: :timer.hours(2)
)

# Get statistics
stats = LLMCache.stats()

# Manual persistence
{:ok, count} = LLMCache.persist()
```

## Cache Key Generation

Cache keys are generated from:
- Prompt content
- Model name
- Temperature setting
- Max tokens
- Provider (when relevant)

This ensures different configurations get different cache entries.

## Performance Impact

### Typical Results
- Cache hits: <1ms response time
- Cache misses: Normal API latency (1-10s)
- Hit rate: 60-90% in production (depends on usage patterns)
- Memory usage: ~1KB per cached entry

### Example Metrics
```
First API call:  2,847ms (cache miss)
Second API call:    3ms (cache hit)
Speed improvement: 949x faster
```

## Monitoring

### Telemetry Events
The cache emits telemetry events for monitoring:
- `[:autonomous_opponent, :llm_cache, :hit]`
- `[:autonomous_opponent, :llm_cache, :miss]`
- `[:autonomous_opponent, :llm_cache, :put]`
- `[:autonomous_opponent, :llm_cache, :evict]`
- `[:autonomous_opponent, :llm_cache, :clear]`
- `[:autonomous_opponent, :llm_cache, :prune]`

### Cache Statistics
Access detailed statistics via:
```elixir
{:ok, stats} = LLMBridge.get_cache_stats()
# %{
#   hits: 1337,
#   misses: 42,
#   evictions: 5,
#   errors: 0,
#   size: 995,
#   hit_rate: 96.95,
#   memory_used: 1024000,
#   cache_enabled: true
# }
```

## Persistence

### Automatic Persistence
- Cache is saved to disk at configured intervals
- Default location: `priv/llm_cache/cache_dump.etf`
- Binary format using Erlang Term Format

### Manual Operations
```elixir
# Save cache to disk
{:ok, saved_count} = LLMCache.persist()

# Load cache from disk
{:ok, loaded_count} = LLMCache.warm_cache()
```

## Testing

Run the test script to verify functionality:
```bash
mix run test_llm_cache.exs
```

This will test:
1. Cache statistics
2. Hit/miss behavior
3. Persistence and warming
4. Cache key differentiation
5. Performance improvements

## Best Practices

1. **Set Appropriate TTL**: Balance freshness vs. cost
   - Short TTL (1hr) for dynamic content
   - Long TTL (24hr) for stable content

2. **Monitor Hit Rate**: Aim for >80% in production
   - Low hit rate may indicate too much prompt variation
   - Consider prompt normalization

3. **Size Limits**: Set based on memory constraints
   - 1000 entries ≈ 1MB memory
   - Monitor eviction rate

4. **Persistence Strategy**:
   - More frequent saves = better recovery
   - Less frequent saves = better performance
   - 5-10 minute intervals are typical

5. **Cache Warming**: Enable in production for better cold starts

## Troubleshooting

### Low Hit Rate
- Check if prompts have high variability
- Consider normalizing prompts before caching
- Increase cache size if evictions are high

### Memory Issues
- Reduce max_size
- Decrease TTL
- Monitor cache growth patterns

### Persistence Failures
- Check disk space
- Verify write permissions on cache directory
- Check logs for specific errors

## Future Enhancements

Potential improvements:
- Distributed caching with Redis/Memcached
- Semantic similarity matching for near-miss cache hits
- Compression for large responses
- Cache preloading from common prompts
- Multi-level caching (memory + disk + distributed)