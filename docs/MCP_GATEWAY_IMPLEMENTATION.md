# MCP Gateway Transport Implementation

## Overview

The MCP Gateway Transport has been implemented to provide HTTP+SSE and WebSocket transport layers for the Autonomous Opponent system, with proper routing, connection pooling, and integration with the VSM architecture.

## Architecture

### Core Components

1. **MCPGateway.Supervisor**
   - Manages all MCP Gateway components
   - Uses rest-for-one strategy for dependent component restart
   - Isolates gateway failures from VSM core

2. **MCPGateway.ConnectionPool**
   - Manages connection pools for different transport types
   - Configurable pool sizes with overflow support
   - Health checking and automatic reconnection
   - Backpressure management when pool is exhausted

3. **MCPGateway.Router**
   - Implements consistent hashing for load balancing
   - Supports wildcard pattern matching
   - Circuit breaker per route for fault tolerance
   - Dynamic backend updates with minimal reshuffling

4. **MCPGateway.HealthMonitor**
   - Monitors all gateway components
   - Configurable health check intervals
   - Automatic alert triggering
   - Integration with metrics system

5. **MCPGateway.TransportRegistry**
   - Strategy pattern for transport selection
   - Dynamic transport registration
   - Transport handler validation

### Transport Implementations

1. **HTTP+SSE Transport**
   - Long-lived HTTP connections with Server-Sent Events
   - Automatic reconnection handling
   - Event buffering with backpressure
   - Heartbeat events for connection keepalive

2. **WebSocket Transport**
   - Full-duplex bidirectional communication
   - Binary and text frame support
   - Ping/pong for connection health
   - Request/response pattern support

### Phoenix Integration

1. **SSE Controller** (`MCPSSEController`)
   - Handles `/mcp/sse/connect` and `/mcp/sse/events/:topic` endpoints
   - Proper SSE headers and chunked responses
   - Integration with MCP Gateway router

2. **WebSocket** (`MCPSocket` and `MCPChannel`)
   - Phoenix Socket at `/mcp` endpoint
   - Channel-based communication
   - Event forwarding to/from EventBus

## VSM Integration

The MCP Gateway integrates with VSM principles:

1. **Variety Management**: Rate limiting controls variety flow into the system
2. **Algedonic Signals**: Connection failures and backpressure trigger pain signals
3. **Metrics Collection**: All operations are measured and reported
4. **Event-Driven**: Full integration with EventBus for loose coupling

## Usage Examples

### HTTP+SSE Connection

```javascript
// Client-side JavaScript
const eventSource = new EventSource('/mcp/sse/events/all');

eventSource.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Received:', data);
};

eventSource.addEventListener('vsm_event', (event) => {
  const vsmData = JSON.parse(event.data);
  console.log('VSM Event:', vsmData);
});
```

### WebSocket Connection

```javascript
// Client-side JavaScript
import { Socket } from "phoenix";

const socket = new Socket("/mcp", {
  params: { user_id: "user123" }
});

socket.connect();

const channel = socket.channel("mcp:events", {});

channel.join()
  .receive("ok", resp => console.log("Joined successfully", resp))
  .receive("error", resp => console.log("Unable to join", resp));

channel.on("event", payload => {
  console.log("Event received:", payload);
});

// Send request
channel.push("request", {
  method: "echo",
  params: { message: "Hello" },
  id: "req-123"
});
```

## Configuration

Add to your config files:

```elixir
# MCP Gateway configuration
config :autonomous_opponent_core, :mcp_gateway,
  pool_size: 50,
  max_overflow: 10,
  hash_ring_size: 1024,
  health_check_interval: 5_000,
  transports: [
    http_sse: [
      max_connections: 1000,
      heartbeat_interval: 30_000,
      buffer_size: 100
    ],
    websocket: [
      max_connections: 1000,
      ping_interval: 30_000,
      pong_timeout: 10_000
    ]
  ]
```

## Monitoring

The MCP Gateway provides comprehensive metrics:

- Connection pool statistics
- Router performance metrics
- Transport-specific metrics
- Health status for all components

Access metrics via:
- Prometheus endpoint: `/metrics`
- Health check: `/health`
- VSM dashboard: `/metrics/dashboard`

## Security Considerations

1. **Rate Limiting**: Prevents DoS attacks
2. **Connection Limits**: Prevents resource exhaustion
3. **Circuit Breakers**: Isolate failing backends
4. **Input Validation**: All messages are validated

## Future Enhancements

1. **Authentication**: Add JWT/OAuth support
2. **Encryption**: TLS for WebSocket connections
3. **Compression**: Per-message deflate for bandwidth optimization
4. **Clustering**: Distributed gateway across nodes
5. **gRPC Transport**: Add gRPC support for high-performance RPC