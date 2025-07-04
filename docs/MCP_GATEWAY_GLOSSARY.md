# MCP Gateway Glossary

This glossary provides definitions for key terms and concepts used throughout the MCP Gateway documentation.

## A

**Algedonic Channel**
: VSM bypass channel for pain/pleasure signals that require immediate attention. Critical system events (like pool exhaustion or circuit breaker opening) trigger pain signals through this channel, bypassing normal hierarchical processing.

**Anti-oscillation**
: S2 (Coordination) function that prevents rapid switching between states. In the gateway context, it prevents clients from switching rapidly between WebSocket and SSE transports.

**Ashby's Law**
: The Law of Requisite Variety - states that a system must have at least as much variety as the environment it's trying to control. The gateway acts as a variety attenuator to reduce external variety before it reaches internal systems.

## B

**Backpressure**
: Flow control mechanism where a system signals upstream that it cannot handle more load. The gateway implements backpressure by slowing message delivery when clients can't keep up.

## C

**Circuit Breaker**
: Design pattern that prevents cascading failures by stopping calls to failing services. The gateway has circuit breakers for each transport type that open after repeated failures.

**Client ID**
: Unique identifier for each connected client. Used for connection tracking, rate limiting, and message routing. Format: alphanumeric string, typically UUID or user-based.

**Connection Pool**
: Managed set of reusable connections to prevent resource exhaustion. The gateway uses Poolboy to manage a configurable pool of connections with overflow capability.

**Consistent Hashing**
: Load balancing algorithm that minimizes redistribution when nodes are added or removed. Uses virtual nodes to ensure even distribution and predictable routing.

## E

**EventBus**
: Internal pub/sub system for message passing between components. All VSM subsystems and the gateway communicate through the EventBus.

## H

**Heartbeat**
: Periodic signal sent to maintain connection state. SSE sends heartbeats every 30 seconds, WebSocket uses ping/pong frames.

## L

**Load Balancing**
: Distribution of work across multiple resources. The gateway uses consistent hashing to distribute connections across available transports and nodes.

## M

**MCP (Model Context Protocol)**
: The gateway's protocol for client-server communication. Not to be confused with AMCP which uses AMQP/RabbitMQ.

**Message Batching**
: Grouping multiple messages together for efficient transmission. Reduces overhead and improves throughput at the cost of slight latency increase.

## O

**Overflow Pool**
: Additional connections available when the main pool is exhausted. Provides elasticity during traffic spikes.

## P

**Phoenix Channel**
: WebSocket abstraction in Phoenix framework that provides topics, event handling, and presence tracking. Used for the WebSocket transport.

**Poolboy**
: Erlang/Elixir library for connection pooling. Provides configurable pools with overflow, health checks, and lifecycle management.

## R

**Rate Limiting**
: Controlling the rate of requests to prevent abuse. The gateway implements per-client rate limiting using token bucket algorithm.

**Reconnection**
: Automatic re-establishment of lost connections. Both SSE and WebSocket transports support automatic reconnection with exponential backoff.

## S

**S1-S5**
: The five VSM subsystems:
- **S1 (Operations)**: Handles day-to-day operations and variety absorption
- **S2 (Coordination)**: Prevents oscillation and coordinates between units
- **S3 (Control)**: Resource management and optimization
- **S4 (Intelligence)**: Environmental scanning and future planning
- **S5 (Policy)**: Identity, purpose, and governance

**SSE (Server-Sent Events)**
: HTTP-based protocol for server-to-client streaming. One-way communication, automatic reconnection, works through proxies.

**Session Affinity**
: Ensuring a client always connects to the same backend node. Maintained through consistent hashing based on client_id.

## T

**Transport**
: Communication protocol layer used for client connections. The gateway supports two transports: WebSocket and SSE.

**Transport Failover**
: Automatic switching from one transport to another when failures occur. For example, switching from WebSocket to SSE when WebSocket connections fail.

## V

**Variety**
: In VSM/cybernetics terms, the number of possible states a system can have. External variety from many clients is high; the gateway reduces this variety before it reaches internal systems.

**Variety Attenuation**
: Process of reducing the number of possible states or complexity. The gateway attenuates variety through rate limiting, message filtering, and aggregation.

**Variety Amplification**
: Increasing the system's ability to respond to variety. While the gateway primarily attenuates, it amplifies control variety through routing and load balancing.

**Virtual Nodes (vnodes)**
: In consistent hashing, multiple hash positions per physical node to ensure even distribution. Default: 150 vnodes per node.

**VSM (Viable System Model)**
: Cybernetic model created by Stafford Beer with 5 subsystems (S1-S5) for understanding organizational structure. The gateway integrates with all VSM subsystems.

## W

**WebSocket**
: Full-duplex communication protocol over TCP. Provides bidirectional, real-time communication with lower overhead than HTTP.

**W3C Trace Context**
: Standard for distributed tracing that allows correlation of requests across services. Used by the gateway's OpenTelemetry integration.

## Symbols

**:mcp_gateway**
: Erlang atom representing the gateway in the supervision tree and EventBus topics.

**{:ok, result}** / **{:error, reason}**
: Elixir's standard tuple format for function returns. {:ok, ...} indicates success, {:error, ...} indicates failure.

---

## Common Acronyms

- **BEAM**: Erlang virtual machine (Björn's Erlang Abstract Machine)
- **CI/CD**: Continuous Integration/Continuous Deployment
- **JWT**: JSON Web Token
- **OTP**: Open Telecom Platform (Erlang/Elixir framework)
- **OTLP**: OpenTelemetry Protocol
- **p50/p95/p99**: Percentile metrics (50th, 95th, 99th percentile)
- **SLO**: Service Level Objective
- **TLS**: Transport Layer Security

## Usage Notes

1. Terms are used consistently throughout the documentation
2. VSM-specific terms follow Stafford Beer's original definitions
3. Technical terms align with industry standards
4. Elixir/Erlang terms follow community conventions

For more detailed explanations, refer to the main documentation files or the implementation code.