# AMQP Patterns for VSM Usage

This document describes the AMQP messaging patterns implemented for the Viable System Model (VSM) in the Autonomous Opponent system.

## Overview

The AMQP infrastructure provides reliable, distributed message transport for VSM subsystem communication. It implements resilience patterns including connection pooling, automatic retry, circuit breakers, and dead letter queues.

## Architecture

### Connection Management

The system uses a connection pool with the following characteristics:

- **Pool Size**: 5 connections by default (configurable)
- **Heartbeat**: 30-second intervals to detect connection failures
- **Retry Logic**: Exponential backoff starting at 1 second, max 30 seconds
- **Health Monitoring**: Continuous health checks every 30 seconds
- **Circuit Breaker**: Prevents cascade failures during outages

### Message Flow

```
EventBus <-> AMQP Router <-> Message Handler <-> RabbitMQ
                                    |
                                    v
                              VSM Topology
```

## VSM Communication Patterns

### 1. Event Broadcasting

VSM subsystems publish events using topic exchanges:

```elixir
# Publishing a subsystem event
MessageHandler.publish_vsm_event(:s3, :state_change, %{
  old_state: :planning,
  new_state: :executing,
  timestamp: DateTime.utc_now()
})
```

**Routing Pattern**: `{subsystem}.{event_type}`
- Example: `s3.state_change`

### 2. Algedonic Signaling

Pain/pleasure signals are broadcast to all subsystems with priority:

```elixir
# Publishing an algedonic signal
MessageHandler.publish_algedonic(:critical, %{
  source: :s1,
  metric: :response_time,
  value: 5000,
  threshold: 1000,
  message: "Response time critically high"
})
```

**Priorities**:
- `:critical` - Priority 10
- `:high` - Priority 8
- `:medium` - Priority 5
- `:low` - Priority 2

### 3. Coordination Messages

S3 and above listen to coordination events:

```elixir
# Coordination between meta-system components
MessageHandler.publish("vsm.events", "coordination.resource_allocation", %{
  request_from: :s3,
  resource_type: :compute,
  quantity: 10,
  priority: :high
})
```

### 4. Command Routing

Directed commands to specific subsystems:

```elixir
# Send command to specific subsystem
MessageHandler.publish("vsm.commands", "s4.adjust_policy", %{
  policy: :resource_limits,
  adjustment: %{cpu_limit: 80, memory_limit: 90}
})
```

## Queue Configuration

### Per-Subsystem Queues

Each VSM subsystem has dedicated queues with:

- **Message TTL**: 1 hour
- **Max Length**: 10,000 messages
- **Dead Letter Queue**: Automatic routing on failure
- **Durability**: Survives broker restarts

### Queue Naming Convention

- Events: `vsm.{subsystem}.events`
- Commands: `vsm.{subsystem}.commands`
- Algedonic: `vsm.algedonic.signals`
- DLQ: `vsm.{subsystem}.events.dlq`

## Error Handling Patterns

### 1. Connection Failures

```elixir
# Automatic retry with exponential backoff
# 1s -> 2s -> 4s -> 8s -> 16s -> 30s (max)

# Circuit breaker prevents thundering herd
# Opens after 5 consecutive failures
# Half-opens after 60 seconds
```

### 2. Message Publishing Failures

```elixir
# Retry up to 3 times with backoff
# On final failure, route to EventBus
# Publish failure event for monitoring
```

### 3. Consumer Errors

```elixir
# Handler exceptions -> reject without requeue -> DLQ
# Temporary failures -> reject with requeue
# Success -> acknowledge
```

## Integration with EventBus

The system provides seamless fallback to EventBus when AMQP is unavailable:

```elixir
# When AMQP is disabled, messages route through EventBus
# Event naming: :vsm_{subsystem}_{event_type}
# Example: :vsm_s3_state_change

# Algedonic signals always route to both AMQP and EventBus
# Ensures critical signals are never lost
```

## Monitoring and Observability

### Health Metrics

```elixir
# Get connection pool health
ConnectionPool.health_status()
# => %{
#   total_connections: 5,
#   healthy_connections: 4,
#   connection_details: %{...}
# }

# Get message handler stats
MessageHandler.get_stats()
# => %{
#   publish: %{success: 1000, failure: 5},
#   consume: %{success: 950, failure: 2},
#   retry_queue_size: 3
# }
```

### Health Check Integration

The AMQP infrastructure integrates with system-wide health checks:

```elixir
# Responds to :health_check_request events
# Publishes :health_check_response with component status
# Triggers algedonic signals on prolonged unhealthy state
```

## Configuration

### Environment Variables

```elixir
# Enable/disable AMQP
config :autonomous_opponent_core, :amqp_enabled, true

# Connection settings
config :autonomous_opponent_core, :amqp_connection, [
  hostname: "localhost",
  username: "guest",
  password: "guest",
  port: 5672,
  virtual_host: "/",
  heartbeat: 30,
  connection_timeout: 5_000
]

# Pool configuration
config :autonomous_opponent_core, :amqp_pool_size, 5
```

### Runtime Configuration

```elixir
# Adjust pool size
{:ok, _} = AutonomousOpponentV2Core.AMCP.Supervisor.start_link(
  pool_size: 10
)

# Configure consumer prefetch
MessageHandler.consume(queue, handler, prefetch_count: 20)
```

## Best Practices

### 1. Message Design

- Keep messages small and focused
- Include timestamps for tracking
- Use consistent field names across subsystems
- Validate messages with Ecto schemas

### 2. Queue Management

- Monitor queue depths regularly
- Set appropriate TTLs for message types
- Use priority queues for critical paths
- Implement proper DLQ handling

### 3. Error Recovery

- Always handle both success and failure cases
- Log errors with context for debugging
- Use circuit breakers for external dependencies
- Implement compensating transactions when needed

### 4. Performance

- Use connection pooling for high throughput
- Batch messages when appropriate
- Configure prefetch for optimal consumer performance
- Monitor and tune based on metrics

## Troubleshooting

### Common Issues

1. **"No healthy connections"**
   - Check RabbitMQ is running
   - Verify network connectivity
   - Check credentials and vhost permissions

2. **Messages not being consumed**
   - Verify queue bindings
   - Check consumer is started
   - Look for errors in consumer handlers

3. **High message latency**
   - Check connection pool health
   - Verify no circuit breakers are open
   - Monitor RabbitMQ performance

4. **Messages going to DLQ**
   - Check consumer handler errors
   - Verify message format
   - Look for timeout issues

### Debug Commands

```elixir
# Check topology
VSMTopology.get_topology_info()

# Monitor specific queue
MessageHandler.consume("vsm.s3.events", &IO.inspect/2)

# Test connectivity
ConnectionPool.get_channel()

# Force health check
HealthMonitor.get_health()
```

## Future Improvements

1. **Distributed Tracing**: Add trace IDs to messages
2. **Message Versioning**: Support schema evolution
3. **Federated Exchanges**: Multi-datacenter support
4. **Stream Processing**: Integration with RabbitMQ Streams
5. **Metrics Export**: Prometheus/OpenTelemetry integration