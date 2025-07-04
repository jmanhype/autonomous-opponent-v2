# MCP Gateway Dashboard - Local Access Guide

## Overview

The MCP Gateway Dashboard is a Phoenix LiveView real-time monitoring interface for the MCP Gateway transport layer. It displays connection counts, message throughput, circuit breaker status, VSM integration metrics, and more.

## Accessing the Dashboard Locally

### 1. Start the Phoenix Server

```bash
# Install dependencies if not already done
mix deps.get
cd apps/autonomous_opponent_web/assets && npm install && cd -

# Start the server with IEx for debugging
iex -S mix phx.server
```

### 2. Access the Dashboard

Open your browser and navigate to:
```
http://localhost:4000/mcp/dashboard
```

### 3. Authentication (Currently Disabled)

**⚠️ Important Security Note**: The dashboard currently has NO authentication. In production, you should add authentication.

To add authentication, modify the router:

```elixir
# In apps/autonomous_opponent_web/lib/autonomous_opponent_web/router.ex

# Add an authenticated pipeline
pipeline :authenticated do
  plug :ensure_authenticated_user
end

# Update the dashboard route
scope "/", AutonomousOpponentV2Web do
  pipe_through [:browser, :authenticated]  # Add authentication
  
  live "/mcp/dashboard", MCPDashboardLive, :index
end
```

## Dashboard Features

### Real-Time Metrics Display

The dashboard updates every second (1000ms) and shows:

1. **Active Connections**
   - WebSocket connection count
   - HTTP/SSE connection count
   - Total connections

2. **Message Throughput**
   - Current messages per second
   - 60-second history graph

3. **Circuit Breakers**
   - WebSocket transport state (OPEN/HALF_OPEN/CLOSED)
   - HTTP/SSE transport state

4. **Connection Pool**
   - Available connections
   - In-use connections
   - Overflow connections
   - Visual usage bar

5. **VSM Integration**
   - S1 Variety Absorption rate
   - S2 Coordination status
   - S3 Resource usage percentage
   - S4 Intelligence events count
   - S5 Policy violations count

6. **Error Rates**
   - WebSocket error percentage
   - HTTP/SSE error percentage

7. **Algedonic Signals**
   - Critical alerts from VSM
   - Displayed when present

## Testing the Dashboard

### Run the Test Script

```bash
# From the project root
mix run test_dashboard.exs
```

This will verify:
- Dashboard route configuration
- Data source functions
- PubSub broadcasting
- Metric updates
- Error handling

### Manual Testing

1. **Generate Traffic**
   ```elixir
   # In IEx console
   # Simulate WebSocket connections
   for i <- 1..10 do
     Registry.register(AutonomousOpponentV2Core.MCP.TransportRegistry, 
                      {:transport, :websocket}, 
                      "client_#{i}")
   end
   
   # Simulate SSE connections
   for i <- 1..5 do
     Registry.register(AutonomousOpponentV2Core.MCP.TransportRegistry, 
                      {:transport, :http_sse}, 
                      "sse_client_#{i}")
   end
   ```

2. **Trigger Circuit Breaker States**
   ```elixir
   # Open a circuit breaker
   AutonomousOpponentV2Core.Core.CircuitBreaker.force_open(:websocket_transport)
   
   # Close a circuit breaker
   AutonomousOpponentV2Core.Core.CircuitBreaker.force_close(:websocket_transport)
   ```

3. **Send Test Metrics**
   ```elixir
   # Broadcast test metrics
   test_metrics = %{
     connections: %{websocket: 15, http_sse: 8, total: 23},
     throughput: 120,
     circuit_breakers: %{websocket: :open, http_sse: :half_open},
     vsm_metrics: %{
       s1_variety_absorption: 85,
       s2_coordination_active: true,
       s3_resource_usage: 72,
       s4_intelligence_events: 42,
       s5_policy_violations: 3,
       algedonic_signals: [
         %{
           severity: :high,
           message: "Connection pool nearing capacity",
           timestamp: DateTime.utc_now()
         }
       ]
     },
     error_rates: %{websocket: 2.5, http_sse: 0.8},
     pool_status: %{available: 20, in_use: 80, overflow: 10}
   }
   
   Phoenix.PubSub.broadcast(
     AutonomousOpponentV2.PubSub,
     "mcp:metrics",
     {:mcp_metrics_update, test_metrics}
   )
   ```

## Troubleshooting

### Dashboard Not Loading

1. **Check if Phoenix is running**
   ```bash
   curl http://localhost:4000/health
   ```

2. **Verify route exists**
   ```elixir
   # In IEx
   AutonomousOpponentV2Web.Router.__routes__()
   |> Enum.find(& &1.path == "/mcp/dashboard")
   ```

3. **Check for JavaScript errors**
   - Open browser console (F12)
   - Look for LiveView connection errors

### No Data Displayed

1. **Verify Gateway is started**
   ```elixir
   # In IEx
   Process.whereis(AutonomousOpponentV2Core.MCP.Gateway)
   ```

2. **Check if metrics are being generated**
   ```elixir
   AutonomousOpponentV2Core.MCP.Gateway.get_dashboard_metrics()
   ```

3. **Test PubSub**
   ```elixir
   # Subscribe
   Phoenix.PubSub.subscribe(AutonomousOpponentV2.PubSub, "mcp:metrics")
   
   # Should receive messages when metrics update
   flush()
   ```

### Circuit Breakers Not Initialized

If circuit breakers show as CLOSED even when they should be OPEN:

```elixir
# Initialize circuit breakers manually
AutonomousOpponentV2Core.Core.CircuitBreaker.init(:websocket_transport)
AutonomousOpponentV2Core.Core.CircuitBreaker.init(:http_sse_transport)
```

## Performance Considerations

- The dashboard refreshes every 1 second
- Keeps 60 seconds of throughput history
- Minimal performance impact on the gateway
- PubSub is used for efficient updates

## Security Recommendations

1. **Add Authentication** (see above)
2. **Use HTTPS in production**
3. **Consider rate limiting dashboard access**
4. **Add CORS headers if needed**
5. **Log dashboard access for auditing**

## Customization

To modify refresh interval:
```elixir
# In mcp_dashboard_live.ex
@refresh_interval 5000  # Change to 5 seconds
```

To add new metrics:
1. Update `Gateway.get_dashboard_metrics/0`
2. Add to dashboard assigns in `mount/3`
3. Update the template in `render/1`

## Integration with Monitoring Tools

The dashboard can be integrated with:
- Prometheus (via `/metrics` endpoint)
- Grafana (create dashboard from metrics)
- DataDog (use statsd reporter)
- New Relic (via OpenTelemetry)