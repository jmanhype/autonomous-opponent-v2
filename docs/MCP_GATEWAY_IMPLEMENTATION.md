# MCP Gateway Transport Implementation

## Overview

The MCP (Model Context Protocol) Gateway has been fully implemented as part of Task 8, providing HTTP+SSE and WebSocket transport layers with intelligent routing, connection pooling, and complete VSM integration.

## Architecture

```
apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/mcp/
├── gateway.ex              # Main supervisor
├── transport/
│   ├── http_sse.ex        # Server-Sent Events implementation
│   ├── websocket.ex       # WebSocket implementation
│   └── router.ex          # Intelligent routing with failover
├── pool/
│   └── connection_pool.ex # Poolboy-based connection pooling
└── load_balancer/
    └── consistent_hash.ex # Consistent hashing for load distribution
```

## Key Features

### 1. Dual Transport Support

#### HTTP+SSE Transport
- Phoenix controller at `/mcp/sse`
- Automatic heartbeat every 30 seconds
- One-way server-to-client communication
- Graceful connection management
- Event-based message delivery

#### WebSocket Transport
- Phoenix Channel at `/mcp/ws`
- Bidirectional communication
- Binary and text frame support
- Compression for messages > 1KB
- Ping/pong keepalive mechanism

### 2. Intelligent Routing

The transport router provides:
- Automatic transport selection based on message size
- Client preference support
- Circuit breaker integration
- Automatic failover between transports
- Session affinity maintenance

### 3. Connection Pooling

Powered by Poolboy with:
- Configurable pool size (default: 100)
- Overflow support (default: 50)
- Connection lifecycle management
- Health monitoring and metrics
- Automatic cleanup of idle connections

### 4. Load Balancing

Consistent hash implementation featuring:
- 150 virtual nodes per physical node
- Weighted node distribution
- Minimal key redistribution on node changes
- Replication support for high availability

### 5. VSM Integration

Full integration with the Viable System Model:
- Metrics reporting to S4 (Intelligence)
- Algedonic signal triggers for critical failures
- EventBus integration for variety flow
- Circuit breaker coordination
- Rate limiting per connection

## Configuration

```elixir
config :autonomous_opponent_core, :mcp_gateway,
  transports: [
    http_sse: [
      port: 4001,
      max_connections: 10_000,
      heartbeat_interval: 30_000
    ],
    websocket: [
      port: 4002,
      compression: true,
      max_frame_size: 65_536,
      ping_interval: 30_000,
      pong_timeout: 10_000
    ]
  ],
  pool: [
    size: 100,
    overflow: 50,
    strategy: :fifo,
    checkout_timeout: 5_000,
    idle_timeout: 300_000
  ],
  routing: [
    algorithm: :consistent_hash,
    vnodes: 150,
    failover_threshold: 3,
    health_check_interval: 10_000
  ],
  rate_limiting: [
    default_limit: 100,
    refill_rate: 100
  ]
```

## VSM Integration Details

### S1 (Operations) Integration
```elixir
# Example: How gateway messages flow to S1
defmodule Gateway.VSMIntegration do
  def process_message(message) do
    # Publish to S1 for variety absorption
    EventBus.publish(:s1_operations, %{
      source: :mcp_gateway,
      variety_type: :external_input,
      payload: message,
      timestamp: DateTime.utc_now()
    })
  end
end
```

### S4 (Intelligence) Metrics Reporting
```elixir
# Gateway automatically reports these metrics to S4:
%{
  metric_type: :gateway_performance,
  timestamp: DateTime.utc_now(),
  data: %{
    active_connections: 1523,
    message_rate: 8500,  # msgs/sec
    latency_p99: 87,     # ms
    transport_distribution: %{
      websocket: 1200,
      http_sse: 323
    },
    error_rate: 0.02,    # 2% error rate
    pool_utilization: 0.75
  }
}
```

### Algedonic Signal Examples
```elixir
# Critical failure triggers pain signal
if pool_exhausted? do
  EventBus.publish(:algedonic_channel, %{
    signal_type: :pain,
    severity: :critical,
    source: :mcp_gateway,
    message: "Connection pool exhausted",
    suggested_action: :increase_pool_size,
    current_capacity: 100,
    overflow_used: 50
  })
end

# Success signal for recovery
if recovered_from_failure? do
  EventBus.publish(:algedonic_channel, %{
    signal_type: :pleasure,
    severity: :moderate,
    source: :mcp_gateway,
    message: "Gateway recovered from transport failure",
    recovery_time_ms: 850
  })
end
```

### S2 (Coordination) Anti-Oscillation
```elixir
# Prevent transport switching oscillation
defmodule Gateway.AntiOscillation do
  def should_switch_transport?(client_id, from_transport, to_transport) do
    # Check S2 coordination to prevent rapid switching
    EventBus.call(:s2_coordination, %{
      request: :check_oscillation,
      client: client_id,
      from: from_transport,
      to: to_transport,
      switch_history: get_switch_history(client_id)
    })
  end
end
```

### S3 (Control) Resource Management
```elixir
# S3 controls gateway resource allocation
defmodule Gateway.ResourceControl do
  def request_resources(transport, count) do
    EventBus.call(:s3_control, %{
      request: :allocate_connections,
      transport: transport,
      requested: count,
      current_usage: get_current_usage(),
      priority: :normal
    })
  end
end
```

## Usage Examples

### Connecting via SSE

```javascript
const eventSource = new EventSource('/mcp/sse?client_id=user123');

eventSource.addEventListener('connected', (event) => {
  console.log('Connected:', JSON.parse(event.data));
});

eventSource.addEventListener('message', (event) => {
  console.log('Message:', JSON.parse(event.data));
});

eventSource.addEventListener('vsm_update', (event) => {
  console.log('VSM Update:', JSON.parse(event.data));
});
```

### Connecting via WebSocket

```javascript
import {Socket} from "phoenix"

const socket = new Socket("/mcp/ws", {
  params: {client_id: "user123", compression: true}
});

socket.connect();

const channel = socket.channel("mcp:gateway", {});

channel.join()
  .receive("ok", resp => console.log("Joined successfully", resp))
  .receive("error", resp => console.log("Unable to join", resp));

channel.on("message", payload => {
  console.log("Received:", payload);
});

channel.push("message", {type: "request", data: {value: 42}});
```

### Python Client Example
```python
import asyncio
import aiohttp
from aiohttp_sse_client import client as sse_client

# SSE Connection Example
async def connect_sse():
    async with sse_client.EventSource(
        'http://localhost:4001/mcp/sse?client_id=python_client'
    ) as event_source:
        try:
            async for event in event_source:
                if event.type == 'connected':
                    print(f"Connected: {event.data}")
                elif event.type == 'message':
                    print(f"Message received: {event.data}")
                elif event.type == 'vsm_update':
                    print(f"VSM Update: {event.data}")
                elif event.type == 'heartbeat':
                    # Handle keepalive
                    pass
        except Exception as e:
            print(f"SSE Error: {e}")

# WebSocket Connection Example
async def connect_websocket():
    session = aiohttp.ClientSession()
    try:
        async with session.ws_connect(
            'ws://localhost:4002/mcp/ws',
            heartbeat=30,
            compress=True
        ) as ws:
            # Join the gateway channel
            await ws.send_json({
                "topic": "mcp:gateway",
                "event": "phx_join",
                "payload": {"client_id": "python_client"},
                "ref": "1"
            })
            
            # Listen for messages
            async for msg in ws:
                if msg.type == aiohttp.WSMsgType.TEXT:
                    data = msg.json()
                    if data.get('event') == 'phx_reply' and data.get('payload', {}).get('status') == 'ok':
                        print("Successfully joined channel")
                    elif data.get('event') == 'message':
                        print(f"Received: {data['payload']}")
                elif msg.type == aiohttp.WSMsgType.ERROR:
                    print(f"WebSocket error: {ws.exception()}")
                    break
    finally:
        await session.close()

# Send a message via WebSocket
async def send_message(ws, message_type, data):
    await ws.send_json({
        "topic": "mcp:gateway",
        "event": "message",
        "payload": {
            "type": message_type,
            "data": data
        },
        "ref": str(uuid.uuid4())
    })

# Main entry point
if __name__ == "__main__":
    # Choose transport based on use case
    asyncio.run(connect_sse())  # For server-push only
    # asyncio.run(connect_websocket())  # For bidirectional
```

### Elixir Client Example
```elixir
# Using the gateway from another Elixir service
defmodule MyApp.GatewayClient do
  alias AutonomousOpponentCore.MCP.Transport.Router
  require Logger
  
  # Direct routing through the gateway
  def send_message(client_id, message) do
    Router.route_message(client_id, message, 
      transport: :auto,        # :auto, :websocket, :http_sse
      priority: :normal,       # :low, :normal, :high
      timeout: 5_000
    )
  end
  
  # Subscribe to gateway events for a specific client
  def subscribe_to_events(client_id) do
    EventBus.subscribe({:mcp_client, client_id})
  end
  
  # Handle incoming events
  def handle_gateway_event({:mcp_client, client_id}, event) do
    case event do
      {:message, payload} ->
        Logger.info("Received message for #{client_id}: #{inspect(payload)}")
      
      {:connection_status, status} ->
        Logger.info("Connection status for #{client_id}: #{status}")
      
      {:transport_switched, from, to} ->
        Logger.info("Transport switched from #{from} to #{to}")
      
      _ ->
        Logger.debug("Unknown event: #{inspect(event)}")
    end
  end
  
  # Example GenServer client
  defmodule ConnectionManager do
    use GenServer
    
    def start_link(client_id) do
      GenServer.start_link(__MODULE__, client_id, name: via_tuple(client_id))
    end
    
    def init(client_id) do
      # Subscribe to gateway events
      EventBus.subscribe({:mcp_client, client_id})
      
      # Establish initial connection
      Router.connect(client_id, transport: :websocket)
      
      {:ok, %{client_id: client_id, connected: false}}
    end
    
    def handle_info({:mcp_client, _client_id} = topic, event, state) do
      MyApp.GatewayClient.handle_gateway_event(topic, event)
      {:noreply, state}
    end
    
    defp via_tuple(client_id) do
      {:via, Registry, {MyApp.Registry, {__MODULE__, client_id}}}
    end
  end
end

# Example: Batch operations
defmodule MyApp.BatchClient do
  alias AutonomousOpponentCore.MCP.Pool.ConnectionPool
  
  def send_batch(messages) do
    # Check out multiple connections from pool
    connections = ConnectionPool.checkout_batch(length(messages))
    
    try do
      # Send messages in parallel
      Task.async_stream(
        Enum.zip(connections, messages),
        fn {conn, msg} -> 
          ConnectionPool.send_message(conn, msg)
        end,
        max_concurrency: 10,
        timeout: 5_000
      )
      |> Enum.to_list()
    after
      # Return connections to pool
      Enum.each(connections, &ConnectionPool.checkin/1)
    end
  end
end
```

### Ruby Client Example
```ruby
require 'faye/websocket'
require 'eventmachine'
require 'json'

# WebSocket client for Ruby
class MCPGatewayClient
  attr_reader :client_id, :ws
  
  def initialize(client_id)
    @client_id = client_id
    @callbacks = {}
  end
  
  def connect
    EM.run do
      @ws = Faye::WebSocket::Client.new('ws://localhost:4002/mcp/ws')
      
      @ws.on :open do |event|
        # Join the gateway channel
        @ws.send({
          topic: "mcp:gateway",
          event: "phx_join",
          payload: { client_id: @client_id },
          ref: "1"
        }.to_json)
      end
      
      @ws.on :message do |event|
        data = JSON.parse(event.data)
        handle_message(data)
      end
      
      @ws.on :close do |event|
        puts "Connection closed: #{event.code} #{event.reason}"
        EM.stop
      end
    end
  end
  
  def send_message(type, data)
    @ws.send({
      topic: "mcp:gateway",
      event: "message",
      payload: { type: type, data: data },
      ref: SecureRandom.uuid
    }.to_json)
  end
  
  def on(event, &block)
    @callbacks[event] = block
  end
  
  private
  
  def handle_message(data)
    case data['event']
    when 'phx_reply'
      if data['payload']['status'] == 'ok'
        @callbacks[:connected]&.call if data['ref'] == '1'
      end
    when 'message'
      @callbacks[:message]&.call(data['payload'])
    when 'vsm_update'
      @callbacks[:vsm_update]&.call(data['payload'])
    end
  end
end

# Usage
client = MCPGatewayClient.new('ruby_client')
client.on(:connected) { puts "Connected to gateway!" }
client.on(:message) { |msg| puts "Received: #{msg}" }
client.connect
```

## Testing

Comprehensive test coverage includes:

1. **Unit Tests**: Each component tested in isolation
2. **Integration Tests**: End-to-end scenarios with VSM
3. **Load Tests**: Concurrent connection handling (1000+)
4. **Failure Tests**: Automatic failover and recovery

Run tests with:
```bash
mix test test/autonomous_opponent_v2_core/mcp/
```

## Performance Characteristics

- **Latency**: < 100ms at p99
- **Throughput**: 10,000+ concurrent connections
- **Message Rate**: 100 msg/sec per connection (rate limited)
- **Failover Time**: < 1 second
- **Memory Usage**: ~1KB per idle connection

## Monitoring

The gateway reports comprehensive metrics:
- Active connections per transport
- Message throughput and latency
- Error rates and circuit breaker status
- Pool utilization and health
- VSM variety flow metrics

Access metrics via:
- Prometheus endpoint: `/metrics`
- Live dashboard: `/metrics/dashboard`
- VSM S4 intelligence reports

## Deployment Considerations

### Container Deployment

#### Docker Compose Configuration
```yaml
# docker-compose.yml addition
mcp_gateway:
  image: autonomous-opponent:latest
  environment:
    - MCP_POOL_SIZE=200
    - MCP_OVERFLOW=100
    - MCP_SSE_PORT=4001
    - MCP_WS_PORT=4002
    - MCP_SSE_MAX_CONNECTIONS=10000
    - MCP_WS_MAX_FRAME_SIZE=65536
    - MCP_RATE_LIMIT=100
  ports:
    - "4001:4001"  # SSE
    - "4002:4002"  # WebSocket
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:4000/health/gateway"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s
  deploy:
    resources:
      limits:
        cpus: '2.0'
        memory: 4G
      reservations:
        cpus: '1.0'
        memory: 2G
```

### Kubernetes Configuration

#### Service Definition
```yaml
apiVersion: v1
kind: Service
metadata:
  name: mcp-gateway
  labels:
    app: autonomous-opponent
    component: gateway
spec:
  type: ClusterIP
  ports:
  - name: sse
    port: 4001
    targetPort: 4001
    protocol: TCP
  - name: websocket
    port: 4002
    targetPort: 4002
    protocol: TCP
  selector:
    app: autonomous-opponent
    component: gateway
```

#### Deployment with Horizontal Pod Autoscaling
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-gateway
spec:
  replicas: 3
  selector:
    matchLabels:
      app: autonomous-opponent
      component: gateway
  template:
    metadata:
      labels:
        app: autonomous-opponent
        component: gateway
    spec:
      containers:
      - name: gateway
        image: autonomous-opponent:latest
        env:
        - name: MCP_POOL_SIZE
          value: "200"
        - name: MCP_OVERFLOW
          value: "100"
        ports:
        - containerPort: 4001
          name: sse
        - containerPort: 4002
          name: websocket
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 4000
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: mcp-gateway-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: mcp-gateway
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Load Balancer Configuration

#### NGINX Ingress for WebSocket/SSE
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mcp-gateway-ingress
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/upstream-keepalive-connections: "10000"
    nginx.ingress.kubernetes.io/upstream-keepalive-timeout: "60"
spec:
  rules:
  - host: gateway.example.com
    http:
      paths:
      - path: /mcp/sse
        pathType: Prefix
        backend:
          service:
            name: mcp-gateway
            port:
              number: 4001
      - path: /mcp/ws
        pathType: Prefix
        backend:
          service:
            name: mcp-gateway
            port:
              number: 4002
```

### Production Environment Variables
```bash
# Required environment variables for production
export DATABASE_URL="postgres://user:pass@db-cluster:5432/autonomous_opponent_prod"
export SECRET_KEY_BASE="your-64-char-production-secret"
export PHX_HOST="gateway.example.com"
export PHX_SERVER=true
export MIX_ENV=prod

# MCP Gateway specific
export MCP_POOL_SIZE=500
export MCP_OVERFLOW=200
export MCP_SSE_MAX_CONNECTIONS=50000
export MCP_WS_MAX_CONNECTIONS=50000
export MCP_RATE_LIMIT_PER_CLIENT=1000
export MCP_CIRCUIT_BREAKER_THRESHOLD=0.5
export MCP_CIRCUIT_BREAKER_TIMEOUT=30000

# Monitoring
export PROMETHEUS_ENABLED=true
export GRAFANA_ENABLED=true
export OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector:4317"
```

### Scaling Strategies

#### Vertical Scaling
- Increase pool size for more concurrent connections
- Adjust memory allocation for connection state
- Tune BEAM VM flags: `+P 5000000 +Q 1000000`

#### Horizontal Scaling
- Deploy multiple gateway instances
- Use sticky sessions for WebSocket connections
- Implement Redis-based session storage
- Consider geographic distribution

### Security Hardening
```elixir
# config/prod.exs
config :autonomous_opponent_web, AutonomousOpponentWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  http: [
    port: 4000,
    transport_options: [
      socket_opts: [:inet6],
      num_acceptors: 100
    ]
  ]

# Enable CORS for gateway endpoints
config :cors_plug,
  origin: ["https://app.example.com"],
  max_age: 86400,
  methods: ["GET", "POST"],
  headers: ["Authorization", "Content-Type", "X-Client-ID"]
```

## Error Handling

Robust error handling includes:
- Exponential backoff for reconnections
- Circuit breakers per transport
- Rate limiting with token bucket
- Graceful degradation
- Algedonic signals for critical failures

## Future Enhancements

Potential improvements identified:
1. WebRTC transport for P2P communication
2. gRPC transport for high-performance RPC
3. Message queue integration (Kafka/Pulsar)
4. Geographic load balancing
5. Enhanced security with mTLS

## Troubleshooting

Common issues and solutions:

### Connection Pool Exhaustion
- **Symptom**: `{:error, :pool_timeout}`
- **Solution**: Increase pool size or reduce connection lifetime

### Transport Failover Loop
- **Symptom**: Repeated failover events
- **Solution**: Check transport health, increase failover threshold

### High Memory Usage
- **Symptom**: Growing memory consumption
- **Solution**: Reduce idle timeout, check for connection leaks

### Rate Limiting
- **Symptom**: `rate_limit_exceeded` errors
- **Solution**: Adjust rate limits or implement client-side throttling

## Enhanced Error Handling

### WebSocket Connection Errors

#### Connection Drops (Code 1006)
**Symptoms:**
- Client receives CloseEvent with code 1006
- No close frame received from server
- Often caused by proxy/firewall timeouts

**Diagnosis:**
```elixir
# Check in IEx for specific client
iex> Gateway.get_client_errors("user123", :websocket)
[
  %{
    timestamp: ~U[2024-01-15 10:23:45Z],
    error: :idle_timeout,
    transport: :websocket,
    details: %{
      last_ping: ~U[2024-01-15 10:20:45Z],
      connection_age: 7200
    }
  }
]
```

**Solutions:**
1. **Client-side fix:**
```javascript
// Implement aggressive heartbeat
const socket = new Socket("/mcp/ws", {
  heartbeatIntervalMs: 25000,  // More frequent than server timeout
  params: {client_id: clientId}
})

// Add application-level keepalive
setInterval(() => {
  if (channel.state === "joined") {
    channel.push("ping", {})
  }
}, 20000)
```

2. **Server-side configuration:**
```elixir
# config/prod.exs
config :autonomous_opponent_core, :mcp_gateway,
  websocket: [
    idle_timeout: 60_000,      # Increase from default 30s
    ping_interval: 25_000,     # More frequent pings
    pong_timeout: 15_000       # Allow more time for pong
  ]
```

#### Authentication Failures
**Error Response:**
```json
{
  "error": "authentication_failed",
  "reason": "invalid_token",
  "retry_after": null
}
```

**Handling:**
```javascript
channel.join()
  .receive("error", ({error, reason}) => {
    if (error === "authentication_failed") {
      if (reason === "token_expired") {
        // Refresh token and retry
        refreshToken().then(newToken => {
          socket.params.token = newToken
          socket.disconnect(() => socket.connect())
        })
      } else {
        // Redirect to login
        window.location.href = "/login"
      }
    }
  })
```

### SSE Connection Issues

#### Automatic Reconnection Failures
**Problem:** SSE doesn't reconnect after network interruption

**Solution:**
```javascript
class RobustEventSource {
  constructor(url, options = {}) {
    this.url = url
    this.options = options
    this.reconnectDelay = 1000
    this.maxReconnectDelay = 30000
    this.reconnectDecay = 1.5
    this.reconnectAttempts = 0
    this.shouldReconnect = true
    
    this.connect()
  }
  
  connect() {
    this.eventSource = new EventSource(this.url)
    
    this.eventSource.onopen = () => {
      console.log('SSE connected')
      this.reconnectDelay = 1000
      this.reconnectAttempts = 0
      this.options.onOpen?.()
    }
    
    this.eventSource.onerror = (error) => {
      console.error('SSE error:', error)
      this.eventSource.close()
      
      if (this.shouldReconnect) {
        const delay = Math.min(
          this.reconnectDelay * Math.pow(this.reconnectDecay, this.reconnectAttempts),
          this.maxReconnectDelay
        )
        
        console.log(`Reconnecting in ${delay}ms...`)
        setTimeout(() => this.connect(), delay)
        this.reconnectAttempts++
      }
      
      this.options.onError?.(error)
    }
    
    // Re-attach all event listeners
    Object.entries(this.options.events || {}).forEach(([event, handler]) => {
      this.eventSource.addEventListener(event, handler)
    })
  }
  
  close() {
    this.shouldReconnect = false
    this.eventSource?.close()
  }
}

// Usage
const sse = new RobustEventSource('/mcp/sse?client_id=user123', {
  events: {
    message: (e) => console.log('Message:', e.data),
    heartbeat: (e) => console.log('Heartbeat:', e.data)
  },
  onOpen: () => console.log('Connected!'),
  onError: (e) => console.error('Error:', e)
})
```

### Message Ordering Issues

**Problem:** Messages arrive out of order during transport switches

**Server-side Solution:**
```elixir
defmodule Gateway.MessageSequencer do
  @moduledoc """
  Ensures message ordering during transport switches
  """
  
  def sequence_message(client_id, message) do
    sequence_number = get_next_sequence(client_id)
    
    %{
      sequence: sequence_number,
      timestamp: System.monotonic_time(:microsecond),
      payload: message
    }
  end
  
  def buffer_out_of_order(client_id, message) do
    buffer = get_buffer(client_id)
    expected = get_expected_sequence(client_id)
    
    if message.sequence == expected do
      # Process this message and any buffered ones
      process_sequential_messages(client_id, [message | buffer])
    else
      # Buffer for later
      add_to_buffer(client_id, message)
      {:buffered, message.sequence}
    end
  end
end
```

**Client-side Handling:**
```javascript
class MessageSequencer {
  constructor() {
    this.expected = 0
    this.buffer = new Map()
    this.maxBufferSize = 100
  }
  
  handleMessage(message) {
    if (message.sequence === this.expected) {
      this.processMessage(message)
      this.expected++
      
      // Process any buffered messages
      while (this.buffer.has(this.expected)) {
        const buffered = this.buffer.get(this.expected)
        this.buffer.delete(this.expected)
        this.processMessage(buffered)
        this.expected++
      }
    } else if (message.sequence > this.expected) {
      // Buffer out-of-order message
      if (this.buffer.size < this.maxBufferSize) {
        this.buffer.set(message.sequence, message)
      } else {
        console.error('Message buffer full, dropping:', message)
      }
    } else {
      // Duplicate or old message
      console.warn('Duplicate message:', message.sequence)
    }
  }
  
  processMessage(message) {
    // Handle the message in order
    this.onMessage?.(message.payload)
  }
}
```

### Circuit Breaker Tripping

**Problem:** Circuit breaker opens unnecessarily

**Monitoring:**
```elixir
# Add custom health check
defmodule Gateway.HealthCheck do
  def check_transport_health(transport) do
    case transport do
      :websocket ->
        active = WebSocket.active_connections()
        errors = WebSocket.recent_errors(60) # Last minute
        
        %{
          healthy: errors < active * 0.05,  # Less than 5% error rate
          active_connections: active,
          error_count: errors,
          recommendation: recommend_action(errors, active)
        }
        
      :http_sse ->
        # Similar for SSE
    end
  end
  
  defp recommend_action(errors, active) when errors > active * 0.1 do
    "Consider increasing timeout or checking network stability"
  end
  defp recommend_action(_, _), do: "System operating normally"
end
```

### Backpressure Handling

**Problem:** Client overwhelmed by messages

**Solution:**
```elixir
defmodule Gateway.BackpressureManager do
  @moduledoc """
  Implements adaptive backpressure based on client acknowledgments
  """
  
  def should_throttle?(client_id) do
    stats = get_client_stats(client_id)
    
    cond do
      stats.pending_acks > 100 -> {:throttle, :high}
      stats.pending_acks > 50 -> {:throttle, :medium}
      stats.message_lag > 5000 -> {:throttle, :lagging}
      true -> :ok
    end
  end
  
  def apply_backpressure(client_id, level) do
    case level do
      :high ->
        # Drop non-critical messages
        filter_critical_only(client_id)
        
      :medium ->
        # Slow down message rate
        reduce_rate(client_id, 0.5)
        
      :lagging ->
        # Bundle messages
        enable_bundling(client_id, interval: 1000)
    end
  end
end
```

**Client-side Flow Control:**
```javascript
class FlowControlledClient {
  constructor(channel) {
    this.channel = channel
    this.pendingAcks = 0
    this.maxPending = 50
    
    this.channel.on("message", (msg) => {
      if (this.pendingAcks < this.maxPending) {
        this.handleMessage(msg)
        this.pendingAcks++
      } else {
        console.warn("Dropping message due to backpressure")
      }
    })
  }
  
  handleMessage(msg) {
    // Process message
    processAsync(msg).then(() => {
      this.pendingAcks--
      // Send ack to server
      this.channel.push("ack", {msg_id: msg.id})
    })
  }
}
```

### Recovery Strategies

#### Automatic Recovery with Exponential Backoff
```javascript
class RecoveryManager {
  constructor(gateway) {
    this.gateway = gateway
    this.baseDelay = 1000
    this.maxDelay = 60000
    this.attempts = 0
  }
  
  async attemptRecovery(error) {
    const delay = Math.min(
      this.baseDelay * Math.pow(2, this.attempts),
      this.maxDelay
    )
    
    console.log(`Recovery attempt ${this.attempts + 1} in ${delay}ms`)
    
    await this.sleep(delay)
    
    try {
      await this.gateway.reconnect()
      this.attempts = 0  // Reset on success
      return true
    } catch (e) {
      this.attempts++
      if (this.attempts < 10) {
        return this.attemptRecovery(e)
      } else {
        throw new Error('Max recovery attempts exceeded')
      }
    }
  }
  
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms))
  }
}
```

## Debugging Guide

### Enable Debug Logging
```elixir
# config/dev.exs
config :logger, level: :debug
config :autonomous_opponent_core, :mcp_gateway,
  debug: true,
  log_connections: true,
  log_messages: true,
  trace_routing: true
```

### Common Debug Commands

#### IEx Debugging Commands
```elixir
# Get connection statistics
iex> Gateway.get_connection_stats()
%{
  total: 1523,
  by_transport: %{websocket: 1200, http_sse: 323},
  pool_available: 45,
  pool_overflow: 12,
  avg_connection_age: 3600,  # seconds
  error_rate: 0.02
}

# Trace specific client
iex> Gateway.trace_client("user123")
# Shows all events for specific client
[
  %{timestamp: ~U[2024-01-15 10:23:45Z], event: :connected, transport: :websocket},
  %{timestamp: ~U[2024-01-15 10:23:46Z], event: :message_sent, size: 1024},
  %{timestamp: ~U[2024-01-15 10:24:12Z], event: :transport_switch, from: :websocket, to: :http_sse}
]

# Check connection pool health
iex> ConnectionPool.health_check()
%{
  status: :healthy,
  pool_size: 100,
  available: 67,
  overflow: 5,
  queue_length: 0,
  avg_checkout_time: 12  # ms
}

# View consistent hash distribution
iex> ConsistentHash.get_distribution()
%{
  nodes: [
    %{id: "node1", weight: 1.0, vnode_count: 150, key_count: 512},
    %{id: "node2", weight: 1.0, vnode_count: 150, key_count: 498},
    %{id: "node3", weight: 1.0, vnode_count: 150, key_count: 513}
  ],
  total_keys: 1523,
  distribution_variance: 0.015
}

# Force garbage collection on connections
iex> Gateway.cleanup_idle_connections(max_idle_seconds: 300)
{:cleaned, 47}

# Check circuit breaker states
iex> CircuitBreaker.get_states(:mcp_gateway)
%{
  websocket: :closed,
  http_sse: :open,
  router: :half_open
}
```

### Monitoring Connection Health

#### Health Check Endpoints
```bash
# Check specific client connection
curl http://localhost:4000/mcp/health/client/user123
# Response:
{
  "client_id": "user123",
  "connected": true,
  "transport": "websocket",
  "connection_age": 3600,
  "messages_sent": 152,
  "messages_received": 89,
  "last_activity": "2024-01-15T10:45:23Z"
}

# Get transport statistics
curl http://localhost:4000/mcp/stats
# Response:
{
  "websocket": {
    "connections": 1200,
    "messages_per_second": 5420,
    "avg_latency_ms": 23,
    "errors_per_minute": 2
  },
  "http_sse": {
    "connections": 323,
    "messages_per_second": 1250,
    "avg_latency_ms": 45,
    "errors_per_minute": 0
  }
}

# Force connection cleanup (admin only)
curl -X POST http://localhost:4000/mcp/admin/cleanup \
  -H "Authorization: Bearer admin-token"
```

### Live Monitoring with Observer
```elixir
# Start Observer for visual debugging
iex> :observer.start()

# Navigate to:
# Applications -> autonomous_opponent_core
# Look for MCP.Gateway supervision tree
```

### Debugging Transport Issues

#### WebSocket Debugging
```javascript
// Client-side WebSocket debugging
const socket = new Socket("/mcp/ws", {
  params: {client_id: "debug_user"},
  logger: (kind, msg, data) => {
    console.log(`${kind}: ${msg}`, data);
  }
});

socket.onError((error) => console.error("Socket error:", error));
socket.onClose(() => console.log("Socket closed"));

// Enable verbose Phoenix.js logging
window.Phoenix = {debug: true};
```

#### SSE Debugging
```javascript
// Client-side SSE debugging
const eventSource = new EventSource('/mcp/sse?client_id=debug_user&debug=true');

eventSource.addEventListener('debug', (event) => {
  console.log('Debug info:', JSON.parse(event.data));
});

// Monitor all events
['open', 'message', 'error', 'connected', 'heartbeat'].forEach(eventType => {
  eventSource.addEventListener(eventType, (event) => {
    console.log(`SSE ${eventType}:`, event);
  });
});
```

### Performance Profiling

#### Using ExProf
```elixir
# Profile specific function
iex> ExProf.start()
iex> ExProf.trace(:calls, Gateway, :route_message, 3)
iex> # Generate some traffic
iex> ExProf.analyze()

# Profile memory usage
iex> :recon.proc_count(:memory, 10)
# Shows top 10 processes by memory

# Check message queue lengths
iex> :recon.proc_count(:message_queue_len, 10)
```

#### Flame Graphs
```bash
# Generate flame graph for gateway
mix run --no-halt scripts/profile_gateway.exs
# Outputs flame graph to priv/static/flamegraph.svg
```

### Debugging Connection Leaks

```elixir
# Find long-lived connections
iex> Gateway.find_old_connections(hours: 24)
[
  %{client_id: "user456", age_hours: 72, transport: :websocket},
  %{client_id: "bot789", age_hours: 168, transport: :http_sse}
]

# Analyze connection patterns
iex> Gateway.analyze_connections()
%{
  connection_distribution: %{
    "0-1h": 892,
    "1-6h": 421,
    "6-24h": 187,
    "24h+": 23
  },
  suspicious_patterns: [
    %{pattern: :rapid_reconnect, client_ids: ["bot123", "bot456"]},
    %{pattern: :connection_hoarding, client_ids: ["user789"]}
  ]
}
```

### Troubleshooting Memory Issues

```elixir
# Get memory breakdown
iex> :recon_alloc.memory(:allocated)
# Shows total allocated memory

# Find memory fragmentation
iex> :recon_alloc.fragmentation(:current)

# Identify binary memory leaks
iex> :recon.bin_leak(5)
# Shows top 5 processes holding binaries
```

### Log Analysis

```bash
# Find errors in gateway logs
grep "MCP.Gateway" logs/error.log | grep -E "(error|failed|timeout)"

# Analyze connection patterns
awk '/connected/ {print $1}' logs/gateway.log | sort | uniq -c | sort -nr

# Track specific client
grep "client_id=user123" logs/gateway.log | tail -f
```

## Migration Guide

### From Direct Phoenix Channels

If migrating from direct Phoenix Channel usage, follow these steps:

#### 1. Update Socket Connection
**Before:**
```javascript
import {Socket} from "phoenix"

const socket = new Socket("/socket", {params: {token: userToken}})
socket.connect()

const channel = socket.channel("room:123", {})
channel.join()
  .receive("ok", resp => console.log("Joined"))
```

**After:**
```javascript
import {Socket} from "phoenix"

const socket = new Socket("/mcp/ws", {
  params: {client_id: "user123", token: userToken}
})
socket.connect()

const channel = socket.channel("mcp:gateway", {
  room: "123",
  client_id: "user123"
})
channel.join()
  .receive("ok", resp => console.log("Joined MCP Gateway"))
```

#### 2. Update Event Names
```javascript
// Before
channel.push("new_msg", {body: "Hello"})
channel.on("new_msg", msg => console.log(msg))

// After
channel.push("message", {type: "chat", data: {body: "Hello"}})
channel.on("message", payload => {
  if (payload.type === "chat") {
    console.log(payload.data)
  }
})
```

#### 3. Add Connection Tracking
```javascript
// Add client_id for connection tracking
const clientId = generateClientId() // uuid or user-based ID

// Handle reconnection with same client_id
socket.onError(() => {
  console.log("Connection error, will reconnect with same client_id")
})
```

### From REST API Polling

Transitioning from polling to real-time updates:

#### 1. Keep REST Endpoints for Initial Data
```javascript
// Initial data fetch via REST
async function loadInitialData() {
  const response = await fetch('/api/data')
  const data = await response.json()
  renderData(data)
  
  // Then connect for real-time updates
  connectToGateway()
}
```

#### 2. Implement SSE for Updates
```javascript
function connectToGateway() {
  const eventSource = new EventSource('/mcp/sse?client_id=' + clientId)
  
  eventSource.addEventListener('data_update', (event) => {
    const update = JSON.parse(event.data)
    applyUpdate(update)
  })
  
  eventSource.addEventListener('error', (event) => {
    if (eventSource.readyState === EventSource.CLOSED) {
      // Reconnection will happen automatically
      console.log('SSE connection closed, reconnecting...')
    }
  })
}
```

#### 3. Implement Offline Queue
```javascript
class OfflineQueue {
  constructor() {
    this.queue = []
    this.connected = false
  }
  
  send(message) {
    if (this.connected) {
      return this.gateway.send(message)
    } else {
      this.queue.push(message)
      return Promise.resolve({queued: true})
    }
  }
  
  flush() {
    while (this.queue.length > 0) {
      const message = this.queue.shift()
      this.gateway.send(message)
    }
  }
  
  onConnect() {
    this.connected = true
    this.flush()
  }
}
```

### From Custom WebSocket Implementation

#### 1. Replace Low-Level WebSocket
**Before:**
```javascript
const ws = new WebSocket('ws://localhost:8080/ws')
ws.onopen = () => {
  ws.send(JSON.stringify({type: 'auth', token: userToken}))
}
ws.onmessage = (event) => {
  const data = JSON.parse(event.data)
  handleMessage(data)
}
```

**After:**
```javascript
// Use Phoenix Socket for better reconnection handling
const socket = new Socket("/mcp/ws", {
  params: {client_id: clientId, token: userToken}
})

const channel = socket.channel("mcp:gateway", {})
channel.on("message", handleMessage)
```

#### 2. Add Automatic Reconnection
```javascript
// Phoenix Socket handles reconnection automatically
socket.onError(() => console.log("Connection error"))
socket.onClose(() => console.log("Connection closed"))

// Configure reconnection behavior
const socket = new Socket("/mcp/ws", {
  reconnectAfterMs: (tries) => {
    return [1000, 2000, 5000, 10000][tries - 1] || 10000
  },
  heartbeatIntervalMs: 30000
})
```

### From Message Queue Systems

If migrating from RabbitMQ/Kafka direct connections:

#### 1. Gateway as Abstraction Layer
```elixir
# Before: Direct AMQP publishing
AMQP.Basic.publish(channel, "exchange", "routing_key", message)

# After: Use MCP Gateway
Router.route_message(client_id, message,
  transport: :auto,
  priority: :normal
)
```

#### 2. Maintain Topic-Based Routing
```elixir
# Configure gateway to maintain topic semantics
defmodule MyApp.TopicRouter do
  def route_by_topic(topic, message) do
    client_ids = get_subscribers(topic)
    
    Enum.each(client_ids, fn client_id ->
      Router.route_message(client_id, %{
        topic: topic,
        payload: message
      })
    end)
  end
end
```

### Backend Migration Checklist

- [ ] Update connection endpoints to use MCP Gateway
- [ ] Add client_id generation and management
- [ ] Implement connection state tracking
- [ ] Update message format to gateway structure
- [ ] Add offline message queueing
- [ ] Configure rate limiting per client
- [ ] Set up monitoring and alerting
- [ ] Plan rollback strategy
- [ ] Test with subset of users first
- [ ] Monitor performance metrics during migration

### Gradual Migration Strategy

#### Phase 1: Dual Operation
```javascript
// Support both old and new connections
class HybridClient {
  constructor(useGateway = false) {
    if (useGateway) {
      this.connection = new GatewayConnection()
    } else {
      this.connection = new LegacyConnection()
    }
  }
}
```

#### Phase 2: Feature Flag Rollout
```elixir
# Server-side feature flag
def should_use_gateway?(user_id) do
  FeatureFlags.enabled?(:mcp_gateway, user_id)
end
```

#### Phase 3: Monitor and Optimize
```elixir
# Track migration metrics
defmodule MigrationMetrics do
  def track_connection_type(user_id, type) do
    Metrics.increment("connections.#{type}")
    
    if type == :gateway do
      EventBus.publish(:migration_progress, %{
        user_id: user_id,
        migrated_at: DateTime.utc_now()
      })
    end
  end
end
```

### Post-Migration Cleanup

1. Remove legacy connection code
2. Update documentation
3. Archive old message formats
4. Clean up feature flags
5. Optimize gateway configuration based on usage patterns