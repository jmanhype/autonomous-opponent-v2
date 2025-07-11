@claude Please implement the WebSocket connection count metrics feature you mentioned in your review. This is actually critical for production operations.

## 📊 WebSocket Connection Counting Implementation

### Why This Is Important (8 Critical Use Cases):

| # | Use Case | How the count gets used |
|---|----------|------------------------|
| 1 | **Auto-scaling** | Spin up new pods/VMs when `active ≥ threshold`; scale down when idle |
| 2 | **Capacity protection** | Reject new sockets once we're 90-95% of limit (memory, file descriptors, LB quota) |
| 3 | **Real-time presence** | "124 people online" banners, active-user lists, spectator counts |
| 4 | **Billing/licensing** | SaaS plans that charge by concurrent connections |
| 5 | **Security & throttling** | Detect floods/DDoS: sudden spikes trigger rate-limits or CAPTCHA |
| 6 | **Feature flags/rollouts** | Roll back features if connection churn > baseline |
| 7 | **Performance dashboards** | Plot `websocket_active` on Grafana; alert when it diverges from HTTP volume |
| 8 | **Cost attribution** | Translate connection-seconds into cloud egress/compute spend |

### Implementation Requirements:

1. **Track connections per channel topic**:
   - `patterns:stream` active connections
   - `patterns:stats` active connections  
   - `patterns:vsm` active connections

2. **Expose metrics via**:
   - Add to `get_monitoring_info` response
   - Create dedicated `get_connection_stats` endpoint
   - Include in periodic stats broadcasts

3. **Cluster-wide aggregation**:
   - Each node tracks its local connections
   - PatternAggregator collects and sums across cluster
   - Expose total and per-node breakdowns

4. **Implementation approach**:
   ```elixir
   # In PatternsChannel
   def join(topic, payload, socket) do
     # Increment counter
     :ets.update_counter(:pattern_channel_connections, {topic, node()}, 1, {{topic, node()}, 0})
     # ... existing code
   end
   
   def terminate(_reason, socket) do
     # Decrement counter
     topic = socket.topic
     :ets.update_counter(:pattern_channel_connections, {topic, node()}, -1)
     # ... cleanup code
   end
   ```

This is a critical operational metric that drives scaling, safety limits, real-time UX, and cost management. Please implement this along with the other remaining fixes.

Thank you! 🚀