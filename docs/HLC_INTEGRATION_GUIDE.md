# Hybrid Logical Clock (HLC) Integration Guide

## Overview

The Hybrid Logical Clock (HLC) system provides deterministic, causally-ordered timestamps throughout the VSM to replace all `DateTime.utc_now()` calls. This ensures consistent ordering of events across distributed components and enables reliable event sequencing for proper VSM operation.

## Key Components

### 1. HybridLogicalClock Module
- **Location**: `apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/core/hybrid_logical_clock.ex`
- **Purpose**: Core HLC implementation with physical time + logical counters
- **Features**:
  - Thread-safe timestamp generation
  - Remote timestamp synchronization
  - Content-based event ID generation
  - Total ordering of events
  - Clock drift protection

### 2. VSM.Clock Module
- **Location**: `apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/vsm/clock.ex`
- **Purpose**: VSM-specific convenience wrapper for HLC operations
- **Features**:
  - VSM event creation with HLC timestamps
  - Event ordering and filtering
  - Correlation ID generation
  - Time window operations

## Integration Steps

### Phase 1: Replace DateTime.utc_now() calls

**Before (non-deterministic):**
```elixir
timestamp = DateTime.utc_now()
event = %{
  id: UUID.uuid4(),
  timestamp: timestamp,
  data: payload
}
```

**After (deterministic with HLC):**
```elixir
{:ok, event} = VSM.Clock.create_event(:s1, :operation_complete, payload)
# event now has deterministic timestamp and content-based ID
```

### Phase 2: Update Event Structures

All VSM events should use the standardized event structure:

```elixir
%{
  id: "1751831818009-2-node-abc123de",        # Content-based ID
  subsystem: :s1,                             # VSM subsystem
  type: :operation_complete,                  # Event type
  data: %{...},                               # Event payload
  timestamp: %{                               # HLC timestamp
    physical: 1751831818009,                  # Physical time (ms)
    logical: 2,                               # Logical counter
    node_id: "node-abc123de"                  # Node identifier
  },
  created_at: "2025-07-06T19:56:58.009Z.2@node-abc123de"  # String representation
}
```

### Phase 3: Update VSM Subsystems

#### S1 External Operations
```elixir
# OLD
operation_result = %{
  timestamp: DateTime.utc_now(),
  result: result_data
}

# NEW
{:ok, operation_event} = VSM.Clock.create_event(:s1, :operation_complete, result_data)
```

#### S2 Coordination
```elixir
# OLD
coordination_signal = %{
  from: :s1,
  to: :s3,
  timestamp: DateTime.utc_now(),
  message: anti_oscillation_data
}

# NEW
{:ok, coord_event} = VSM.Clock.create_event(:s2, :coordination_signal, %{
  from: :s1,
  to: :s3,
  message: anti_oscillation_data
})
```

#### S3 Control
```elixir
# Use HLC for resource allocation decisions
{:ok, control_event} = VSM.Clock.create_event(:s3, :resource_allocation, allocation_data)
```

#### S4 Intelligence
```elixir
# Use HLC for intelligence scanning
{:ok, intelligence_event} = VSM.Clock.create_event(:s4, :environmental_scan, scan_results)
```

#### S5 Policy
```elixir
# Use HLC for policy decisions
{:ok, policy_event} = VSM.Clock.create_event(:s5, :policy_update, new_constraints)
```

### Phase 4: Event Ordering and Processing

#### Ordering Events by Timestamp
```elixir
# Get events from multiple sources
events = [s1_events, s2_events, s3_events] |> List.flatten()

# Order them deterministically
ordered_events = VSM.Clock.order_events(events)

# Process in correct causal order
Enum.each(ordered_events, &process_event/1)
```

#### Finding Recent Events
```elixir
# Find events within last 5 seconds
recent_events = Enum.filter(events, fn event ->
  VSM.Clock.within_window?(event, 5000)
end)
```

#### Correlation Tracking
```elixir
# Create correlation ID for related operations
{:ok, correlation_id} = VSM.Clock.correlation_id("s1_s2_coordination")

# Use in related events
{:ok, event1} = VSM.Clock.create_event(:s1, :start_op, %{correlation: correlation_id})
{:ok, event2} = VSM.Clock.create_event(:s2, :respond_op, %{correlation: correlation_id})
```

## Distributed Synchronization

### Receiving Remote Timestamps
```elixir
# When receiving events from remote VSM nodes
remote_event = %{timestamp: remote_hlc_timestamp, ...}

# Synchronize local clock with remote
{:ok, updated_local_timestamp} = VSM.Clock.sync_with_remote(remote_hlc_timestamp)

# Continue with local operations using updated timestamp
```

### Cross-Node Event Ordering
```elixir
# Events from multiple nodes can be properly ordered
local_events = get_local_events()
remote_events = get_remote_events()

all_events = local_events ++ remote_events
causally_ordered = VSM.Clock.order_events(all_events)
```

## Performance Considerations

### Timestamp Generation Performance
- HLC.now() is ~2-3x slower than DateTime.utc_now()
- Overhead is minimal for VSM operations (microseconds)
- Benefits of deterministic ordering far outweigh cost

### Memory Usage
- Each HLC timestamp: ~100 bytes
- Event IDs: ~50-60 characters
- Minimal impact on overall system memory

### Event Storage
```elixir
# Use partition keys for efficient storage
partition_key = VSM.Clock.partition_key(event, 16)
# Store event in appropriate partition
```

## Best Practices

### 1. Always Use VSM.Clock for Events
```elixir
# ✅ GOOD
{:ok, event} = VSM.Clock.create_event(:s1, :operation, data)

# ❌ AVOID
event = %{timestamp: DateTime.utc_now(), ...}
```

### 2. Validate Event Timestamps
```elixir
if VSM.Clock.valid_event?(event) do
  process_event(event)
else
  Logger.warning("Invalid event timestamp structure")
end
```

### 3. Use Content-Based IDs
```elixir
# Events with same content will have same ID (idempotent)
{:ok, event_id} = HybridLogicalClock.event_id(deterministic_data)
```

### 4. Monitor Clock Drift
```elixir
# HLC will reject excessive drift (>60s by default)
case VSM.Clock.sync_with_remote(remote_timestamp) do
  {:ok, synced} -> :ok
  {:error, :clock_drift_exceeded} -> handle_drift_error()
end
```

## Testing HLC Integration

### Unit Tests
```elixir
test "events are properly ordered" do
  # Create sequence of events
  events = create_test_events()
  
  # Verify ordering
  ordered = VSM.Clock.order_events(events)
  assert_events_chronological(ordered)
end
```

### Integration Tests
```elixir
test "cross-subsystem event correlation" do
  {:ok, s1_event} = VSM.Clock.create_event(:s1, :start, data)
  
  # Simulate processing time
  Process.sleep(10)
  
  {:ok, s2_event} = VSM.Clock.create_event(:s2, :respond, data)
  
  # Verify causal ordering
  assert VSM.Clock.before?(s1_event.timestamp, s2_event.timestamp)
end
```

## Migration Checklist

- [ ] Replace all `DateTime.utc_now()` calls with `VSM.Clock.now()`
- [ ] Update event creation to use `VSM.Clock.create_event/3`
- [ ] Implement event ordering using `VSM.Clock.order_events/1`
- [ ] Add timestamp validation using `VSM.Clock.valid_event?/1`
- [ ] Update AMCP bridges to use HLC timestamps
- [ ] Modify consciousness module to use deterministic timestamps
- [ ] Update telemetry to include HLC timestamps
- [ ] Add HLC synchronization to distributed components
- [ ] Test event ordering across all VSM subsystems
- [ ] Verify performance impact is acceptable

## Troubleshooting

### Clock Drift Issues
```elixir
# Monitor for drift warnings
Logger.warning("Clock drift detected: #{inspect(error)}")

# Implement drift correction
case sync_with_time_server() do
  :ok -> retry_operation()
  :error -> fallback_to_local_time()
end
```

### Event Ordering Problems
```elixir
# Debug timestamp issues
events
|> Enum.map(&VSM.Clock.event_to_string/1)
|> Enum.each(&Logger.debug/1)
```

### Performance Issues
```elixir
# Benchmark HLC vs DateTime
{time_hlc, _} = :timer.tc(fn -> 
  Enum.each(1..1000, fn _ -> VSM.Clock.now() end)
end)

{time_dt, _} = :timer.tc(fn ->
  Enum.each(1..1000, fn _ -> DateTime.utc_now() end)
end)

Logger.info("HLC overhead: #{time_hlc / time_dt}x")
```

## Future Enhancements

1. **Persistent HLC State**: Save/restore logical counters across restarts
2. **Network Time Sync**: Integrate with NTP for better physical time accuracy
3. **Distributed Consensus**: Use HLC for distributed decision making
4. **Event Sourcing**: Build event sourcing system on HLC foundation
5. **Temporal Queries**: Query events by HLC time ranges

## Conclusion

The HLC integration provides deterministic, causally-ordered timestamps throughout the VSM system, enabling reliable event sequencing and proper distributed operation. This foundation is essential for the VSM's ability to maintain coherent state across all subsystems.