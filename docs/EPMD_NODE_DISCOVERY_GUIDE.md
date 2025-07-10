# EPMD-based CRDT Node Discovery Guide (Issue #89)

## Overview

This document describes the implementation of automatic CRDT peer discovery using Erlang's EPMD (Erlang Port Mapper Daemon), replacing the previous hardcoded peer configuration.

## Problem Solved

Previously, CRDT sync peers had to be manually configured with hardcoded node names. This made dynamic cluster formation impossible and required manual intervention for every topology change.

## Solution Architecture

### Components

1. **EPMDDiscovery GenServer** (`apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/amcp/memory/epmd_discovery.ex`)
   - Monitors Erlang nodes via `:net_kernel.monitor_nodes/2`
   - Polls for new nodes every 10 seconds (configurable)
   - Implements stability tracking before adding peers
   - Manages node filtering and peer limits

2. **CRDT Store Integration**
   - `discover_peers/0` now triggers EPMD discovery
   - Fallback to EventBus discovery if EPMD not available
   - Automatic sync initiation with discovered peers

3. **Configuration** (`config/dev.exs`)
   ```elixir
   config :autonomous_opponent_core, AutonomousOpponentV2Core.AMCP.Memory.EPMDDiscovery,
     enabled: true,
     discovery_interval: 10_000,  # 10 seconds
     max_peers: 100,
     node_filter: fn node -> ... end
   ```

## How It Works

### Discovery Process

1. **Node Monitoring**: EPMDDiscovery subscribes to Erlang node events (nodeup/nodedown)
2. **Periodic Polling**: Every 10 seconds, queries `Node.list()` and EPMD for all nodes
3. **Stability Tracking**: New nodes must be seen 3 times before being added as CRDT peers
4. **Filtering**: Applies configurable node filter (e.g., only nodes with certain prefixes)
5. **Automatic Addition**: Stable nodes are automatically added to CRDT sync peers
6. **Cleanup**: Departed nodes are automatically removed from sync peers

### Discovery Methods

- **Primary**: `Node.list(:visible)`, `Node.list(:hidden)`, `Node.list(:known)`
- **Secondary**: `:net_adm.names()` for local EPMD registry
- **Real-time**: `:net_kernel.monitor_nodes/2` for immediate notifications

## Usage

### Basic Setup

1. **Start nodes with distributed Erlang**:
   ```bash
   # Node 1
   iex --sname node1 --cookie my_cookie -S mix
   
   # Node 2  
   iex --sname node2 --cookie my_cookie -S mix
   ```

2. **Nodes automatically discover each other within 10 seconds**

### Manual Operations

```elixir
# Trigger immediate discovery
CRDTStore.discover_peers()

# Check discovery status
EPMDDiscovery.status()

# Enable/disable discovery
EPMDDiscovery.set_enabled(false)

# Check CRDT peers
CRDTStore.get_cluster_members()
```

### Demo Script

Run the interactive demo to see discovery in action:

```bash
# Terminal 1
NODE_NAME=crdt1 mix run scripts/demo_epmd_discovery.exs

# Terminal 2
NODE_NAME=crdt2 mix run scripts/demo_epmd_discovery.exs

# Terminal 3
NODE_NAME=crdt3 mix run scripts/demo_epmd_discovery.exs
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable/disable automatic discovery |
| `discovery_interval` | integer | `10_000` | Base milliseconds between discovery runs (adaptive) |
| `max_peers` | integer | `100` | Maximum number of CRDT sync peers |
| `stability_threshold` | integer | `3` | Sightings required before adding as peer |
| `sync_cooldown_ms` | integer | `1_000` | Minimum ms between sync operations |
| `node_filter` | function | (see below) | Function to filter acceptable nodes |

### Default Node Filter

By default, only nodes with matching prefixes are accepted:
```elixir
fn node ->
  # Extract prefix before @ or first number
  self_prefix = extract_node_prefix(to_string(node()))
  node_prefix = extract_node_prefix(to_string(node))
  self_prefix == node_prefix
end
```

## Cybernetic Alignment

The implementation follows VSM (Viable System Model) principles:

- **S1 (Operations)**: Autonomous peer discovery without manual intervention
- **S2 (Coordination)**: Anti-oscillation through stability tracking and sync cooldowns
- **S3 (Control)**: Resource limits, adaptive intervals, and peer selection optimization
- **S4 (Intelligence)**: Environmental scanning via EPMD with real-time monitoring
- **S5 (Policy)**: Configurable constraints, filters, and thresholds

### Adaptive Behavior

The system adapts to its environment:
- Discovery interval increases with cluster size to reduce network overhead
- Stability tracking prevents rapid peer churn during network instability
- Sync cooldowns prevent cascading sync storms in large clusters

## Testing

### Unit Tests
```bash
mix test test/autonomous_opponent_v2_core/amcp/memory/epmd_discovery_test.exs
```

### Integration Tests
The distributed tests require actual Erlang nodes:
```bash
mix test --only distributed
```

## Monitoring

### Telemetry Events

- `[:epmd_discovery, :peer_added]` - New peer discovered and added
- `[:epmd_discovery, :discovery_completed]` - Discovery scan completed with metrics
- `[:crdt_store, :sync_timeout]` - Sync timeout with peer

Example telemetry handler:
```elixir
:telemetry.attach(
  "log-discovery",
  [:epmd_discovery, :discovery_completed],
  fn _event, measurements, metadata, _config ->
    Logger.info("Discovery completed: #{measurements.discovered} new, #{measurements.removed} removed, #{measurements.duration_ms}ms")
  end,
  nil
)```
- `[:crdt_store, :backpressure, :dropped]` - Sync request dropped due to overload

### Logs

```
[info] 🚀 EPMD Discovery initialized - Maximum intensity peer discovery activated!
[info] ⚡ EPMD: Node detected via monitor - node2@localhost
[info] ✨ EPMD Discovery: Found new node node2@localhost
[info] ✅ EPMD Discovery: Added node2@localhost as CRDT peer (stability threshold met)
```

## Troubleshooting

### Nodes Not Discovering Each Other

1. **Check EPMD is running**: `epmd -names`
2. **Verify same cookie**: Nodes must share the same Erlang cookie
3. **Check node names**: Use consistent naming (all short or all long names)
4. **Network connectivity**: Ensure nodes can reach each other
5. **Check filters**: Verify node filter isn't rejecting valid nodes

### Discovery Too Slow/Fast

Adjust `discovery_interval` in configuration:
```elixir
config :autonomous_opponent_core, EPMDDiscovery,
  discovery_interval: 5_000  # 5 seconds instead of 10
```

### Too Many Peers

Adjust `max_peers` limit or make node filter more restrictive:
```elixir
config :autonomous_opponent_core, EPMDDiscovery,
  max_peers: 50,
  node_filter: fn node ->
    # Only production nodes
    String.contains?(to_string(node), "prod")
  end
```

## Migration from Hardcoded Peers

1. **Existing hardcoded peers remain functional** - EPMD discovery is additive
2. **EventBus discovery still works** - Used as fallback if EPMD unavailable
3. **No breaking changes** - All existing CRDT sync functionality preserved

## Future Enhancements

1. **DNS-based discovery** for cross-datacenter clusters
2. **Kubernetes service discovery** integration
3. **Consul/etcd integration** for service mesh environments
4. **Peer reputation tracking** for selective sync
5. **Geographic proximity** awareness for optimal peer selection

## Conclusion

EPMD-based discovery transforms the CRDT system from static to dynamic, enabling true distributed operation without manual configuration. The implementation satisfies all requirements from issue #89 while maintaining backward compatibility and following cybernetic design principles.