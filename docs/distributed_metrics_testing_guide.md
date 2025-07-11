# VSM Distributed Metrics Testing Guide

## Overview

This guide demonstrates how to test the distributed metrics aggregation system implemented for issue #90.

## Quick Start (3-Node Cluster)

### Terminal 1 - Primary Node
```bash
# Start the primary VSM node
iex --name vsm1@127.0.0.1 --cookie autonomous_opponent -S mix phx.server
```

### Terminal 2 - Secondary Node
```bash
# Start secondary node on different port
PORT=4001 iex --name vsm2@127.0.0.1 --cookie autonomous_opponent -S mix phx.server
```

### Terminal 3 - Tertiary Node
```bash
# Start tertiary node
PORT=4002 iex --name vsm3@127.0.0.1 --cookie autonomous_opponent -S mix phx.server
```

## Connecting Nodes

In any node's IEx shell:
```elixir
# Connect nodes
Node.connect(:"vsm2@127.0.0.1")
Node.connect(:"vsm3@127.0.0.1")

# Verify cluster
Node.list()
```

## Testing Metrics Aggregation

### 1. Generate Test Metrics
```elixir
# On each node, generate some metrics
metrics = AutonomousOpponentV2Core.Core.Metrics
metrics.record(metrics, "test.counter", 100)
metrics.record(metrics, "vsm.s1.variety_absorbed", 500)
```

### 2. Test Cluster Aggregation
```elixir
# Get aggregated metrics
{:ok, results} = AutonomousOpponentV2Core.Metrics.Cluster.Aggregator.aggregate_cluster_metrics()

# Inspect results
Enum.each(results, fn m ->
  IO.puts("#{m.name}: sum=#{m.aggregated.sum}, avg=#{m.aggregated.avg}")
end)
```

### 3. Test VSM Health
```elixir
{:ok, health} = AutonomousOpponentV2Core.Metrics.Cluster.Aggregator.vsm_health()
IO.inspect(health, pretty: true)
```

### 4. Test Time-Series Queries
```elixir
query_engine = AutonomousOpponentV2Core.Metrics.Cluster.QueryEngine
{:ok, data} = query_engine.query("test.counter", :sum, 
  from: DateTime.add(DateTime.utc_now(), -3600, :second),
  to: DateTime.utc_now()
)
```

## HTTP Endpoints

### Local Metrics
```bash
curl http://localhost:4000/metrics
```

### Cluster Metrics (Prometheus Format)
```bash
curl http://localhost:4000/metrics?cluster=true
```

### Cluster Metrics (JSON)
```bash
curl http://localhost:4000/api/metrics/cluster
```

### VSM Health
```bash
curl http://localhost:4000/api/metrics/vsm_health
```

### Query Specific Metric
```bash
curl "http://localhost:4000/api/metrics/cluster?metric=vsm.s1.variety_absorbed&aggregation=sum"
```

## Advanced Testing

### Simulate Algedonic Signal
```elixir
# Trigger pain signal
AutonomousOpponentV2Core.EventBus.publish(:algedonic_signal, %{
  type: :pain,
  intensity: 0.9,
  source: :s1_operations
})
```

### Test Variety Limits
```elixir
# Generate high variety to test quotas
for i <- 1..1000 do
  metrics.record(metrics, "high_variety_#{i}", :rand.uniform())
end
```

### Monitor Circuit Breakers
```elixir
# Check circuit breaker status
:ets.tab2list(:circuit_breakers)
```

## Troubleshooting

### Nodes Not Connecting
- Ensure all nodes use same cookie
- Check firewall allows EPMD (4369) and Erlang ports (9100-9199)
- Verify nodes can resolve each other's hostnames

### Metrics Not Aggregating
- Check aggregator is running: `Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Aggregator)`
- Verify EventBus connections
- Check logs for errors

### Performance Issues
- Monitor variety quotas
- Check time-series rotation is working
- Verify CRDT synchronization

## Automated Test Script

Run the comprehensive test script:
```bash
elixir test_cluster_metrics.exs
```

This will:
1. Connect nodes
2. Generate test metrics
3. Test all aggregation features
4. Report results