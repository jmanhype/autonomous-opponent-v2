# MCP Gateway Testing Guide

This guide provides comprehensive examples and best practices for writing integration tests against the MCP Gateway. It covers unit testing, integration testing, load testing, and end-to-end scenarios.

## Table of Contents

1. [Test Setup](#test-setup)
2. [Unit Testing](#unit-testing)
3. [Integration Testing](#integration-testing)
4. [Load Testing](#load-testing)
5. [End-to-End Testing](#end-to-end-testing)
6. [Testing Best Practices](#testing-best-practices)
7. [Common Test Patterns](#common-test-patterns)
8. [Troubleshooting Tests](#troubleshooting-tests)

## Test Setup

### ExUnit Configuration

```elixir
# test/test_helper.exs
ExUnit.start(capture_log: true)

# Configure test environment
Application.put_env(:autonomous_opponent_core, :mcp_gateway,
  pool: [size: 10, overflow: 5],
  rate_limiting: [default_limit: 1000],
  debug: true
)

# Ensure applications are started
Application.ensure_all_started(:autonomous_opponent_core)
Application.ensure_all_started(:autonomous_opponent_web)
```

### Test Case Template

```elixir
defmodule YourApp.GatewayTestCase do
  @moduledoc """
  Common setup for gateway tests
  """
  
  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case, async: true
      alias AutonomousOpponentCore.{EventBus, MCP}
      alias AutonomousOpponentCore.MCP.{Gateway, Transport}
      
      setup do
        # Generate unique client ID for each test
        client_id = "test_client_#{:rand.uniform(10000)}"
        
        # Subscribe to relevant events
        EventBus.subscribe(:gateway_events)
        EventBus.subscribe({:mcp_client, client_id})
        
        on_exit(fn ->
          # Cleanup connections
          Gateway.disconnect_client(client_id)
        end)
        
        {:ok, client_id: client_id}
      end
    end
  end
end
```

## Unit Testing

### Testing Transport Modules

```elixir
defmodule MCP.Transport.WebSocketTest do
  use ExUnit.Case, async: true
  alias AutonomousOpponentCore.MCP.Transport.WebSocket
  
  describe "connection management" do
    test "registers new connection" do
      client_id = "test_#{:rand.uniform(1000)}"
      transport_pid = self()
      
      assert :ok = WebSocket.register_connection(client_id, transport_pid)
      assert {:ok, ^transport_pid} = WebSocket.get_connection(client_id)
    end
    
    test "handles duplicate registration" do
      client_id = "test_#{:rand.uniform(1000)}"
      pid1 = spawn(fn -> :timer.sleep(100) end)
      pid2 = spawn(fn -> :timer.sleep(100) end)
      
      assert :ok = WebSocket.register_connection(client_id, pid1)
      assert {:error, :already_registered} = WebSocket.register_connection(client_id, pid2)
    end
    
    test "cleans up on process exit" do
      client_id = "test_#{:rand.uniform(1000)}"
      
      # Spawn a process that registers and then exits
      pid = spawn(fn ->
        WebSocket.register_connection(client_id, self())
        :timer.sleep(10)
      end)
      
      # Wait for process to register
      :timer.sleep(20)
      
      # Verify connection was cleaned up
      assert {:error, :not_found} = WebSocket.get_connection(client_id)
    end
  end
  
  describe "message handling" do
    setup do
      client_id = "test_#{:rand.uniform(1000)}"
      {:ok, pid} = WebSocket.start_link(client_id: client_id)
      {:ok, client_id: client_id, pid: pid}
    end
    
    test "processes valid messages", %{pid: pid} do
      message = %{type: "test", data: %{value: 42}}
      
      assert :ok = WebSocket.send_message(pid, message)
      assert_receive {:websocket_sent, ^message}, 100
    end
    
    test "handles compression for large messages", %{pid: pid} do
      # Create message > 1KB
      large_data = :crypto.strong_rand_bytes(2000) |> Base.encode64()
      message = %{type: "large", data: large_data}
      
      assert :ok = WebSocket.send_message(pid, message)
      assert_receive {:websocket_sent, %{compressed: true}}, 100
    end
  end
end
```

### Testing Connection Pool

```elixir
defmodule MCP.Pool.ConnectionPoolTest do
  use ExUnit.Case, async: false
  alias AutonomousOpponentCore.MCP.Pool.ConnectionPool
  
  setup do
    # Start fresh pool for each test
    {:ok, pool} = ConnectionPool.start_link(
      name: :test_pool,
      size: 5,
      overflow: 2
    )
    
    on_exit(fn ->
      GenServer.stop(pool)
    end)
    
    {:ok, pool: pool}
  end
  
  describe "pool management" do
    test "respects pool size limits", %{pool: pool} do
      # Checkout all available connections
      connections = for _ <- 1..5 do
        assert {:ok, conn} = ConnectionPool.checkout(pool)
        conn
      end
      
      # Verify pool is exhausted
      assert {:error, :pool_timeout} = ConnectionPool.checkout(pool, timeout: 100)
      
      # Return one connection
      ConnectionPool.checkin(pool, hd(connections))
      
      # Should now be able to checkout
      assert {:ok, _conn} = ConnectionPool.checkout(pool)
    end
    
    test "handles overflow correctly", %{pool: pool} do
      # Checkout main pool + overflow
      connections = for _ <- 1..7 do
        assert {:ok, conn} = ConnectionPool.checkout(pool)
        conn
      end
      
      # Pool + overflow exhausted
      assert {:error, :pool_timeout} = ConnectionPool.checkout(pool, timeout: 100)
      
      # Return all connections
      Enum.each(connections, &ConnectionPool.checkin(pool, &1))
      
      # Check pool health
      assert %{available: 5, overflow: 0} = ConnectionPool.status(pool)
    end
  end
end
```

### Testing Load Balancer

```elixir
defmodule MCP.LoadBalancer.ConsistentHashTest do
  use ExUnit.Case, async: true
  alias AutonomousOpponentCore.MCP.LoadBalancer.ConsistentHash
  
  describe "node distribution" do
    setup do
      nodes = ["node1", "node2", "node3"]
      {:ok, hash} = ConsistentHash.start_link(nodes: nodes, vnodes: 150)
      {:ok, hash: hash, nodes: nodes}
    end
    
    test "distributes keys evenly", %{hash: hash} do
      # Generate test keys
      keys = for i <- 1..1000, do: "key_#{i}"
      
      # Count distribution
      distribution = Enum.reduce(keys, %{}, fn key, acc ->
        node = ConsistentHash.get_node(hash, key)
        Map.update(acc, node, 1, &(&1 + 1))
      end)
      
      # Verify roughly even distribution (within 20% variance)
      expected = 1000 / 3
      Enum.each(distribution, fn {_node, count} ->
        assert count > expected * 0.8
        assert count < expected * 1.2
      end)
    end
    
    test "maintains consistency on node changes", %{hash: hash} do
      # Record initial mappings
      keys = for i <- 1..100, do: "key_#{i}"
      initial_mapping = Map.new(keys, fn key ->
        {key, ConsistentHash.get_node(hash, key)}
      end)
      
      # Add a new node
      ConsistentHash.add_node(hash, "node4")
      
      # Check how many keys moved
      moved = Enum.count(keys, fn key ->
        new_node = ConsistentHash.get_node(hash, key)
        initial_mapping[key] != new_node
      end)
      
      # Should move approximately 25% of keys (1/4 nodes)
      assert moved > 20
      assert moved < 35
    end
  end
end
```

## Integration Testing

### Basic Integration Test

```elixir
defmodule MCP.IntegrationTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  
  alias AutonomousOpponentCore.{EventBus, MCP.Gateway}
  alias AutonomousOpponentCore.MCP.Transport.Router
  
  setup_all do
    # Ensure gateway is running
    Application.ensure_all_started(:autonomous_opponent_core)
    :ok
  end
  
  describe "end-to-end message flow" do
    test "message flows through gateway to VSM" do
      client_id = "integration_test_#{:rand.uniform(1000)}"
      
      # Subscribe to VSM events
      EventBus.subscribe(:s1_operations)
      EventBus.subscribe(:s4_intelligence)
      
      # Connect client
      assert {:ok, conn} = Gateway.connect(client_id, transport: :websocket)
      
      # Send message through gateway
      message = %{
        type: "test_message",
        data: %{value: 42, timestamp: DateTime.utc_now()}
      }
      
      assert :ok = Router.route_message(client_id, message)
      
      # Verify S1 received the message
      assert_receive {:event_bus, :s1_operations, %{
        source: :mcp_gateway,
        variety_type: :external_input,
        payload: ^message
      }}, 1000
      
      # Verify S4 received metrics
      assert_receive {:event_bus, :s4_intelligence, %{
        metric_type: :gateway_performance,
        data: metrics
      }}, 2000
      
      assert metrics.active_connections > 0
    end
    
    test "failover between transports" do
      client_id = "failover_test_#{:rand.uniform(1000)}"
      
      # Subscribe to transport events
      EventBus.subscribe({:mcp_client, client_id})
      
      # Connect via WebSocket
      assert {:ok, _} = Gateway.connect(client_id, transport: :websocket)
      
      # Force WebSocket failure
      Gateway.simulate_transport_failure(client_id, :websocket)
      
      # Should receive transport switch event
      assert_receive {:event_bus, {:mcp_client, ^client_id}, 
        {:transport_switched, :websocket, :http_sse}}, 2000
      
      # Verify can still send messages
      assert :ok = Router.route_message(client_id, %{type: "test"})
    end
  end
  
  describe "VSM integration" do
    test "respects S5 policy constraints" do
      client_id = "policy_test_#{:rand.uniform(1000)}"
      
      # Set restrictive policy
      EventBus.publish(:s5_policy, %{
        update: :connection_limit,
        transport: :websocket,
        max_connections: 1
      })
      
      # First connection should succeed
      assert {:ok, _} = Gateway.connect("client_1", transport: :websocket)
      
      # Second should fail due to policy
      assert {:error, :policy_violation} = 
        Gateway.connect("client_2", transport: :websocket)
    end
    
    test "triggers algedonic signals on critical failures" do
      EventBus.subscribe(:algedonic_channel)
      
      # Exhaust connection pool
      connections = for i <- 1..200 do
        Gateway.connect("stress_#{i}", transport: :websocket)
      end
      
      # Should receive pain signal
      assert_receive {:event_bus, :algedonic_channel, %{
        signal_type: :pain,
        severity: :critical,
        source: :mcp_gateway,
        message: "Connection pool exhausted"
      }}, 5000
    end
  end
end
```

### Phoenix Channel Integration Tests

```elixir
defmodule AutonomousOpponentWeb.MCPChannelIntegrationTest do
  use AutonomousOpponentWeb.ChannelCase
  @moduletag :integration
  
  alias AutonomousOpponentWeb.{MCPSocket, MCPChannel}
  
  setup do
    client_id = "channel_test_#{:rand.uniform(1000)}"
    
    # Create socket connection
    {:ok, socket} = connect(MCPSocket, %{"client_id" => client_id})
    
    {:ok, socket: socket, client_id: client_id}
  end
  
  describe "channel lifecycle" do
    test "full connection flow", %{socket: socket, client_id: client_id} do
      # Join channel
      {:ok, _, socket} = subscribe_and_join(
        socket, 
        MCPChannel, 
        "mcp:gateway",
        %{"client_id" => client_id}
      )
      
      # Send message
      ref = push(socket, "message", %{
        "type" => "test",
        "data" => %{"value" => 123}
      })
      
      assert_reply ref, :ok, %{received: true}
      
      # Should receive echo
      assert_push "message", %{
        "type" => "echo",
        "data" => %{"original" => %{"value" => 123}}
      }
      
      # Leave channel
      Process.unlink(socket.channel_pid)
      ref = leave(socket)
      assert_reply ref, :ok
    end
    
    test "rate limiting enforcement", %{socket: socket, client_id: client_id} do
      {:ok, _, socket} = subscribe_and_join(socket, "mcp:gateway", %{})
      
      # Send messages up to rate limit
      for i <- 1..100 do
        ref = push(socket, "message", %{"index" => i})
        assert_reply ref, :ok, _
      end
      
      # Next message should be rate limited
      ref = push(socket, "message", %{"index" => 101})
      assert_reply ref, :error, %{reason: "rate_limit_exceeded"}
    end
  end
  
  describe "error handling" do
    test "handles malformed messages", %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, "mcp:gateway", %{})
      
      # Send invalid message
      ref = push(socket, "message", "not a map")
      assert_reply ref, :error, %{reason: "invalid_message_format"}
      
      # Connection should remain active
      ref = push(socket, "ping", %{})
      assert_reply ref, :ok, %{pong: true}
    end
    
    test "graceful disconnection", %{socket: socket, client_id: client_id} do
      {:ok, _, socket} = subscribe_and_join(socket, "mcp:gateway", %{})
      
      # Monitor the channel process
      Process.monitor(socket.channel_pid)
      
      # Simulate client disconnect
      Process.exit(socket.channel_pid, :shutdown)
      
      # Should receive DOWN message
      assert_receive {:DOWN, _, :process, _, :shutdown}, 1000
      
      # Verify cleanup
      assert {:error, :not_found} = Gateway.get_client_info(client_id)
    end
  end
end
```

## Load Testing

### Concurrent Connection Test

```elixir
defmodule MCP.LoadTest do
  use ExUnit.Case, async: false
  @moduletag :load_test
  @moduletag timeout: :infinity
  
  alias AutonomousOpponentCore.MCP.Gateway
  
  describe "concurrent connections" do
    test "handles 1000 concurrent connections" do
      num_connections = 1000
      
      # Start timing
      start_time = System.monotonic_time(:millisecond)
      
      # Create connections concurrently
      tasks = for i <- 1..num_connections do
        Task.async(fn ->
          client_id = "load_test_#{i}"
          
          case Gateway.connect(client_id, transport: :websocket) do
            {:ok, conn} -> {:ok, client_id, conn}
            {:error, reason} -> {:error, client_id, reason}
          end
        end)
      end
      
      # Wait for all connections
      results = Task.await_many(tasks, 30_000)
      
      # Calculate metrics
      connect_time = System.monotonic_time(:millisecond) - start_time
      successful = Enum.count(results, &match?({:ok, _, _}, &1))
      failed = num_connections - successful
      
      # Log results
      IO.puts """
      Load Test Results:
      - Total connections: #{num_connections}
      - Successful: #{successful}
      - Failed: #{failed}
      - Total time: #{connect_time}ms
      - Avg time per connection: #{connect_time / num_connections}ms
      """
      
      # Assertions
      assert successful >= num_connections * 0.95  # 95% success rate
      assert connect_time < 10_000  # Under 10 seconds total
      
      # Cleanup
      results
      |> Enum.filter(&match?({:ok, _, _}, &1))
      |> Enum.each(fn {:ok, client_id, _} ->
        Gateway.disconnect(client_id)
      end)
    end
    
    test "message throughput under load" do
      num_clients = 100
      messages_per_client = 100
      
      # Setup clients
      clients = for i <- 1..num_clients do
        client_id = "throughput_test_#{i}"
        {:ok, _} = Gateway.connect(client_id, transport: :websocket)
        client_id
      end
      
      # Subscribe to metrics
      EventBus.subscribe(:s4_intelligence)
      
      # Start timing
      start_time = System.monotonic_time(:millisecond)
      
      # Send messages concurrently
      tasks = for client_id <- clients do
        Task.async(fn ->
          for j <- 1..messages_per_client do
            message = %{
              type: "load_test",
              data: %{client: client_id, index: j}
            }
            Router.route_message(client_id, message)
          end
        end)
      end
      
      # Wait for completion
      Task.await_many(tasks, 60_000)
      
      # Calculate throughput
      total_time = System.monotonic_time(:millisecond) - start_time
      total_messages = num_clients * messages_per_client
      throughput = total_messages / (total_time / 1000)  # messages per second
      
      IO.puts """
      Throughput Test Results:
      - Total messages: #{total_messages}
      - Total time: #{total_time}ms
      - Throughput: #{Float.round(throughput, 2)} msg/sec
      """
      
      # Verify throughput meets requirements
      assert throughput > 1000  # At least 1000 msg/sec
      
      # Cleanup
      Enum.each(clients, &Gateway.disconnect/1)
    end
  end
  
  describe "stress testing" do
    test "connection churn" do
      duration = 10_000  # 10 seconds
      end_time = System.monotonic_time(:millisecond) + duration
      
      # Track metrics
      connections = :atomics.new(1, [])
      disconnections = :atomics.new(1, [])
      errors = :atomics.new(1, [])
      
      # Start churning connections
      tasks = for i <- 1..50 do
        Task.async(fn ->
          churn_connections(i, end_time, connections, disconnections, errors)
        end)
      end
      
      # Wait for completion
      Task.await_many(tasks, duration + 5000)
      
      # Get final counts
      total_connections = :atomics.get(connections, 1)
      total_disconnections = :atomics.get(disconnections, 1)
      total_errors = :atomics.get(errors, 1)
      
      IO.puts """
      Churn Test Results:
      - Connections: #{total_connections}
      - Disconnections: #{total_disconnections}
      - Errors: #{total_errors}
      - Error rate: #{Float.round(total_errors / total_connections * 100, 2)}%
      """
      
      # Verify system remained stable
      assert total_errors / total_connections < 0.05  # Less than 5% error rate
    end
  end
  
  # Helper function for connection churn
  defp churn_connections(worker_id, end_time, connections, disconnections, errors) do
    if System.monotonic_time(:millisecond) < end_time do
      client_id = "churn_#{worker_id}_#{:rand.uniform(10000)}"
      
      case Gateway.connect(client_id, transport: Enum.random([:websocket, :http_sse])) do
        {:ok, _conn} ->
          :atomics.add(connections, 1, 1)
          
          # Hold connection briefly
          :timer.sleep(:rand.uniform(100))
          
          # Disconnect
          Gateway.disconnect(client_id)
          :atomics.add(disconnections, 1, 1)
          
        {:error, _reason} ->
          :atomics.add(errors, 1, 1)
      end
      
      # Continue churning
      churn_connections(worker_id, end_time, connections, disconnections, errors)
    end
  end
end
```

### VSM Variety Management Integration Tests

```elixir
describe "VSM variety management" do
  test "gateway attenuates variety before S1" do
    # Setup high variety scenario
    clients = for i <- 1..100, do: "high_variety_#{i}"
    
    # Generate diverse message types
    messages = for client <- clients, type <- [:chat, :command, :query] do
      %{client_id: client, type: type, data: %{value: :rand.uniform(100)}}
    end
    
    # Measure S1 input before gateway
    EventBus.subscribe(:s1_operations)
    start_time = System.monotonic_time(:millisecond)
    
    # Send all messages through gateway
    Enum.each(messages, fn msg ->
      Router.route_message(msg.client_id, msg)
    end)
    
    # Wait for processing
    Process.sleep(1000)
    
    # Collect S1 metrics
    s1_messages = collect_messages(:s1_operations, start_time)
    
    # Verify variety reduction
    assert length(s1_messages) < length(messages) * 0.5
    assert Gateway.get_variety_metrics().reduction_ratio > 0.5
  end
  
  test "algedonic bypass works under extreme load" do
    EventBus.subscribe(:algedonic_channel)
    
    # Generate overwhelming load
    tasks = for i <- 1..1000 do
      Task.async(fn ->
        Router.route_message("stress_#{i}", %{data: "flood"})
      end)
    end
    
    # Should receive pain signal
    assert_receive {:event_bus, :algedonic_channel, %{
      signal_type: :pain,
      severity: severity,
      source: :mcp_gateway
    }}, 5000
    
    assert severity in [:high, :critical]
    
    # Cleanup
    Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
  end
  
  test "S2 prevents transport oscillation" do
    client_id = "oscillation_test_#{:rand.uniform(1000)}"
    
    # Subscribe to coordination events
    EventBus.subscribe(:s2_coordination)
    
    # Connect and force rapid transport switches
    Gateway.connect(client_id, transport: :websocket)
    
    # Attempt to trigger oscillation
    for _ <- 1..10 do
      Gateway.simulate_transport_failure(client_id, :websocket)
      Process.sleep(100)
      Gateway.simulate_transport_failure(client_id, :http_sse)
      Process.sleep(100)
    end
    
    # S2 should prevent oscillation
    assert_receive {:event_bus, :s2_coordination, %{
      action: :prevent_oscillation,
      client_id: ^client_id
    }}, 2000
    
    # Verify client stabilized on one transport
    Process.sleep(1000)
    info = Gateway.get_client_info(client_id)
    assert info.transport_switches < 5
  end
  
  test "S4 receives gateway intelligence metrics" do
    EventBus.subscribe(:s4_intelligence)
    
    # Generate pattern-rich traffic
    users = for i <- 1..20, do: "pattern_user_#{i}"
    
    # Create recognizable pattern (burst traffic)
    for cycle <- 1..3 do
      # Burst phase
      Enum.each(users, fn user ->
        for _ <- 1..10 do
          Router.route_message(user, %{type: "burst", cycle: cycle})
        end
      end)
      
      # Quiet phase
      Process.sleep(2000)
    end
    
    # S4 should detect the pattern
    assert_receive {:event_bus, :s4_intelligence, %{
      event: :pattern_detected,
      pattern: :burst_traffic,
      confidence: confidence
    }}, 10_000
    
    assert confidence > 0.8
  end
  
  test "complete VSM message flow" do
    client_id = "vsm_flow_test_#{:rand.uniform(1000)}"
    
    # Subscribe to all VSM subsystems
    EventBus.subscribe(:s1_operations)
    EventBus.subscribe(:s2_coordination)
    EventBus.subscribe(:s3_control)
    EventBus.subscribe(:s4_intelligence)
    EventBus.subscribe(:s5_policy)
    EventBus.subscribe(:algedonic_channel)
    
    # Connect client
    Gateway.connect(client_id, transport: :websocket)
    
    # Send message that requires full VSM processing
    message = %{
      type: "complex_operation",
      data: %{
        requires_resources: true,
        policy_check: true,
        coordination_needed: true
      }
    }
    
    Router.route_message(client_id, message)
    
    # Verify message flows through all subsystems
    assert_receive {:event_bus, :s5_policy, %{
      check: :message_allowed,
      client_id: ^client_id
    }}, 1000
    
    assert_receive {:event_bus, :s1_operations, %{
      source: :mcp_gateway,
      variety_type: :external_input
    }}, 1000
    
    assert_receive {:event_bus, :s2_coordination, %{
      action: :coordinate_operation,
      operation_id: _
    }}, 2000
    
    assert_receive {:event_bus, :s3_control, %{
      request: :allocate,
      operation_id: _
    }}, 2000
    
    assert_receive {:event_bus, :s4_intelligence, %{
      metric_type: :gateway_performance
    }}, 5000
  end
end

# Helper function for collecting messages
defp collect_messages(topic, start_time) do
  messages = []
  receive do
    {:event_bus, ^topic, msg} when msg.timestamp > start_time ->
      collect_messages(topic, start_time) ++ [msg]
  after
    100 -> messages
  end
end
```

### Performance Regression Tests

```elixir
@tag :performance
describe "performance regression tests" do
  test "message latency stays within bounds" do
    results = LoadTest.run_latency_test(
      duration: 60_000,
      connections: 100,
      message_rate: 10
    )
    
    assert results.p50 < 5   # 5ms
    assert results.p95 < 50  # 50ms
    assert results.p99 < 100 # 100ms
  end
  
  test "connection pool efficiency" do
    # Measure pool utilization under load
    start_metrics = ConnectionPool.get_metrics()
    
    # Create load
    clients = for i <- 1..100 do
      {:ok, _} = Gateway.connect("perf_#{i}", transport: :websocket)
      "perf_#{i}"
    end
    
    # Send messages
    for _ <- 1..1000 do
      client = Enum.random(clients)
      Router.route_message(client, %{type: "test"})
    end
    
    end_metrics = ConnectionPool.get_metrics()
    
    # Verify pool efficiency
    assert end_metrics.checkout_success_rate > 0.95
    assert end_metrics.avg_wait_time < 5  # ms
    assert end_metrics.overflow_used < 10
  end
  
  test "VSM variety reduction effectiveness" do
    # Measure variety reduction under different loads
    test_scenarios = [
      {10, 100},    # 10 clients, 100 msg each
      {100, 10},    # 100 clients, 10 msg each  
      {50, 50}      # 50 clients, 50 msg each
    ]
    
    results = Enum.map(test_scenarios, fn {clients, messages} ->
      EventBus.subscribe(:s1_operations)
      
      # Generate load
      input_count = clients * messages
      for i <- 1..clients, j <- 1..messages do
        Router.route_message("test_#{i}", %{seq: j})
      end
      
      # Wait and count S1 messages
      Process.sleep(2000)
      s1_count = count_s1_messages()
      
      %{
        input: input_count,
        output: s1_count,
        reduction: (input_count - s1_count) / input_count
      }
    end)
    
    # All scenarios should achieve > 50% reduction
    Enum.each(results, fn result ->
      assert result.reduction > 0.5
    end)
  end
end
```

## End-to-End Testing

### Complete User Journey Test

```elixir
defmodule MCP.E2ETest do
  use ExUnit.Case, async: false
  @moduletag :e2e
  
  alias AutonomousOpponentCore.{EventBus, MCP}
  
  describe "complete user journey" do
    test "user session from connection to disconnection" do
      user_id = "e2e_user_#{:rand.uniform(1000)}"
      
      # Phase 1: Connection
      assert {:ok, conn} = Gateway.connect(user_id, 
        transport: :websocket,
        metadata: %{device: "test_device"}
      )
      
      # Phase 2: Authentication
      auth_message = %{
        type: "auth",
        data: %{token: "test_token_#{user_id}"}
      }
      assert :ok = Router.route_message(user_id, auth_message)
      
      # Wait for auth confirmation
      assert_receive {:event_bus, {:mcp_client, ^user_id}, 
        {:auth_status, :authenticated}}, 1000
      
      # Phase 3: Subscribe to topics
      subscription_message = %{
        type: "subscribe",
        data: %{topics: ["news", "updates", "alerts"]}
      }
      assert :ok = Router.route_message(user_id, subscription_message)
      
      # Phase 4: Receive messages
      EventBus.publish(:gateway_broadcast, %{
        topic: "news",
        content: "Breaking news!"
      })
      
      assert_receive {:event_bus, {:mcp_client, ^user_id},
        {:message, %{topic: "news", content: "Breaking news!"}}}, 1000
      
      # Phase 5: Send user action
      action_message = %{
        type: "action",
        data: %{
          action: "like",
          target: "post_123"
        }
      }
      assert :ok = Router.route_message(user_id, action_message)
      
      # Phase 6: Transport switch (simulate network change)
      Gateway.simulate_transport_failure(user_id, :websocket)
      
      # Should auto-switch to SSE
      assert_receive {:event_bus, {:mcp_client, ^user_id},
        {:transport_switched, :websocket, :http_sse}}, 2000
      
      # Phase 7: Continue receiving messages on new transport
      EventBus.publish(:gateway_broadcast, %{
        topic: "updates",
        content: "System update available"
      })
      
      assert_receive {:event_bus, {:mcp_client, ^user_id},
        {:message, %{topic: "updates"}}}, 1000
      
      # Phase 8: Graceful disconnection
      assert :ok = Gateway.disconnect(user_id)
      
      # Verify cleanup
      assert {:error, :not_found} = Gateway.get_client_info(user_id)
    end
  end
  
  describe "multi-user interaction" do
    test "chat room scenario" do
      room_id = "room_#{:rand.uniform(1000)}"
      users = for i <- 1..5, do: "chat_user_#{i}"
      
      # Connect all users
      Enum.each(users, fn user ->
        assert {:ok, _} = Gateway.connect(user, transport: :websocket)
        
        # Join room
        join_msg = %{
          type: "join_room",
          data: %{room_id: room_id}
        }
        assert :ok = Router.route_message(user, join_msg)
      end)
      
      # User 1 sends message
      chat_message = %{
        type: "chat_message",
        data: %{
          room_id: room_id,
          content: "Hello everyone!",
          timestamp: DateTime.utc_now()
        }
      }
      
      Router.route_message(hd(users), chat_message)
      
      # All other users should receive it
      other_users = tl(users)
      Enum.each(other_users, fn user ->
        assert_receive {:event_bus, {:mcp_client, ^user},
          {:message, %{
            type: "chat_message",
            data: %{content: "Hello everyone!"}
          }}}, 1000
      end)
      
      # Cleanup
      Enum.each(users, &Gateway.disconnect/1)
    end
  end
end
```

### Testing with External Services

```elixir
defmodule MCP.ExternalIntegrationTest do
  use ExUnit.Case, async: false
  @moduletag :external_integration
  
  # Skip these tests in CI
  @moduletag :skip_ci
  
  describe "RabbitMQ integration" do
    setup do
      # Ensure RabbitMQ is available
      case AMQP.Connection.open() do
        {:ok, conn} ->
          on_exit(fn -> AMQP.Connection.close(conn) end)
          {:ok, conn: conn}
        {:error, _} ->
          :skip
      end
    end
    
    test "gateway publishes to AMQP", %{conn: amqp_conn} do
      {:ok, channel} = AMQP.Channel.open(amqp_conn)
      
      # Setup queue
      {:ok, %{queue: queue}} = AMQP.Queue.declare(channel, "", exclusive: true)
      :ok = AMQP.Queue.bind(channel, queue, "gateway_exchange", routing_key: "test.#")
      
      # Subscribe to queue
      {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue)
      
      # Send message through gateway
      client_id = "amqp_test_#{:rand.uniform(1000)}"
      {:ok, _} = Gateway.connect(client_id, transport: :websocket)
      
      message = %{
        type: "external_publish",
        data: %{
          routing_key: "test.message",
          payload: "Hello AMQP!"
        }
      }
      
      Router.route_message(client_id, message)
      
      # Should receive message from AMQP
      assert_receive {:basic_deliver, payload, _meta}, 5000
      assert payload == "Hello AMQP!"
    end
  end
  
  describe "PostgreSQL integration" do
    setup do
      # Get test repo
      repo = Application.get_env(:autonomous_opponent, :ecto_repos) |> hd()
      {:ok, repo: repo}
    end
    
    test "gateway persists connection events", %{repo: repo} do
      client_id = "db_test_#{:rand.uniform(1000)}"
      
      # Connect
      {:ok, _} = Gateway.connect(client_id, transport: :websocket)
      
      # Wait for async persistence
      :timer.sleep(100)
      
      # Query database
      import Ecto.Query
      
      event = repo.one(
        from e in "gateway_events",
        where: e.client_id == ^client_id and e.event_type == "connected",
        order_by: [desc: e.inserted_at],
        limit: 1
      )
      
      assert event
      assert event.transport == "websocket"
      
      # Disconnect
      Gateway.disconnect(client_id)
      :timer.sleep(100)
      
      # Verify disconnect event
      disconnect_event = repo.one(
        from e in "gateway_events",
        where: e.client_id == ^client_id and e.event_type == "disconnected",
        limit: 1
      )
      
      assert disconnect_event
    end
  end
end
```

## Testing Best Practices

### 1. Test Isolation

```elixir
# Always use unique identifiers
client_id = "test_#{inspect(self())}_#{:rand.uniform(10000)}"

# Clean up in on_exit callbacks
on_exit(fn ->
  Gateway.disconnect(client_id)
  Process.unregister(:test_process) rescue nil
end)
```

### 2. Async vs Sync Tests

```elixir
# Use async: true for independent tests
use ExUnit.Case, async: true

# Use async: false for tests that modify global state
use ExUnit.Case, async: false
```

### 3. Proper Timeouts

```elixir
# Use appropriate timeouts for async operations
assert_receive pattern, 1000  # 1 second for local operations
assert_receive pattern, 5000  # 5 seconds for network operations

# Tag long-running tests
@tag timeout: :infinity
test "load test with many connections" do
  # ...
end
```

### 4. Mock External Dependencies

```elixir
defmodule MockTransport do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    {:ok, %{responses: opts[:responses] || %{}}}
  end
  
  def handle_call({:send, message}, _from, state) do
    response = Map.get(state.responses, message.type, :ok)
    {:reply, response, state}
  end
end

# Use in tests
setup do
  {:ok, mock} = MockTransport.start_link(
    responses: %{"error" => {:error, :simulated_error}}
  )
  
  on_exit(fn -> GenServer.stop(mock) end)
  :ok
end
```

### 5. Test Data Factories

```elixir
defmodule TestFactory do
  def build_message(attrs \\ %{}) do
    %{
      type: attrs[:type] || "test_message",
      data: attrs[:data] || %{value: :rand.uniform(100)},
      timestamp: attrs[:timestamp] || DateTime.utc_now()
    }
  end
  
  def build_client(attrs \\ %{}) do
    %{
      id: attrs[:id] || "client_#{:rand.uniform(10000)}",
      transport: attrs[:transport] || :websocket,
      metadata: attrs[:metadata] || %{}
    }
  end
end
```

### 6. Property-Based Testing

```elixir
use ExUnitProperties

property "consistent hash maintains key distribution" do
  check all nodes <- list_of(string(:alphanumeric, min_length: 1), min_length: 2, max_length: 10),
            keys <- list_of(string(:alphanumeric, min_length: 1), min_length: 10, max_length: 1000) do
    
    {:ok, hash} = ConsistentHash.start_link(nodes: nodes)
    
    # Map all keys
    mapping = Map.new(keys, fn key ->
      {key, ConsistentHash.get_node(hash, key)}
    end)
    
    # All keys should map to valid nodes
    assert Enum.all?(mapping, fn {_key, node} -> node in nodes end)
    
    GenServer.stop(hash)
  end
end
```

## Common Test Patterns

### Testing Event-Driven Behavior

```elixir
test "event propagation through system" do
  # Subscribe to multiple event streams
  EventBus.subscribe(:gateway_events)
  EventBus.subscribe(:vsm_events)
  EventBus.subscribe(:metrics_events)
  
  # Trigger action
  Gateway.connect("test_client", transport: :websocket)
  
  # Assert on event sequence
  assert_receive {:event_bus, :gateway_events, %{type: :client_connected}}
  assert_receive {:event_bus, :vsm_events, %{type: :variety_input}}
  assert_receive {:event_bus, :metrics_events, %{type: :connection_count}}
end
```

### Testing Rate Limiting

```elixir
test "rate limiting per client" do
  client_id = "rate_test_#{:rand.uniform(1000)}"
  limit = 10
  
  # Send messages up to limit
  for i <- 1..limit do
    assert :ok = Router.route_message(client_id, %{index: i})
  end
  
  # Next should be rate limited
  assert {:error, :rate_limit_exceeded} = 
    Router.route_message(client_id, %{index: limit + 1})
  
  # Wait for refill
  :timer.sleep(1100)
  
  # Should work again
  assert :ok = Router.route_message(client_id, %{index: limit + 2})
end
```

### Testing Circuit Breakers

```elixir
test "circuit breaker opens on repeated failures" do
  client_id = "circuit_test_#{:rand.uniform(1000)}"
  
  # Force failures
  for _ <- 1..5 do
    MockTransport.set_response(:error)
    Router.route_message(client_id, %{type: "fail"})
  end
  
  # Circuit should be open
  assert {:error, :circuit_open} = 
    Router.route_message(client_id, %{type: "test"})
  
  # Wait for half-open state
  :timer.sleep(5000)
  
  # Reset mock to success
  MockTransport.set_response(:ok)
  
  # Should allow one request (half-open)
  assert :ok = Router.route_message(client_id, %{type: "test"})
end
```

## Troubleshooting Tests

### Common Test Failures

1. **Timeout Errors**
   ```elixir
   # Increase timeout for slow operations
   @tag timeout: 60_000
   test "slow operation" do
     # ...
   end
   ```

2. **Race Conditions**
   ```elixir
   # Add small delays for async operations
   Gateway.connect(client_id)
   :timer.sleep(50)  # Allow connection to establish
   ```

3. **Port Already in Use**
   ```elixir
   # Use dynamic ports in tests
   config :autonomous_opponent_web, AutonomousOpponentWeb.Endpoint,
     http: [port: 4002 + System.unique_integer([:positive]) |> rem(1000)]
   ```

4. **Cleanup Issues**
   ```elixir
   # Always use on_exit for cleanup
   setup do
     thing = start_something()
     on_exit(fn -> 
       stop_something(thing) 
       # Gracefully handle if already stopped
       Process.alive?(thing) && GenServer.stop(thing)
     end)
   end
   ```

### Debugging Test Failures

```elixir
# Enable detailed logging for specific test
@tag capture_log: false
test "debug this test" do
  require Logger
  Logger.debug("Test state: #{inspect(state)}")
  # ...
end

# Use IEx.pry for interactive debugging
require IEx
test "interactive debug" do
  result = some_operation()
  IEx.pry()  # Drops into IEx shell
  assert result == expected
end
```

### Test Performance Profiling

```elixir
test "profile slow test" do
  :fprof.trace([:start])
  
  # Run test code
  expensive_operation()
  
  :fprof.trace([:stop])
  :fprof.profile()
  :fprof.analyse(dest: 'test_profile.txt')
end
```

## Running Tests

### Command Line Options

```bash
# Run all tests
mix test

# Run specific test file
mix test test/mcp/gateway_test.exs

# Run specific test
mix test test/mcp/gateway_test.exs:42

# Run tests with tag
mix test --only integration

# Run tests excluding tag
mix test --exclude load_test

# Run tests in parallel
mix test --max-cases 4

# Run with coverage
mix test --cover

# Run with detailed output
mix test --trace
```

### CI/CD Integration

```yaml
# .github/workflows/test.yml
name: Test Suite
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
          
      rabbitmq:
        image: rabbitmq:3-management
        ports:
          - 5672:5672
          
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'
          
      - name: Install dependencies
        run: mix deps.get
        
      - name: Run tests
        env:
          MIX_ENV: test
        run: |
          mix test --exclude external_integration
          
      - name: Run coverage
        run: mix test --cover --export-coverage default
        
      - name: Upload coverage
        uses: codecov/codecov-action@v2
```

---

This comprehensive testing guide provides patterns and examples for thoroughly testing the MCP Gateway at all levels, from unit tests to full end-to-end scenarios.