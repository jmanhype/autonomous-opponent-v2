# MCP Gateway Production Features

This document describes the production-ready features added to the MCP Gateway to ensure observability, reliability, and security.

## Table of Contents

1. [LiveView Monitoring Dashboard](#liveview-monitoring-dashboard)
2. [Connection Draining](#connection-draining)
3. [OpenTelemetry Distributed Tracing](#opentelemetry-distributed-tracing)
4. [JWT Authentication](#jwt-authentication)

## LiveView Monitoring Dashboard

### Overview

A real-time monitoring dashboard built with Phoenix LiveView provides instant visibility into gateway operations.

### Features

- **Connection Metrics**: Real-time counts by transport type (WebSocket/SSE)
- **Throughput Graphs**: Message per second visualization with 60-second history
- **Circuit Breaker Status**: Visual indicators for each transport's health
- **Connection Pool Status**: Available, in-use, and overflow connections
- **VSM Integration Metrics**: 
  - S1 variety absorption rate
  - S2 coordination status
  - S3 resource usage
  - S4 intelligence events
  - S5 policy violations
- **Error Rates**: Per-transport error percentages
- **Algedonic Signals**: Critical system alerts display

### Usage

Access the dashboard at: `http://localhost:4000/mcp/dashboard`

```elixir
# Dashboard automatically updates every second
# No configuration required - metrics are collected automatically
```

### Customization

```elixir
# Adjust refresh interval in MCPDashboardLive
@refresh_interval 1000  # milliseconds

# Modify history window
@history_size 60  # seconds of throughput history
```

## Connection Draining

### Overview

Graceful shutdown mechanism for zero-downtime deployments.

### Features

- **Client Notifications**: Warns connected clients of impending shutdown
- **Connection Rejection**: Stops accepting new connections
- **Configurable Timeout**: Waits for existing connections to close
- **Forced Shutdown**: Option to immediately close all connections
- **VSM Integration**: Reports draining status to S3 Control

### Usage

```elixir
# Start graceful shutdown (30s default timeout)
Gateway.graceful_shutdown()

# Custom timeout (60 seconds)
Gateway.graceful_shutdown(timeout: 60_000)

# With completion callback
Gateway.graceful_shutdown(
  timeout: 45_000,
  callback: fn reason ->
    Logger.info("Shutdown completed: #{reason}")
  end
)

# Force immediate shutdown
Gateway.force_shutdown()
```

### Client Notifications

Connected clients receive shutdown notifications via their transport:

```javascript
// WebSocket clients
socket.onMessage((event) => {
  if (event.type === "shutdown_pending") {
    console.log("Server shutting down, reconnect after:", event.reconnect_after);
    // Prepare for reconnection
  }
});

// SSE clients
eventSource.addEventListener("shutdown_pending", (event) => {
  const data = JSON.parse(event.data);
  console.log("Server shutting down:", data.message);
});
```

### Configuration

```elixir
# In your deployment script
defmodule Deployment do
  def rolling_update do
    # Signal old instance to drain
    Gateway.graceful_shutdown(timeout: 60_000)
    
    # Wait for drain to complete
    wait_for_drain_completion()
    
    # Deploy new instance
    deploy_new_instance()
  end
end
```

## OpenTelemetry Distributed Tracing

### Overview

Comprehensive distributed tracing using OpenTelemetry standards for debugging and performance monitoring.

### Features

- **Automatic Span Creation**: Traces all major operations
- **Trace Propagation**: W3C Trace Context headers support
- **VSM Integration**: Traces flow through VSM subsystems
- **Performance Metrics**: Operation duration tracking
- **Error Recording**: Automatic exception capture

### Configuration

```elixir
# config/config.exs
config :opentelemetry,
  resource: [
    service: [
      name: "mcp-gateway",
      namespace: "autonomous-opponent"
    ]
  ],
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318"),
  otlp_headers: [{"x-api-key", System.get_env("OTEL_API_KEY", "")}]
```

### Usage

```elixir
# Automatic tracing for routing
# Traces are created automatically when messages are routed

# Manual tracing for custom operations
Tracing.with_span "custom.operation", [kind: :internal] do
  # Your code here
  perform_operation()
end

# Add custom attributes
Tracing.add_attributes(%{
  user_id: "user123",
  operation_type: "bulk_update"
})

# Record events
Tracing.add_event("processing.started", %{
  item_count: 100
})
```

### Trace Propagation

```elixir
# Extract trace from incoming request
trace_context = Tracing.extract_trace_context(conn.req_headers)

# Inject trace into outgoing request
headers = Tracing.inject_trace_context(%{
  "content-type" => "application/json"
})
```

### Integration with APM Tools

The gateway exports traces in OTLP format, compatible with:
- Jaeger
- Zipkin  
- DataDog
- New Relic
- AWS X-Ray
- Google Cloud Trace

## JWT Authentication

### Overview

Secure authentication using JSON Web Tokens with role-based rate limiting.

### Features

- **Token Generation**: Create tokens with custom claims
- **Token Validation**: Verify and extract user information
- **Role-Based Rate Limiting**: Different limits per user tier
- **Channel Authentication**: WebSocket auth support
- **SSE Authentication**: HTTP auth via headers or query params
- **Token Refresh**: Automatic refresh for expiring tokens

### Token Structure

```json
{
  "sub": "user123",           // User ID
  "role": "premium",          // User role
  "permissions": ["read"],    // Granted permissions
  "iss": "autonomous-opponent",
  "aud": "mcp-gateway",
  "exp": 1704067200,         // Expiration timestamp
  "iat": 1704063600          // Issued at timestamp
}
```

### Usage

#### Generating Tokens

```elixir
# Generate basic token (1 hour expiration)
{:ok, token} = JWTAuthenticator.generate_token("user123")

# With custom role and permissions
{:ok, token} = JWTAuthenticator.generate_token("user123", [
  role: "admin",
  permissions: ["read", "write", "admin"],
  exp: 7200  # 2 hours
])
```

#### Client Authentication

**WebSocket Authentication:**
```javascript
const socket = new Socket("/mcp/ws", {
  params: {
    token: "eyJhbGciOiJIUzI1NiIs..."
  }
});

socket.connect();

const channel = socket.channel("mcp:gateway", {});
channel.join()
  .receive("ok", resp => {
    console.log("Joined as:", resp.user_id, resp.role);
  })
  .receive("error", resp => {
    console.log("Auth failed:", resp.reason);
  });
```

**SSE Authentication:**
```javascript
// Via Authorization header
const eventSource = new EventSource("/mcp/sse", {
  headers: {
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIs..."
  }
});

// Via query parameter (for browsers that don't support headers)
const eventSource = new EventSource("/mcp/sse?token=eyJhbGciOiJIUzI1NiIs...");
```

### Rate Limiting by Role

Rate limits are automatically applied based on user role:

| Role    | Requests/Minute | Use Case            |
|---------|-----------------|---------------------|
| admin   | 10,000         | Internal services   |
| premium | 1,000          | Paid users          |
| user    | 100            | Free tier           |
| guest   | 10             | Unauthenticated     |

### Security Configuration

```elixir
# Set JWT secret (required for production)
config :autonomous_opponent_core,
  jwt_secret: System.get_env("JWT_SECRET")

# Or via environment variable
export JWT_SECRET="your-secret-key-at-least-32-characters"
```

### Token Refresh

```elixir
# Refresh token if close to expiration
case JWTAuthenticator.refresh_token(current_token) do
  {:ok, new_token} ->
    # Use new token
  {:ok, ^current_token} ->
    # Token still valid, no refresh needed
  {:error, :invalid_token} ->
    # Token invalid, re-authenticate
end
```

### Permission Checking

```elixir
# In your application logic
if JWTAuthenticator.has_permission?(claims, "write") do
  # Allow write operation
else
  # Deny access
end
```

## Integration Example

Here's how all features work together:

```elixir
defmodule MyApp.MCPClient do
  alias AutonomousOpponentV2Core.MCP.Gateway
  alias AutonomousOpponentV2Core.MCP.Auth.JWTAuthenticator
  alias AutonomousOpponentV2Core.MCP.Tracing
  
  def authenticated_request(user_id, message) do
    # Generate token
    {:ok, token} = JWTAuthenticator.generate_token(user_id, role: "premium")
    
    # Trace the operation
    Tracing.with_span "myapp.authenticated_request", [kind: :client] do
      # Send authenticated message
      Gateway.route_message(user_id, message, [
        auth_token: token,
        trace_context: Tracing.inject_trace_context()
      ])
    end
  end
  
  def monitor_gateway do
    # Check dashboard for real-time metrics
    # http://localhost:4000/mcp/dashboard
    
    # Or programmatically
    {:ok, metrics} = Gateway.get_dashboard_metrics()
    
    if metrics.connections.total > 9000 do
      Logger.warning("High connection count: #{metrics.connections.total}")
    end
  end
  
  def handle_deployment do
    # Graceful shutdown with monitoring
    Gateway.graceful_shutdown(
      timeout: 60_000,
      callback: fn reason ->
        Tracing.add_event("gateway.shutdown", %{reason: reason})
        Logger.info("Gateway shutdown complete: #{reason}")
      end
    )
  end
end
```

## Best Practices

1. **Always use authentication in production** - Even if optional, it enables better rate limiting and tracking
2. **Monitor the dashboard during deployments** - Watch connection draining progress
3. **Export traces to an APM tool** - Don't just log locally
4. **Rotate JWT secrets regularly** - Use environment variables for secrets
5. **Test graceful shutdown** - Ensure your deployment scripts handle it properly
6. **Set appropriate rate limits** - Adjust based on your infrastructure capacity

## Troubleshooting

### Dashboard Not Updating
- Check WebSocket connection to LiveView
- Verify `Gateway.get_dashboard_metrics()` returns data
- Check browser console for errors

### Traces Not Appearing
- Verify OTLP endpoint is reachable
- Check OpenTelemetry configuration
- Ensure span processor is running: `:otel_batch_processor.which_exporters()`

### Authentication Failures
- Verify JWT secret is set correctly
- Check token expiration
- Validate token format (3 base64 parts separated by dots)
- Check rate limit hasn't been exceeded

### Connection Draining Issues
- Monitor algedonic signals for pain events
- Check drain timeout is sufficient
- Verify clients handle shutdown notifications
- Use force_shutdown as last resort