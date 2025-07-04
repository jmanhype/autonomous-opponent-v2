# Task 8: Complete MCP Gateway Transport Implementation

## Description
Complete HTTP+SSE and WebSocket transport layers for MCP gateway with proper routing and connection pooling

## Implementation Details
Implement HTTP+SSE transport using Phoenix.Endpoint and Server-Sent Events. Complete WebSocket transport with Phoenix.Socket. Add gateway routing with load balancing using consistent hashing. Implement connection pooling with configurable pool sizes. Add proper error handling, reconnection logic, and backpressure management.

## Technical Requirements

### Performance Targets
- Support 10,000+ concurrent connections
- Message latency < 100ms at p99
- Zero message loss during transport failover
- Memory usage < 1KB per idle connection
- Automatic reconnection within 5 seconds
- Throughput of 100,000 messages/second aggregate

### Security Requirements
- Rate limiting per client (100 req/sec default)
- Circuit breaker protection per transport
- Connection authentication via client_id
- Optional TLS encryption for WebSocket
- Automatic session invalidation after idle timeout
- Protection against connection flooding attacks

## Architecture Decisions

### Why Two Transport Layers?
- **SSE**: Ideal for server-push scenarios, lower overhead
  - One-way communication reduces complexity
  - Built-in reconnection in modern browsers
  - Works through proxies and firewalls
  - Lower resource usage for read-only clients
- **WebSocket**: Required for bidirectional communication
  - Real-time interactive features
  - Binary protocol support
  - Lower latency for high-frequency updates
  - Compression for bandwidth optimization

### Why Poolboy for Connection Pooling?
- Battle-tested in production environments
- Configurable overflow handling
- Built-in health checks and lifecycle management
- Proven performance under high load
- Easy integration with OTP supervision trees
- Automatic resource cleanup

### Why Consistent Hashing for Load Balancing?
- Minimal key redistribution when nodes change
- Better cache locality for stateful connections
- Predictable routing for debugging
- Support for weighted distribution
- Built-in replication for high availability

### Resource Requirements (per 10K connections)
- CPU: ~2 cores at 70% utilization
- Memory: ~2GB (200KB per connection including buffers)
- Network: 100Mbps sustained, 1Gbps burst capability
- Disk I/O: Minimal (logs only)

## Monitoring & Observability Requirements

### Core Metrics
- Distributed tracing support (OpenTelemetry)
- Prometheus metrics endpoint at `/metrics`
- Structured logging with correlation IDs
- Real-time dashboard with key metrics
- Alert thresholds for SLO violations

### Required Dashboards
- Connection count by transport type
- Message throughput and latency (p50, p90, p99)
- Error rates and circuit breaker status
- Pool utilization and queue depth
- VSM variety flow metrics

### Alert Thresholds
- Connection pool exhaustion (> 90% utilized)
- High error rate (> 5% over 1 minute)
- Transport failover events (> 10 per minute)
- Message latency degradation (p99 > 500ms)
- Memory pressure (> 80% heap usage)

## VSM Integration Dependencies

### Integration with VSM (Specific Event Topics)
- **S1 (Operations)**: Gateway publishes all incoming messages to `:s1_operations` topic
  - Event format: `{:external_message, client_id, payload, metadata}`
  - Frequency: Every incoming message
  - Expected processing time: < 50ms
  
- **S2 (Coordination)**: Prevents transport oscillation via `:s2_coordination` checks
  - Call before transport switch: `{:check_oscillation, client_id, from, to}`
  - Anti-oscillation window: 60 seconds
  - Max switches per window: 3
  
- **S3 (Control)**: Resource allocation requests via `:s3_control` calls
  - Connection allocation: `{:allocate_connections, transport, count}`
  - Rate limit adjustment: `{:adjust_rate_limit, client_id, new_limit}`
  - Circuit breaker override: `{:force_circuit_state, transport, state}`
  
- **S4 (Intelligence)**: Metrics published every 10s to `:s4_intelligence` topic
  - Aggregate metrics: `{:gateway_metrics, stats_map}`
  - Pattern detection: `{:usage_pattern, client_id, pattern_type}`
  - Anomaly reports: `{:anomaly_detected, details}`
  
- **S5 (Policy)**: Connection limits enforced via `:s5_policy` subscriptions
  - Policy updates: `{:policy_update, :gateway, constraints}`
  - Compliance checks: `{:check_compliance, action, context}`
  - Identity alignment: `{:verify_identity, operation}`
  
- **Algedonic Channel**: Critical failures (pool exhaustion, circuit open) trigger pain signals
  - Pain signal: `{:pain, :critical, source, message, context}`
  - Pleasure signal: `{:pleasure, :moderate, source, recovery_metrics}`
  - Bypass threshold: 3 consecutive failures or pool > 95% utilized

## Test Strategy
Unit tests for transport protocols, load tests with concurrent connections, integration tests with rate limiter and metrics, connection pool behavior verification

## Dependencies
Task dependencies: 2, 3, 6

## Implementation Status
This file tracks the implementation of Task 8.

@claude Please implement this task according to the specifications above.
