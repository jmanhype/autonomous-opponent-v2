# AMQP Patterns for VSM

This document describes the AMQP messaging patterns implemented for the Viable System Model (VSM) in the Autonomous Opponent system.

## Architecture Overview

The AMQP infrastructure provides reliable, scalable messaging between VSM subsystems with the following key features:

- **Connection Pooling**: 10 connections by default with overflow handling
- **Automatic Retry**: Exponential backoff for failed operations
- **Health Monitoring**: Continuous health checks with algedonic pain signals
- **Graceful Degradation**: Falls back to EventBus when AMQP unavailable
- **VSM-Specific Routing**: Optimized topology for S1-S5 communication

## Connection Management

### Configuration

```elixir
# config/config.exs
config :autonomous_opponent_core,
  amqp_enabled: true,
  amqp_connection: [
    host: "localhost",
    port: 5672,
    username: "guest",
    password: "guest",
    virtual_host: "/",
    heartbeat: 30,
    connection_timeout: 10_000
  ],
  amqp_pool_size: 10,
  amqp_max_overflow: 5
```

### Environment Variables

- `AMQP_ENABLED`: Set to "false" to disable AMQP
- `AMQP_URL`: Full connection URL (overrides other settings)
- `AMQP_HOST`: RabbitMQ host
- `AMQP_PORT`: RabbitMQ port
- `AMQP_USERNAME`: Authentication username
- `AMQP_PASSWORD`: Authentication password
- `AMQP_VHOST`: Virtual host

## VSM Communication Patterns

### 1. Subsystem Publishing

Each VSM subsystem (S1-S5) has dedicated queues with specific characteristics:

```elixir
# S1: Operations - High throughput
Client.publish_to_subsystem(:s1, %{
  operation: "process_order",
  order_id: "12345"
})

# S3: Control - Priority handling
Client.publish_to_subsystem(:s3, %{
  action: "emergency_stop",
  reason: "threshold_exceeded"
}, priority: 10)

# S4: Intelligence - Analysis tasks
Client.publish_to_subsystem(:s4, %{
  task: "analyze_patterns",
  dataset: "recent_operations"
})
```

### 2. Algedonic Signaling

Pain and pleasure signals bypass normal hierarchy:

```elixir
# Pain signal - highest priority
Client.send_algedonic(:pain, %{
  source: "resource_monitor",
  severity: "critical",
  metric: "memory_usage",
  value: 95.5
})

# Pleasure signal - positive feedback
Client.send_algedonic(:pleasure, %{
  source: "goal_tracker",
  achievement: "sales_target_exceeded",
  value: 120
})
```

### 3. Event Broadcasting

Events are published to all interested subsystems:

```elixir
Client.publish_event(:system_state_changed, %{
  previous_state: "normal",
  new_state: "degraded",
  reason: "high_load"
})
```

### 4. Work Queues

Distribute tasks among workers:

```elixir
# Create work queue
Client.create_work_queue("data_processing", 
  ttl: 3_600_000,  # 1 hour
  max_length: 1000
)

# Send work
Client.send_work("data_processing", %{
  file_path: "/data/input.csv",
  operations: ["validate", "transform", "aggregate"]
})

# Consume work
Client.consume_work("data_processing", fn work_item ->
  process_data(work_item)
  :ok  # Acknowledges message
end)
```

## Exchange and Queue Topology

### Exchanges

1. **vsm.topic** (Topic Exchange)
   - Main routing exchange for VSM communication
   - Uses routing keys like "vsm.s1.operation"

2. **vsm.events** (Fanout Exchange)
   - Broadcasts events to all subsystems
   - No routing key needed

3. **vsm.algedonic** (Direct Exchange)
   - Routes pain/pleasure signals
   - Routing keys: "pain", "pleasure"

4. **vsm.dlx** (Dead Letter Exchange)
   - Handles failed messages
   - Prevents message loss

### Queue Configuration

#### S1: Operations
- **Queue**: vsm.s1.operations
- **Features**: High throughput, 5-minute TTL, 10k message limit
- **Routing**: operations.*, vsm.s1.*

#### S2: Coordination
- **Queue**: vsm.s2.coordination
- **Features**: Single active consumer for ordering
- **Routing**: coordination.*, vsm.s2.*

#### S3: Control
- **Queue**: vsm.s3.control.priority
- **Features**: Priority queue (0-10), immediate processing
- **Routing**: control.*, vsm.s3.*, vsm.s3star.*

#### S4: Intelligence
- **Queue**: vsm.s4.intelligence
- **Features**: 1-hour TTL for long analysis
- **Routing**: intelligence.*, vsm.s4.*, analysis.*

#### S5: Policy
- **Queue**: vsm.s5.policy
- **Features**: Lazy queue mode for durability
- **Routing**: policy.*, vsm.s5.*, governance.*

## Error Handling and Recovery

### Retry Logic

Failed operations automatically retry with exponential backoff:

1. Initial retry: 1 second
2. Second retry: 2 seconds
3. Third retry: 4 seconds
4. Fourth retry: 8 seconds
5. Fifth retry: 16 seconds
6. Maximum backoff: 60 seconds

### Connection Recovery

Workers monitor their connections and automatically reconnect:

```elixir
# Handled automatically by ConnectionWorker
# - Monitors connection process
# - Reconnects on failure
# - Preserves channel configuration
```

### Dead Letter Queues

Failed messages are routed to DLQs for investigation:

- vsm.dlq.s1.operations
- vsm.dlq.s2.coordination
- vsm.dlq.s3.control
- vsm.dlq.s4.intelligence
- vsm.dlq.s5.policy

## Health Monitoring

### Automated Health Checks

Every 30 seconds, the system:
1. Checks connection pool status
2. Tests message publishing
3. Monitors queue depths (when management API available)
4. Calculates health score

### Health Status API

```elixir
# Get detailed health status
HealthMonitor.get_status()
# => %{
#   status: :healthy,
#   last_check: %{...},
#   consecutive_failures: 0,
#   history: [...]
# }

# Simple health indicator
HealthMonitor.health_indicator()
# => :ok | :degraded | :unhealthy
```

### Integration with Health Endpoints

```elixir
# In your health controller
def health(conn, _params) do
  amqp_health = HealthMonitor.health_indicator()
  
  status = case amqp_health do
    :ok -> :pass
    :degraded -> :warn
    _ -> :fail
  end
  
  json(conn, %{
    status: status,
    checks: %{
      amqp: amqp_health
    }
  })
end
```

## Best Practices

### 1. Use the Client API

Always use the high-level Client API instead of direct AMQP calls:

```elixir
# Good
Client.publish_to_subsystem(:s1, message)

# Avoid
ConnectionPool.with_connection(fn channel ->
  Topology.publish_message(channel, message, "vsm.s1.default")
end)
```

### 2. Handle Errors Gracefully

Always handle potential failures:

```elixir
case Client.publish_to_subsystem(:s1, message) do
  :ok -> 
    Logger.info("Message published successfully")
  {:error, reason} ->
    Logger.error("Failed to publish: #{inspect(reason)}")
    # Fall back to EventBus or other mechanism
    EventBus.publish(:s1_message, message)
end
```

### 3. Set Appropriate Priorities

Use priorities for time-sensitive operations:

```elixir
# Emergency stop - highest priority
Client.publish_to_subsystem(:s3, stop_command, priority: 10)

# Regular operation - default priority
Client.publish_to_subsystem(:s1, regular_task)
```

### 4. Monitor Queue Depths

In production, monitor queue depths to prevent overload:

```elixir
# Set up alerts when queues exceed thresholds
# - S1: Alert at 5000 messages
# - S2: Alert at 1000 messages
# - S3: Alert at 100 messages (priority queue)
```

### 5. Use Work Queues for Heavy Processing

Offload heavy processing to work queues:

```elixir
# Instead of processing in-line
Client.publish_to_subsystem(:s4, %{
  task: "analyze",
  data: large_dataset  # Don't do this
})

# Use work queue reference
Client.send_work("analysis_queue", %{
  task: "analyze",
  data_location: "s3://bucket/dataset.parquet"
})
```

## Testing

### Unit Tests

Test with AMQP in stub mode:

```elixir
# In test config
config :autonomous_opponent_core,
  amqp_enabled: false
```

### Integration Tests

Tag tests that require RabbitMQ:

```elixir
@tag :integration
@tag :skip  # Skip in CI if RabbitMQ unavailable
test "full message flow" do
  # Test with real RabbitMQ
end
```

### Load Testing

Use the connection pool for concurrent operations:

```elixir
tasks = for i <- 1..1000 do
  Task.async(fn ->
    Client.publish_to_subsystem(:s1, %{id: i})
  end)
end

results = Task.await_many(tasks)
```

## Troubleshooting

### Connection Issues

1. Check AMQP is enabled: `Application.get_env(:autonomous_opponent_core, :amqp_enabled)`
2. Verify RabbitMQ is running: `rabbitmqctl status`
3. Check connection settings match RabbitMQ config
4. Look for connection errors in logs

### Message Not Delivered

1. Check health status: `HealthMonitor.get_status()`
2. Verify exchange and queue bindings
3. Check for messages in DLQ
4. Enable debug logging for AMQP modules

### Performance Issues

1. Monitor connection pool usage
2. Check for connection churn (frequent reconnects)
3. Verify heartbeat settings
4. Consider increasing pool size for high load

## Future Enhancements

1. **Request/Reply Pattern**: Full implementation with correlation IDs
2. **RabbitMQ Management API**: Queue depth monitoring
3. **Distributed Tracing**: OpenTelemetry integration
4. **Circuit Breaker**: Per-subsystem circuit breakers
5. **Message Compression**: For large payloads
6. **Schema Registry**: Message validation