# Redis Integration for Distributed Rate Limiting

## Overview

The Autonomous Opponent V2 now includes Redis-based distributed rate limiting, implementing Issue #84. This provides cluster-wide rate limiting with VSM integration for adaptive variety attenuation based on cybernetic principles.

## Features

✅ **Distributed Rate Limiting**: Consistent rate limits across all nodes
✅ **VSM Integration**: Adaptive limits based on subsystem health and algedonic signals  
✅ **Graceful Fallback**: Automatic fallback to local ETS when Redis unavailable
✅ **Circuit Breaker**: Protection against Redis failures
✅ **Comprehensive Telemetry**: Full observability of rate limiting behavior
✅ **Security**: GDPR-compliant audit logging with hashed identifiers

## Quick Start

### 1. Install Redis

```bash
# macOS
brew install redis
brew services start redis

# Ubuntu/Debian
sudo apt update
sudo apt install redis-server
sudo systemctl start redis

# Docker
docker run -d -p 6379:6379 redis:alpine
```

### 2. Configuration

The system is pre-configured for development. For production, set these environment variables:

```bash
export REDIS_ENABLED=true
export REDIS_HOST=localhost
export REDIS_PORT=6379
export REDIS_PASSWORD=your_secure_password  # Optional
```

### 3. Verify Installation

```bash
# Run the test script
mix run test_redis_rate_limiter.exs

# Or in IEx
iex -S mix
iex> AutonomousOpponentV2Core.Connections.RedisPool.health_check()
:ok
```

## Architecture

### Three-Layer Design

1. **Redis Layer**: Primary distributed state with Lua scripts for atomicity
2. **Circuit Breaker**: Monitors Redis health and triggers fallback
3. **Local Fallback**: ETS-based rate limiting when Redis unavailable

### VSM Integration

The rate limiter integrates deeply with the Viable System Model:

- **S1 Operations**: 100 req/sec (highest capacity for variety absorption)
- **S2 Coordination**: 50 req/sec (prevents oscillations)
- **S3 Control**: 20 req/sec (resource management)
- **S4 Intelligence**: 100 req/min (pattern learning)
- **S5 Policy**: 50 req/5min (governance)

### Adaptive Behavior

Rate limits adapt based on:
- **Pain Signals**: Reduce limits when system stressed
- **Pleasure Signals**: Increase limits when capacity available
- **Utilization**: Automatic adjustment based on rejection rates
- **Channel Capacity**: Limits aligned with VSM variety channels

## Usage Examples

### Basic Rate Limiting

```elixir
# Check rate limit
case DistributedRateLimiter.check_and_track(:api_rate_limiter, user_id, :burst) do
  {:ok, usage} ->
    # Request allowed
    IO.puts("Allowed: #{usage.remaining}/#{usage.max} remaining")
    
  {:error, :rate_limited, usage} ->
    # Request denied
    IO.puts("Rate limited: #{usage.current}/#{usage.max}")
end
```

### VSM Subsystem Limits

```elixir
# Check S1 operations limit
case RateLimiterIntegration.check_subsystem_limit(:s1, operation_id) do
  {:ok, usage} ->
    # Operation allowed
    perform_operation()
    
  {:error, :rate_limited, _usage} ->
    # Emit pain signal and queue for later
    emit_variety_overflow()
end
```

### Batch Usage Check

```elixir
# Check multiple identifiers efficiently
{:ok, usages} = DistributedRateLimiter.get_usage_batch(
  :api_rate_limiter,
  ["user1", "user2", "user3"],
  :sustained
)

for {user_id, usage} <- usages do
  IO.puts("#{user_id}: #{usage.current}/#{usage.max}")
end
```

## Monitoring

### Key Metrics

- `rate_limiter.checks.total` - Total rate limit checks
- `rate_limiter.violations.total` - Rate limit violations
- `redis.command.duration` - Redis operation latency
- `circuit_breaker.trips.total` - Circuit breaker activations
- `vsm.rate_limiter.adaptations` - Adaptive limit changes

### Algedonic Integration

The system emits pain/pleasure signals:

```elixir
# Pain signal on rate limiting
EventBus.subscribe(:algedonic_pain)

# Pleasure signal on low utilization  
EventBus.subscribe(:algedonic_pleasure)
```

## Security Considerations

1. **Redis Authentication**: Use ACL with minimal permissions
2. **TLS Encryption**: Enable for production deployments
3. **Audit Logging**: All violations logged with hashed identifiers
4. **Input Sanitization**: Prevents Redis command injection
5. **Credential Management**: Uses SecretsManager for passwords

## Production Deployment

### Redis Sentinel (High Availability)

```elixir
config :autonomous_opponent_core,
  redis_sentinels: [
    [host: "sentinel1", port: 26379],
    [host: "sentinel2", port: 26379],
    [host: "sentinel3", port: 26379]
  ],
  redis_sentinel_group: "mymaster"
```

### Redis Cluster (Horizontal Scaling)

For >10K requests/second, consider Redis Cluster. The implementation supports it through key hashing.

### Performance Tuning

1. **Connection Pool**: Adjust `redis_pool_size` based on load
2. **Lua Script Caching**: Scripts are pre-loaded for performance
3. **Batch Operations**: Use `get_usage_batch` for multiple checks
4. **Local Caching**: Consider adding process-level cache for hot keys

## Troubleshooting

### Redis Connection Failed

```bash
# Check Redis is running
redis-cli ping

# Check connection
mix run -e "AutonomousOpponentV2Core.Connections.RedisPool.health_check() |> IO.inspect()"
```

### High Fallback Usage

Monitor the `rate_limiter.fallback.usage` metric. High values indicate Redis issues.

### Rate Limits Not Adapting

Ensure VSM integration is running:
```elixir
RateLimiterIntegration.get_subsystem_metrics()
```

## Implementation Details

### Lua Scripts

Two Lua scripts provide atomic operations:

1. **Check and Increment**: Atomic rate limit check with sliding window
2. **Batch Usage**: Efficient multi-key usage queries

### Fallback Mechanism

When Redis is unavailable:
1. Circuit breaker opens after 5 failures
2. Switches to ETS-based local limiting
3. Continues attempting Redis reconnection
4. Automatically resumes when Redis recovers

### VSM Cybernetics

The implementation follows Stafford Beer's principles:
- **Variety Attenuation**: Rate limits reduce incoming variety
- **Requisite Variety**: Limits match system processing capacity
- **Recursive Structure**: Each subsystem has independent limits
- **Algedonic Bypass**: Emergency signals bypass normal channels

## Future Enhancements

1. **Distributed Consensus**: Share state via CRDT during Redis outages
2. **ML-Based Prediction**: S4 Intelligence predicts load patterns
3. **Dynamic Windows**: Adjust time windows based on patterns
4. **Multi-Region**: Geo-distributed rate limiting
5. **WebAssembly Scripts**: Custom rate limit algorithms

## References

- [Redis Documentation](https://redis.io/docs/)
- [Stafford Beer's Viable System Model](https://en.wikipedia.org/wiki/Viable_system_model)
- [Redix Elixir Client](https://github.com/whatyouhide/redix)
- [Circuit Breaker Pattern](https://martinfowler.com/bliki/CircuitBreaker.html)