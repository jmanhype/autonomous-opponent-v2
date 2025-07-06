# Telemetry and Observability Guide

The Autonomous Opponent system provides comprehensive telemetry and observability through structured events, metrics, and dashboards.

## Overview

All telemetry in the system flows through the central `SystemTelemetry` module, which provides:
- Unified event emission
- Span tracking for operations
- Handler registration
- Metric aggregation

## Architecture

```
┌─────────────────────┐
│   Application Code  │
└──────────┬──────────┘
           │ emit
           ▼
┌─────────────────────┐
│   SystemTelemetry   │
└──────────┬──────────┘
           │ :telemetry.execute
           ▼
┌─────────────────────┐     ┌──────────────────┐
│  Telemetry Handlers │────▶│ Phoenix Dashboard│
└─────────────────────┘     └──────────────────┘
           │                         │
           ▼                         ▼
    ┌──────────────┐         ┌──────────────┐
    │   Logging    │         │   Metrics    │
    └──────────────┘         └──────────────┘
```

## Telemetry Events

### Consciousness Events

#### `[:consciousness, :state_change]`
Emitted when consciousness changes state.
- **Measurements**: `%{duration: nanoseconds}`
- **Metadata**: `%{from_state: atom, to_state: atom}`

#### `[:consciousness, :decision_made]`
Emitted when consciousness makes a decision.
- **Measurements**: `%{confidence: float, duration: nanoseconds}`
- **Metadata**: `%{decision_type: atom}`

#### `[:consciousness, :reflection_completed]`
Emitted after consciousness completes a reflection.
- **Measurements**: `%{insights_count: integer, duration: nanoseconds}`
- **Metadata**: `%{aspect: string, awareness_level: float}`

#### `[:consciousness, :awareness_level_changed]`
Emitted when awareness level changes significantly (>0.1).
- **Measurements**: `%{delta: float}`
- **Metadata**: `%{from_level: float, to_level: float, triggers: list}`

#### `[:consciousness, :dialog_exchange]`
Emitted for each dialog exchange with consciousness.
- **Measurements**: `%{message_length: integer, response_length: integer}`
- **Metadata**: `%{conversation_id: string}`

#### `[:consciousness, :existential_inquiry]`
Emitted for existential questions posed to consciousness.
- **Measurements**: `%{inquiry_count: integer}`
- **Metadata**: `%{question_length: integer}`

### VSM Events

#### S1 Operations Events

#### `[:vsm, :s1, :operation, :start]`
Operation begins in S1.
- **Measurements**: `%{input_variety: integer}`
- **Metadata**: `%{operation: atom}`

#### `[:vsm, :s1, :operation, :stop]`
Operation completes in S1.
- **Measurements**: `%{duration: nanoseconds, output_variety: integer}`
- **Metadata**: `%{operation: atom}`

#### `[:vsm, :s1, :operation, :exception]`
Operation fails in S1.
- **Measurements**: `%{duration: nanoseconds}`
- **Metadata**: `%{operation: atom, error: term}`

#### `[:vsm, :s1, :variety_absorbed]`
S1 absorbs variety from environment.
- **Measurements**: `%{input_variety: integer, absorbed_variety: integer, efficiency: float}`
- **Metadata**: `%{server_name: string}`

#### S2 Coordination Events

#### `[:vsm, :s2, :anti_oscillation_triggered]`
S2 detects and dampens oscillation.
- **Measurements**: `%{damping_factor: float}`
- **Metadata**: `%{oscillation_type: atom}`

#### S3 Control Events

#### `[:vsm, :s3, :resource_allocated]`
S3 allocates resources.
- **Measurements**: `%{amount: number, utilization: float}`
- **Metadata**: `%{resource_type: atom}`

#### S4 Intelligence Events

#### `[:vsm, :s4, :threat_detected]`
S4 detects environmental threat.
- **Measurements**: `%{severity: float, confidence: float}`
- **Metadata**: `%{threat_type: atom}`

#### `[:vsm, :s4, :opportunity_identified]`
S4 identifies opportunity.
- **Measurements**: `%{potential_value: float, confidence: float}`
- **Metadata**: `%{opportunity_type: atom}`

#### S5 Policy Events

#### `[:vsm, :s5, :policy_updated]`
S5 updates system policy.
- **Measurements**: `%{changes_count: integer}`
- **Metadata**: `%{policy_domain: atom}`

#### `[:vsm, :s5, :constraint_violation]`
S5 detects constraint violation.
- **Measurements**: `%{severity: float}`
- **Metadata**: `%{constraint_type: atom}`

#### Algedonic Events

#### `[:vsm, :algedonic, :pain_signal]`
Pain signal received.
- **Measurements**: `%{intensity: float}`
- **Metadata**: `%{source: atom, bypass_activated: boolean}`

#### `[:vsm, :algedonic, :pleasure_signal]`
Pleasure signal received.
- **Measurements**: `%{intensity: float}`
- **Metadata**: `%{source: atom, bypass_activated: boolean}`

### EventBus Events

#### `[:event_bus, :publish]`
Event published to bus.
- **Measurements**: `%{message_size: bytes}`
- **Metadata**: `%{topic: atom}`

#### `[:event_bus, :subscribe]`
New subscription created.
- **Measurements**: `%{}`
- **Metadata**: `%{event_type: atom}`

#### `[:event_bus, :broadcast]`
Event broadcast completed.
- **Measurements**: `%{recipient_count: integer, duration: nanoseconds}`
- **Metadata**: `%{topic: atom}`

#### `[:event_bus, :message_dropped]`
Message dropped due to dead process or overflow.
- **Measurements**: `%{queue_size: integer}`
- **Metadata**: `%{topic: atom, reason: atom}`

### LLM Events

#### `[:llm, :request, :start]`
LLM API request begins.
- **Measurements**: `%{prompt_tokens: integer}`
- **Metadata**: `%{provider: atom, model: string}`

#### `[:llm, :request, :stop]`
LLM API request completes.
- **Measurements**: `%{duration: nanoseconds, total_tokens: integer, estimated_cost: float}`
- **Metadata**: `%{provider: atom, model: string}`

#### `[:llm, :cache, :hit]`
LLM cache hit.
- **Measurements**: `%{ttl: seconds}`
- **Metadata**: `%{intent: atom}`

#### `[:llm, :cache, :miss]`
LLM cache miss.
- **Measurements**: `%{}`
- **Metadata**: `%{intent: atom, reason: atom}`

#### `[:llm, :rate_limit]`
LLM rate limit encountered.
- **Measurements**: `%{retry_after: seconds}`
- **Metadata**: `%{provider: atom}`

#### `[:llm, :token_usage]`
Token usage for completed request.
- **Measurements**: `%{prompt_tokens: integer, response_tokens: integer, total_tokens: integer, estimated_cost: float}`
- **Metadata**: `%{provider: atom, model: string, intent: atom}`

### System Events

#### `[:vm, :memory]`
VM memory statistics.
- **Measurements**: `%{total: bytes, processes: bytes, binary: bytes, ets: bytes}`
- **Metadata**: `%{}`

#### `[:system, :health_check]`
Health check completed.
- **Measurements**: `%{checks_passed: integer, total_checks: integer, duration: nanoseconds}`
- **Metadata**: `%{status: atom}`

#### `[:system, :circuit_breaker, :opened]`
Circuit breaker opened.
- **Measurements**: `%{failure_count: integer, threshold: integer}`
- **Metadata**: `%{name: atom}`

#### `[:system, :rate_limit, :exceeded]`
Rate limit exceeded.
- **Measurements**: `%{limit: integer, window: seconds}`
- **Metadata**: `%{key: string}`

## Using Telemetry

### Emitting Events

```elixir
# Simple event
SystemTelemetry.emit(
  [:my_app, :operation_completed],
  %{duration: 1500, items_processed: 42},
  %{user_id: "user123"}
)

# Using measurement helper
SystemTelemetry.measure([:my_app, :expensive_operation], %{}, fn ->
  # Your code here
  do_expensive_work()
end)

# Using spans for async operations
start_metadata = SystemTelemetry.start_span([:my_app, :async_work])
# ... do work ...
SystemTelemetry.stop_span([:my_app, :async_work], start_metadata, %{items: 10})
```

### Attaching Handlers

Handlers are automatically attached by `SystemTelemetry.setup()`, but you can add custom handlers:

```elixir
:telemetry.attach(
  "my-custom-handler",
  [:my_app, :special_event],
  &MyApp.handle_telemetry_event/4,
  nil
)
```

### Viewing Metrics

#### LiveDashboard

Access the Phoenix LiveDashboard at `/dashboard` to see:
- Real-time metrics
- Historical charts
- System performance
- Custom dashboards

#### Prometheus Export

Metrics are exported for Prometheus at `/metrics` endpoint.

#### Custom Dashboards

The telemetry dashboard configuration in `TelemetryDashboard` provides:
- Consciousness metrics (awareness, reflections, state changes)
- VSM subsystem metrics (S1-S5 operations)
- EventBus flow metrics
- LLM usage and costs
- System health metrics

## Best Practices

1. **Event Naming**: Use hierarchical naming `[:app, :subsystem, :action]`
2. **Measurements**: Include numeric values that can be aggregated
3. **Metadata**: Include contextual information for filtering/grouping
4. **Performance**: Telemetry is designed to be low-overhead, but avoid:
   - Complex calculations in event emission
   - Large data structures in metadata
   - Excessive event frequency (>1000/sec per event)

5. **Span Usage**: Use spans for operations that:
   - Are asynchronous
   - Cross process boundaries
   - Need duration tracking

## Telemetry Configuration

Configure telemetry in your `config.exs`:

```elixir
config :autonomous_opponent_core,
  telemetry_enabled: true,
  telemetry_log_level: :info,
  telemetry_sampling_rate: 1.0  # 1.0 = 100% sampling

config :phoenix, :live_dashboard,
  metrics: AutonomousOpponentV2Web.Telemetry,
  metrics_history: [
    {AutonomousOpponentV2Web.Telemetry.Metrics, :metrics_history, []}
  ]
```

## Monitoring Alerts

Key metrics to monitor:

1. **Consciousness Health**
   - Awareness level < 0.3 for extended periods
   - State changes failing repeatedly
   - Reflection completion rate dropping

2. **VSM Performance**
   - S1 variety absorption efficiency < 0.5
   - S2 anti-oscillation triggers > 10/min
   - S4 threat detection spikes
   - S5 constraint violations

3. **LLM Usage**
   - Token usage exceeding budget
   - Cache hit rate < 20%
   - Rate limit frequency
   - Provider switch frequency

4. **System Health**
   - Memory usage > 80%
   - Process count > 10,000
   - Circuit breakers opening
   - Health check failures

## Troubleshooting

### Missing Events

If events aren't appearing:
1. Verify `SystemTelemetry.setup()` was called
2. Check handler attachment with `:telemetry.list_handlers()`
3. Verify event names match exactly
4. Check log level configuration

### Performance Impact

If telemetry is impacting performance:
1. Reduce sampling rate for high-frequency events
2. Simplify metadata structures
3. Use async handlers for expensive operations
4. Consider batching related events

### Dashboard Issues

If LiveDashboard metrics aren't updating:
1. Verify telemetry poller is running
2. Check metric definitions in `TelemetryDashboard`
3. Ensure events are being emitted with correct names
4. Verify reporter configuration

## Extending Telemetry

To add new telemetry:

1. Define events in your module
2. Add handlers in `SystemTelemetry`
3. Add metrics in `TelemetryDashboard`
4. Document events in this guide
5. Consider adding alerts for critical metrics

Remember: Good observability is key to understanding and operating complex cybernetic systems!