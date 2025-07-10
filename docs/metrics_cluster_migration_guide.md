# Distributed Metrics Aggregation Migration Guide

This guide covers the migration from single-node metrics to cluster-wide metrics aggregation for issue #90.

## Overview

The new distributed metrics system provides:
- Automatic aggregation across all cluster nodes
- Per-node breakdowns for debugging
- Graceful handling of node failures
- VSM-compliant variety management
- Multi-tier time-series storage

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Node A    │     │   Node B    │     │   Node C    │
│  Metrics    │     │  Metrics    │     │  Metrics    │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┴───────────────────┘
                           │
                    ┌──────▼──────┐
                    │ Aggregator  │
                    │   (CRDT)    │
                    └──────┬──────┘
                           │
                  ┌────────▼────────┐
                  │  Query Engine   │
                  │  (SQL-like)     │
                  └────────┬────────┘
                           │
                    ┌──────▼──────┐
                    │  Time-Series │
                    │    Store     │
                    └─────────────┘
```

## Configuration

### 1. Enable Cluster Metrics

In your `config/config.exs`:

```elixir
config :autonomous_opponent_core,
  metrics_cluster_enabled: true,
  metrics_cluster: [
    aggregation_interval: 10_000,  # 10 seconds
    retention_policy: [
      hot: :timer.minutes(5),
      warm: :timer.hours(24),
      cold: :timer.days(30)
    ]
  ]
```

### 2. Ensure Distributed Erlang

The system requires distributed Erlang. Start your nodes with:

```bash
# Node 1
iex --name node1@127.0.0.1 --cookie secret -S mix phx.server

# Node 2
iex --name node2@127.0.0.1 --cookie secret -S mix phx.server
```

### 3. Connect Nodes

```elixir
# On node1
Node.connect(:"node2@127.0.0.1")
```

## API Changes

### Existing Endpoints (Unchanged)

- `GET /metrics` - Returns local node metrics (Prometheus format)
- `GET /metrics?cluster=true` - Returns cluster-aggregated metrics (Prometheus format)

### New Endpoints

- `GET /metrics/cluster` - JSON API for cluster metrics
- `GET /metrics/cluster?metric=vsm.variety_absorbed&aggregation=sum` - Query specific metric
- `GET /metrics/vsm_health` - VSM health across cluster

### Query Parameters

For `/metrics/cluster`:
- `metric` - Specific metric name
- `aggregation` - sum, avg, min, max, p50, p95, p99
- `from/to` - ISO8601 timestamps for time range
- `nodes` - Comma-separated node names

## Code Migration

### 1. Recording Metrics (No Changes)

Continue using the existing API:

```elixir
# This works on both single-node and cluster
Metrics.counter(Metrics, "api.requests", 1, %{endpoint: "/users"})
Metrics.gauge(Metrics, "memory.usage", 1024)
Metrics.vsm_metric(Metrics, :s1, "operations", 100)
```

### 2. Querying Metrics (New)

For cluster-wide queries:

```elixir
# Query across cluster
{:ok, result} = Metrics.query_cluster("vsm.variety_absorbed", 
  aggregation: :sum,
  from: ~U[2024-01-01 00:00:00Z],
  nodes: :all
)

# Get VSM health
{:ok, health} = Aggregator.vsm_health()
```

### 3. Programmatic Access

```elixir
# Subscribe to aggregated metrics
Phoenix.PubSub.subscribe(
  AutonomousOpponentV2Core.PubSub,
  "metrics:aggregated"
)

# Receive updates
receive do
  {:metrics_aggregated, data} ->
    IO.inspect(data.metrics)
end
```

## Monitoring Setup

### Prometheus Configuration

Update your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'autonomous_opponent_cluster'
    scrape_interval: 30s
    static_configs:
      - targets: ['localhost:4000']
    params:
      cluster: ['true']  # Request cluster metrics
```

### Grafana Dashboards

Example queries for cluster metrics:

```promql
# Total variety absorbed across cluster
sum(vsm_variety_absorbed_cluster_sum)

# Average latency across all nodes
avg(request_latency_cluster_avg)

# Per-node breakdown
vsm_variety_absorbed_by_node
```

## Troubleshooting

### Metrics Not Aggregating

1. Check if cluster supervisor is running:
```elixir
Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Supervisor)
```

2. Verify node connectivity:
```elixir
Node.list()
```

3. Check aggregator health:
```elixir
Aggregator.get_stats()
```

### Performance Issues

1. Adjust aggregation interval:
```elixir
Application.put_env(:autonomous_opponent_core, 
  :metrics_aggregation_interval, 30_000)
```

2. Enable sampling for high-cardinality metrics:
```elixir
Aggregator.configure_sampling("high_freq_metric", sample_rate: 0.1)
```

### Node Failures

The system handles node failures gracefully:
- Failed nodes are excluded from aggregation
- CRDT storage ensures eventual consistency
- Circuit breakers prevent cascade failures

## VSM Compliance

The metrics system follows VSM principles:

1. **Variety Management**: Metrics flow is constrained by variety quotas
2. **Time Constants**: Different aggregation rates for S1-S5
3. **Algedonic Bypass**: Critical metrics bypass normal channels
4. **Autonomy**: Each node maintains local metrics independently

## Performance Considerations

- Hot tier (ETS): Sub-microsecond access, 5-minute retention
- Warm tier (DETS): Fast disk access, 24-hour retention  
- Cold tier (Mnesia): Distributed storage, 30-day retention
- Automatic tier rotation every minute

## Best Practices

1. **Use Tags Wisely**: High-cardinality tags increase storage
2. **Choose Appropriate Aggregations**: Use sum for counters, avg for gauges
3. **Set Reasonable Time Ranges**: Large ranges impact query performance
4. **Monitor Circuit Breakers**: Check for frequently tripped breakers
5. **Regular Compaction**: Run `TimeSeriesStore.compact()` weekly

## Examples

### Basic Cluster Query
```bash
curl "http://localhost:4000/metrics/cluster?metric=vsm.variety_absorbed&aggregation=sum"
```

### Time-Range Query
```bash
curl "http://localhost:4000/metrics/cluster?metric=latency&aggregation=p95&from=2024-01-01T00:00:00Z&to=2024-01-02T00:00:00Z"
```

### Node-Specific Query
```bash
curl "http://localhost:4000/metrics/cluster?metric=cpu.usage&nodes=node1@host,node2@host"
```

## Future Enhancements

- Automatic anomaly detection
- Predictive scaling based on metrics
- GraphQL API for complex queries
- Integration with external TSDB (InfluxDB, TimescaleDB)