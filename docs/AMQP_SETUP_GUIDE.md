# AMQP/RabbitMQ Setup Guide for VSM

This guide explains how to set up and run the Autonomous Opponent with full AMQP messaging support.

## Prerequisites

### 1. Install RabbitMQ

**macOS (Homebrew):**
```bash
brew install rabbitmq
brew services start rabbitmq
```

**Ubuntu/Debian:**
```bash
sudo apt-get install rabbitmq-server
sudo systemctl start rabbitmq-server
sudo systemctl enable rabbitmq-server
```

**Docker:**
```bash
docker-compose -f docker-compose.rabbitmq.yml up -d
```

### 2. Verify RabbitMQ is Running

```bash
# Check service status
rabbitmqctl status

# Access management UI (default: guest/guest)
open http://localhost:15672
```

## Configuration

### 1. Environment Variables

The system checks for AMQP configuration in this order:
1. Application config
2. Environment variables
3. Default values

**Enable AMQP (default is true):**
```bash
export AMQP_ENABLED=true
export AMQP_URL=amqp://localhost:5672
```

**Or in config/dev.exs:**
```elixir
config :autonomous_opponent_core,
  amqp_enabled: true,
  amqp_connection: [
    host: "localhost",
    port: 5672,
    username: "guest",
    password: "guest"
  ]
```

### 2. VSM Topology Setup

The VSM requires specific queues and exchanges. Run the setup script:

```bash
# From project root
mix run scripts/setup_vsm_topology.exs
```

This creates:
- 5 exchanges (vsm.topic, vsm.events, vsm.algedonic, vsm.commands, vsm.dlx)
- 29 queues for VSM subsystems and channels
- Proper bindings and routing keys

## Running the System

### 1. Start with AMQP

```bash
# Ensure RabbitMQ is running
rabbitmqctl status

# Start the application
iex -S mix

# You should see:
# [info] Starting AMQP supervisor with full functionality
# [info] AMQP connection established successfully
```

### 2. Verify AMQP is Working

In IEx:
```elixir
# Check AMQP status
AutonomousOpponentV2Core.AMCP.Supervisor.amqp_available?()
# Should return: true

# Check connection pool health
AutonomousOpponentV2Core.AMCP.ConnectionPool.health_check()
# Should show: %{healthy: true, ...}
```

### 3. Monitor VSM Activity

The system will show VSM activity in logs:
```
[info] VSM IS VIABLE AND OPERATIONAL!
[info] 😊 PLEASURE SIGNAL from s5_policy.thriving: 1.0
[warning] 😣 PAIN SIGNAL from s4_intelligence.blind: 0.86
[error] S3 EMERGENCY INTERVENTION
```

## Troubleshooting

### AMQP in Stub Mode

If you see:
```
[warning] AMQP supervisor starting in stub mode
```

Check:
1. Is RabbitMQ running? `rabbitmqctl status`
2. Is AMQP_ENABLED set? `echo $AMQP_ENABLED`
3. Can you connect? `telnet localhost 5672`

### Connection Failures

If connections fail:
```bash
# Check RabbitMQ logs
tail -f /opt/homebrew/var/log/rabbitmq/rabbit@localhost.log

# Reset RabbitMQ (WARNING: deletes all data)
rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl start_app
```

### Missing Queues

If VSM queues are missing:
```bash
# Re-run topology setup
mix run scripts/setup_vsm_topology.exs

# Or manually in RabbitMQ management UI
# Create exchanges and queues as defined in topology.ex
```

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   External      │     │    RabbitMQ     │     │   VSM System    │
│   Clients       │────▶│   (29 queues)   │────▶│   (S1-S5)       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │                          │
                               ▼                          ▼
                        ┌─────────────────┐     ┌─────────────────┐
                        │  VSMConsumer    │────▶│    EventBus     │
                        └─────────────────┘     └─────────────────┘
```

## Message Flow Examples

### Send Operational Request to S1
```elixir
alias AutonomousOpponentV2Core.AMCP.{ConnectionPool, Topology}

ConnectionPool.with_connection(fn channel ->
  message = %{
    type: "operational_request",
    data: "Process this order"
  }
  Topology.publish_message(channel, message, "vsm.s1.operations")
end)
```

### Send Algedonic Signal
```elixir
# Pain signal (high priority)
ConnectionPool.with_connection(fn channel ->
  Topology.publish_algedonic(channel, :pain, %{
    level: 8,
    source: "production_line",
    message: "Critical failure!"
  })
end)
```

## Production Considerations

### 1. Connection Pool Size
```elixir
# In config/prod.exs
config :autonomous_opponent_core,
  amqp_pool_size: 20,      # Default: 10
  amqp_max_overflow: 10    # Default: 5
```

### 2. Message Persistence
Messages are persisted by default. For high-throughput:
```elixir
# In topology.ex publish_message/4
publish_opts = [
  persistent: false,  # Disable for speed
  mandatory: true     # Ensure delivery
]
```

### 3. Monitoring
- Use RabbitMQ Management UI: http://localhost:15672
- Monitor queue depths and consumer counts
- Set up alerts for dead letter queues

### 4. Clustering
For high availability:
```bash
# Join RabbitMQ cluster
rabbitmqctl join_cluster rabbit@node1

# Enable mirrored queues
rabbitmqctl set_policy ha-all "^vsm\." '{"ha-mode":"all"}'
```

## Testing AMQP Integration

Run the test suite:
```bash
# Unit tests
mix test test/autonomous_opponent_v2_core/amcp/

# Integration test (requires RabbitMQ)
MIX_ENV=test mix test test/autonomous_opponent_v2_core/amcp/real_amqp_test.exs
```

## Disabling AMQP

To run without RabbitMQ (stub mode):
```bash
export AMQP_ENABLED=false
iex -S mix

# System will show:
# [warning] AMQP supervisor starting in stub mode
```

The system will still function using EventBus only, but without distributed messaging capabilities.

## Next Steps

1. **Scale Consumers**: Add more VSMConsumer instances for each subsystem
2. **Add Metrics**: Integrate Prometheus for queue metrics
3. **Implement Sagas**: Use AMQP for distributed transactions
4. **Deploy Distributed**: Run subsystems on separate nodes

Remember: "The purpose of a system is what it does" - and with AMQP, this system can now do it at scale!