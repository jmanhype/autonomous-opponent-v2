# EventBus Cluster Architecture

## Overview

The EventBus Cluster transforms the Autonomous Opponent from a single-node VSM (Viable System Model) into a truly distributed cybernetic organism. This implementation follows Stafford Beer's cybernetic principles while leveraging modern distributed systems techniques.

## Cybernetic Foundations

### Stafford Beer's VSM in Distributed Context

The EventBus Cluster implements a recursive VSM structure where:

- **Each node is a complete VSM instance** (S1-S5 subsystems)
- **Cross-node channels connect corresponding subsystems**
- **Algedonic signals provide zero-latency pain/pleasure propagation**
- **Variety management prevents information overload**
- **Recursive structure enables fractal scaling**

```
System VSM (Level 0) - Distributed Cluster
├── Node VSM A (Level 1)
│   ├── S1: Operations + Cross-node S1 channels
│   ├── S2: Coordination + Anti-oscillation sync
│   ├── S3: Control + Resource optimization sync
│   ├── S4: Intelligence + Pattern sharing
│   └── S5: Policy + Governance coordination
├── Node VSM B (Level 1)
└── Node VSM C (Level 1)
```

### Key Cybernetic Principles

1. **Ashby's Law of Requisite Variety**: The cluster must match environmental variety
2. **Variety Absorption**: Higher levels absorb variety from lower levels
3. **Algedonic Channels**: Pain/pleasure signals bypass normal processing
4. **Recursive Viability**: Each level maintains its own viability

## Architecture Components

### 1. ClusterBridge (Main Orchestrator)

**File**: `cluster_bridge.ex`

The ClusterBridge is the central nervous system component that:

- **Manages peer connections** using circuit breaker patterns
- **Classifies events** by VSM subsystem (S1-S5 + Algedonic)
- **Applies variety constraints** before cross-node transmission
- **Handles graceful degradation** during network partitions

```elixir
# Event classification by VSM channel
@algedonic_events [:emergency_algedonic, :algedonic_pain, :algedonic_pleasure]
@s5_policy_events [:policy_update, :governance_decision]
@s4_intelligence_events [:pattern_detected, :environment_scan]
@s3_control_events [:resource_allocation, :optimization_directive]
@s2_coordination_events [:anti_oscillation, :synchronization]
@s1_operational_events [:task_execution, :operational_metric]
```

**Key Features**:
- Circuit breakers prevent cascade failures
- HLC timestamps ensure causal ordering
- Event deduplication prevents loops
- Telemetry integration for observability

### 2. AlgedonicBroadcast (Zero-Latency Signals)

**File**: `algedonic_broadcast.ex`

Implements the critical algedonic bypass channel:

- **Multiple redundant paths**: GenServer, RPC, UDP broadcast
- **Confirmation mechanism**: Tracks delivery to all nodes
- **Retry logic**: Up to 3 retries for failed confirmations
- **Priority handling**: Bypasses all variety constraints

```elixir
# Emergency scream with confirmation
def emergency_scream(signal) do
  # 1. Direct GenServer messages (fastest)
  # 2. RPC calls (reliable)
  # 3. Phoenix.PubSub if available
  # 4. UDP broadcast (last resort)
  # 5. Local S5 notification
end
```

**Signal Types**:
- **Pain Signals**: Indicate system stress or threats
- **Pleasure Signals**: Indicate positive outcomes
- **Emergency Screams**: Critical system-wide alerts

### 3. VarietyManager (Channel Capacity Control)

**File**: `variety_manager.ex`

Implements Ashby's variety engineering:

- **Token bucket algorithm** with VSM-specific quotas
- **Semantic compression** to reduce similar events
- **Adaptive rate adjustment** based on system pressure
- **Algedonic bypass** for critical signals

```elixir
# Channel quotas (events per second)
quotas: %{
  algedonic: :unlimited,    # Pain/pleasure bypass all limits
  s5_policy: 50,           # Governance decisions
  s4_intelligence: 100,    # Pattern recognition
  s3_control: 200,         # Resource management
  s2_coordination: 500,    # Anti-oscillation
  s1_operational: 1000,    # Routine operations
  general: 100             # Unclassified events
}
```

**Compression Algorithm**:
1. Generate event signature based on structure
2. Find similar events in time window
3. Aggregate similar events into compressed form
4. Track compression ratio for telemetry

### 4. PartitionDetector (Split-Brain Handling)

**File**: `partition_detector.ex`

Sophisticated partition detection using multiple strategies:

- **Quorum-based detection**: Traditional majority voting
- **VSM health-based**: Uses algedonic signals for health
- **Asymmetric failure detection**: Detects one-way failures
- **Tarjan's algorithm**: Finds strongly connected components

```elixir
# Detection strategies
:static_quorum    # Only majority partition continues
:dynamic_weights  # Weight by VSM subsystem health
:vsm_health      # Use algedonic signals for viability
:manual          # Alert operators and wait
```

**Resolution Process**:
1. Build communication graph between all nodes
2. Detect strongly connected components (partitions)
3. Apply resolution strategy (quorum/weights/health)
4. Notify S5 (Policy) subsystem of partition
5. Enter degraded mode for unreachable nodes

### 5. Cluster.Supervisor (OTP Management)

**File**: `supervisor.ex`

Manages the lifecycle of cluster components:

```elixir
# Supervision tree with proper dependencies
children = [
  {PartitionDetector, opts},      # Must start first
  {VarietyManager, opts},         # Needed by ClusterBridge
  {AlgedonicBroadcast, opts},     # Independent operation
  {ClusterBridge, opts}           # Main coordinator
]

# :rest_for_one strategy ensures proper shutdown order
```

### 6. Telemetry Integration

**File**: `telemetry.ex`

Comprehensive observability:

- **Variety flow metrics**: Throughput, pressure, throttling
- **Algedonic signal metrics**: Latency, confirmation rates
- **Cluster health metrics**: Connectivity, partitions
- **Performance metrics**: Memory, CPU, network

## Configuration

### Basic Configuration

```elixir
# config/cluster.exs
config :autonomous_opponent_core, AutonomousOpponentV2Core.EventBus.Cluster,
  enabled: true,
  
  # Node discovery
  topology: [
    vsm_cluster: [
      strategy: Cluster.Strategy.Gossip,
      config: [port: 45892, multicast_addr: "224.1.1.2"]
    ]
  ],
  
  # Partition handling
  partition_strategy: :static_quorum,
  quorum_size: :majority,
  
  # Variety quotas
  variety_quotas: %{
    algedonic: :unlimited,
    s5_policy: 50,
    s4_intelligence: 100,
    s3_control: 200,
    s2_coordination: 500,
    s1_operational: 1000
  }
```

### Environment-Specific Configuration

**Development** (Epmd discovery):
```elixir
topology: [
  vsm_cluster: [
    strategy: Cluster.Strategy.Epmd,
    config: [hosts: [:"vsm1@localhost", :"vsm2@localhost"]]
  ]
]
```

**Production** (Kubernetes discovery):
```elixir
topology: [
  vsm_cluster: [
    strategy: Cluster.Strategy.Kubernetes,
    config: [
      kubernetes_selector: "app=autonomous-opponent",
      kubernetes_namespace: "production"
    ]
  ]
]
```

## Deployment Guide

### Single Node to Cluster Migration

1. **Phase 1: Enable Clustering**
   ```bash
   # Start with clustering enabled but no peers
   iex --name vsm1@localhost -S mix
   ```

2. **Phase 2: Add Peer Nodes**
   ```bash
   # Start additional nodes
   iex --name vsm2@localhost -S mix
   iex --name vsm3@localhost -S mix
   ```

3. **Phase 3: Verify Cluster Formation**
   ```elixir
   # Check topology
   AutonomousOpponentV2Core.EventBus.Cluster.topology()
   
   # Test algedonic signals
   AutonomousOpponentV2Core.EventBus.Cluster.algedonic_scream(%{
     type: :pain,
     severity: 8,
     source: :deployment_test,
     data: %{message: "Cluster formation test"}
   })
   ```

### Production Deployment

**Docker Swarm**:
```yaml
version: '3.8'
services:
  vsm-node:
    image: autonomous-opponent:latest
    deploy:
      replicas: 3
    environment:
      - RELEASE_DISTRIBUTION=name
      - RELEASE_NODE=vsm-${HOSTNAME}@tasks.vsm-node
    networks:
      - vsm-cluster
```

**Kubernetes**:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: autonomous-opponent
spec:
  serviceName: "vsm-cluster"
  replicas: 3
  template:
    spec:
      containers:
      - name: vsm-node
        image: autonomous-opponent:latest
        env:
        - name: RELEASE_DISTRIBUTION
          value: "name"
        - name: RELEASE_NODE
          value: "vsm-$(hostname)@$(POD_IP)"
```

## Monitoring and Observability

### Key Metrics to Monitor

1. **Variety Pressure** (`variety_pressure` 0.0-1.0):
   - < 0.5: Healthy
   - 0.5-0.8: Moderate pressure
   - > 0.8: High pressure (throttling occurs)

2. **Algedonic Latency** (milliseconds):
   - < 100ms: Excellent
   - 100-500ms: Good
   - > 500ms: Concerning

3. **Partition Status**:
   - `:healthy`: All nodes connected
   - `{:partitioned, partitions}`: Split-brain detected

4. **Circuit Breaker Status**:
   - Monitor failure rates per node
   - Track recovery times

### Telemetry Events

```elixir
# Variety flow
[:vsm, :cluster, :variety, :flow]       # Event throughput
[:vsm, :cluster, :variety, :throttled]  # Throttling events
[:vsm, :cluster, :variety, :compressed] # Compression events

# Algedonic signals
[:vsm, :cluster, :algedonic, :broadcast_latency]  # Signal propagation time
[:vsm, :cluster, :algedonic, :confirmation]       # Delivery confirmations

# Cluster health
[:vsm, :cluster, :partition, :detected]  # Partition events
[:vsm, :cluster, :node, :connected]      # Node join/leave
```

### Grafana Dashboard Example

```json
{
  "dashboard": {
    "title": "VSM Cluster Health",
    "panels": [
      {
        "title": "Variety Pressure by Channel",
        "type": "graph",
        "targets": [
          {
            "expr": "vsm_cluster_variety_pressure{channel=\"s1_operational\"}",
            "legendFormat": "S1 Operations"
          },
          {
            "expr": "vsm_cluster_variety_pressure{channel=\"s5_policy\"}",
            "legendFormat": "S5 Policy"
          }
        ]
      },
      {
        "title": "Algedonic Signal Latency",
        "type": "graph",
        "targets": [
          {
            "expr": "vsm_cluster_algedonic_latency_ms",
            "legendFormat": "Signal Propagation Time"
          }
        ]
      }
    ]
  }
}
```

## Troubleshooting

### Common Issues

1. **High Variety Pressure**
   ```elixir
   # Check which channels are under pressure
   stats = AutonomousOpponentV2Core.EventBus.Cluster.variety_stats()
   IO.inspect(stats.pressure_by_channel)
   
   # Increase quotas if needed
   config :autonomous_opponent_core, AutonomousOpponentV2Core.EventBus.Cluster,
     variety_quotas: %{s1_operational: 2000}  # Increase from 1000
   ```

2. **Partition Detection False Positives**
   ```elixir
   # Check partition detector status
   status = AutonomousOpponentV2Core.EventBus.Cluster.partition_status()
   
   # Adjust detection sensitivity
   config :autonomous_opponent_core, AutonomousOpponentV2Core.EventBus.Cluster,
     partition_check_interval: 10_000  # Increase from 5000ms
   ```

3. **Algedonic Signal Failures**
   ```elixir
   # Check algedonic stats
   stats = AutonomousOpponentV2Core.EventBus.Cluster.health_report().algedonic_stats
   
   # Look for failed nodes
   IO.inspect(stats.total_failed_nodes)
   ```

4. **Circuit Breaker Issues**
   ```elixir
   # Check topology for circuit breaker states
   topology = AutonomousOpponentV2Core.EventBus.Cluster.topology()
   IO.inspect(topology.peer_states)
   ```

### Debug Commands

```elixir
# Get comprehensive health report
AutonomousOpponentV2Core.EventBus.Cluster.health_report()

# Force partition check
AutonomousOpponentV2Core.EventBus.Cluster.check_partitions()

# Test algedonic signal
AutonomousOpponentV2Core.EventBus.Cluster.algedonic_scream(%{
  type: :pain, severity: 5, source: :debug, data: %{test: true}
})

# Monitor variety pressure
Stream.interval(1000)
|> Stream.map(fn _ -> 
  AutonomousOpponentV2Core.EventBus.Cluster.variety_pressure()
end)
|> Enum.take(10)
```

## Performance Characteristics

### Scalability

- **2-10 nodes**: Full mesh topology, all-to-all communication
- **10-100 nodes**: Hierarchical topology recommended
- **100+ nodes**: Sharding with gossip protocols

### Latency Expectations

- **Local events**: 1-5 microseconds
- **LAN events**: 100-500 microseconds  
- **WAN events**: 10-100 milliseconds
- **Algedonic signals**: < 100ms target

### Memory Usage

- **Base overhead**: ~10MB per node
- **Event cache**: ~1MB per 10,000 cached events
- **Peer state**: ~1KB per connected node

## Security Considerations

### Node Authentication

The cluster relies on Erlang distribution security:

```bash
# Set erlang cookie for authentication
export RELEASE_COOKIE="secure-cluster-cookie-here"

# Use TLS for inter-node communication
export ERL_FLAGS="-proto_dist inet_tls"
```

### Network Security

1. **Firewall Rules**: Only allow cluster nodes to connect
2. **VPN/Private Networks**: Use private networking
3. **TLS Encryption**: Enable for production deployments

### Event Filtering

```elixir
# Validate events before processing
defp validate_remote_event(event, from_node, state) do
  with :ok <- validate_event_structure(event),
       :ok <- validate_source_node(from_node),
       :ok <- validate_event_signature(event) do
    {:ok, event}
  end
end
```

## Future Enhancements

### Planned Features

1. **Adaptive Topology**: Automatic topology optimization
2. **ML-Based Variety Prediction**: Predict and prevent overload
3. **Cross-Datacenter Support**: WAN-optimized protocols
4. **Event Sourcing Integration**: Persistent event streams
5. **Chaos Engineering**: Built-in failure injection

### Research Areas

1. **Quantum-Inspired Clustering**: Explore quantum algorithms
2. **Biological Network Patterns**: Bio-inspired topologies
3. **Advanced Compression**: AI-powered semantic compression
4. **Predictive Scaling**: ML-based capacity planning

## Conclusion

The EventBus Cluster represents a significant evolution in distributed systems architecture, combining Stafford Beer's cybernetic wisdom with modern distributed computing techniques. By implementing true VSM principles at scale, we create not just a distributed system, but a distributed **organism** capable of adaptation, learning, and self-organization.

The system embodies the principle that "the purpose of a system is what it does" - and what this system does is create a resilient, adaptive, self-organizing distributed intelligence that can maintain viability across any scale of deployment.