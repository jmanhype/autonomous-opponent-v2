defmodule AutonomousOpponentV2Core.WebGateway.IntegrationTest do
  @moduledoc """
  Integration tests for the complete Web Gateway system including
  VSM integration, load testing, and end-to-end scenarios.
  """
  
  use ExUnit.Case
  
  alias AutonomousOpponentV2Core.WebGateway.{Gateway, Transport.Router}
  alias AutonomousOpponentV2Core.WebGateway.Transport.{HTTPSSE, WebSocket}
  alias AutonomousOpponentV2Core.WebGateway.Pool.ConnectionPool
  alias AutonomousOpponentV2Core.WebGateway.LoadBalancer.ConsistentHash
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM
  
  @tag :integration
  
  setup_all do
    # Ensure all systems are started
    Application.ensure_all_started(:autonomous_opponent_core)
    :ok
  end
  
  setup do
    # Subscribe to relevant events
    EventBus.subscribe(:vsm_s4_metrics)
    EventBus.subscribe(:vsm_algedonic)
    EventBus.subscribe(:web_gateway_failover)
    EventBus.subscribe(:web_gateway_message_received)
    
    :ok
  end
  
  describe "end-to-end message flow" do
    test "message flows from client through gateway to VSM" do
      client_id = "e2e_client_#{:rand.uniform(1000)}"
      
      # Register WebSocket connection
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id)
      
      # Send message through WebSocket
      message = %{"type" => "test_message", "data" => %{"value" => 42}}
      WebSocket.handle_message(conn_id, Jason.encode!(message))
      
      # Should receive in Web Gateway message handler
      assert_receive {:event_bus, :web_gateway_message_received, event}
      assert event.client_id == client_id
      assert event.type == "test_message"
      assert event.data["value"] == 42
      
      # Should trigger VSM metrics update
      assert_receive {:event_bus, :vsm_s4_metrics, metrics}
      assert metrics.source == :web_gateway
    end
    
    test "VSM broadcasts reach connected clients" do
      client_id = "vsm_broadcast_client_#{:rand.uniform(1000)}"
      
      # Register both transports
      {:ok, _} = HTTPSSE.register_connection(self(), client_id)
      {:ok, _} = WebSocket.register_connection(self(), client_id)
      
      # VSM publishes update
      EventBus.publish(:vsm_broadcast, %{
        type: "system_update",
        data: %{status: "optimal", timestamp: DateTime.utc_now()}
      })
      
      # Should receive on both transports
      assert_receive {:sse_event, sse_data}
      assert sse_data =~ "vsm_update"
      
      assert_receive {:ws_send, ws_data}
      decoded = Jason.decode!(ws_data)
      assert decoded["type"] == "vsm_update"
      assert decoded["data"]["type"] == "system_update"
    end
  end
  
  describe "load balancing behavior" do
    test "distributes clients across transport nodes" do
      # Add transport nodes to hash ring
      ConsistentHash.add_node(:http_sse, 1)
      ConsistentHash.add_node(:websocket, 1)
      
      # Create multiple clients
      client_distributions = for i <- 1..20 do
        client_id = "load_client_#{i}"
        route = Router.get_route(client_id)
        {client_id, route.primary_transport}
      end
      
      # Check distribution
      grouped = Enum.group_by(client_distributions, fn {_, transport} -> transport end)
      
      # Both transports should have clients
      assert map_size(grouped) == 2
      assert length(grouped[:http_sse] || []) > 0
      assert length(grouped[:websocket] || []) > 0
    end
    
    test "maintains session affinity" do
      client_id = "affinity_client"
      
      # Get initial route
      route1 = Router.get_route(client_id)
      
      # Multiple requests should get same route
      route2 = Router.get_route(client_id)
      route3 = Router.get_route(client_id)
      
      assert route1.primary_transport == route2.primary_transport
      assert route2.primary_transport == route3.primary_transport
    end
  end
  
  describe "concurrent connection handling" do
    @tag :load_test
    test "handles many concurrent connections" do
      # Create concurrent connections
      tasks = for i <- 1..50 do
        Task.async(fn ->
          client_id = "concurrent_#{i}"
          
          # Randomly choose transport
          if :rand.uniform() > 0.5 do
            HTTPSSE.register_connection(self(), client_id)
          else
            WebSocket.register_connection(self(), client_id)
          end
        end)
      end
      
      # Wait for all to complete
      results = Task.await_many(tasks, 5000)
      
      # All should succeed
      Enum.each(results, fn result ->
        assert {:ok, _conn_id} = result
      end)
      
      # Check pool stats
      stats = ConnectionPool.get_stats()
      assert stats.checked_out <= stats.pool_size + stats.overflow
    end
    
    @tag :load_test
    test "handles high message throughput" do
      client_id = "throughput_client"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id)
      
      # Send many messages rapidly
      message_count = 100
      
      for i <- 1..message_count do
        message = Jason.encode!(%{
          "type" => "load_test",
          "data" => %{"sequence" => i}
        })
        WebSocket.handle_message(conn_id, message)
      end
      
      # Should receive all messages
      received = for _ <- 1..message_count do
        assert_receive {:event_bus, :web_gateway_message_received, _}, 1000
        1
      end
      
      assert length(received) == message_count
    end
  end
  
  describe "failure recovery" do
    test "automatic failover between transports" do
      client_id = "failover_client"
      
      # Register both transports
      {:ok, _} = HTTPSSE.register_connection(self(), client_id)
      {:ok, _} = WebSocket.register_connection(self(), client_id)
      
      # Get initial route
      route = Router.get_route(client_id)
      initial_primary = route.primary_transport
      
      # Simulate failures on primary
      for _ <- 1..3 do
        Router.report_failure(client_id, initial_primary, :connection_error)
      end
      
      # Should trigger failover
      assert_receive {:event_bus, :mcp_failover, failover_event}
      assert failover_event.client_id == client_id
      
      # Route message - should use fallback
      Router.route_message(client_id, %{test: "after_failover"})
      
      # Should still receive message
      assert_receive msg when elem(msg, 0) in [:sse_event, :ws_send], 1000
    end
    
    test "connection pool recovery from exhaustion" do
      # Exhaust pool
      workers = for i <- 1..10 do
        case ConnectionPool.checkout("exhaust_#{i}", "client_#{i}") do
          {:ok, worker} -> worker
          {:error, :pool_timeout} -> nil
        end
      end
      |> Enum.filter(&(&1 != nil))
      
      # Pool should be under pressure
      health = ConnectionPool.health_check()
      assert health in [:warning, :critical]
      
      # Return half the workers
      workers
      |> Enum.take(div(length(workers), 2))
      |> Enum.each(&ConnectionPool.checkin/1)
      
      # Health should improve
      health = ConnectionPool.health_check()
      assert health in [:healthy, :warning]
      
      # Return remaining
      workers
      |> Enum.drop(div(length(workers), 2))
      |> Enum.each(&ConnectionPool.checkin/1)
    end
  end
  
  describe "VSM integration" do
    test "gateway reports variety metrics to S4" do
      # Generate some activity
      client_id = "vsm_metrics_client"
      {:ok, _} = WebSocket.register_connection(self(), client_id)
      
      # Send messages
      for i <- 1..5 do
        Router.route_message(client_id, %{test: i})
      end
      
      # Should receive S4 metrics
      assert_receive {:event_bus, :vsm_s4_metrics, metrics}, 5000
      assert metrics.source == :web_gateway
      assert is_map(metrics.metrics)
    end
    
    test "critical failures trigger algedonic signals" do
      # Simulate all transports down
      EventBus.publish(:transport_status, %{transport: :http_sse, status: :unhealthy})
      EventBus.publish(:transport_status, %{transport: :websocket, status: :unhealthy})
      
      # Trigger health check
      send(Router, :health_check)
      
      # Should receive algedonic signal
      assert_receive {:event_bus, :vsm_algedonic, signal}, 1000
      assert signal.type == :pain
      assert signal.severity == :critical
      assert signal.reason == :all_transports_down
    end
    
    test "variety flow through VSM channels" do
      client_id = "variety_client"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id)
      
      # Subscribe to variety channel events
      EventBus.subscribe(:vsm_variety_flow)
      
      # Send message with high variety
      message = %{
        "type" => "complex_request",
        "data" => %{
          "parameters" => Enum.map(1..10, &%{id: &1, value: :rand.uniform()}),
          "options" => %{mode: "advanced", depth: 5}
        }
      }
      
      WebSocket.handle_message(conn_id, Jason.encode!(message))
      
      # Should flow through VSM variety channels
      assert_receive {:event_bus, :web_gateway_message_received, _}
      
      # VSM should process variety
      # (This would be more detailed with full VSM implementation)
    end
  end
  
  describe "monitoring and observability" do
    test "comprehensive metrics collection" do
      # Generate various activities
      client_id = "monitor_client"
      
      # SSE connection
      {:ok, _} = HTTPSSE.register_connection(self(), client_id)
      HTTPSSE.send_event(client_id, "test", %{data: 1})
      
      # WebSocket connection
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id)
      WebSocket.handle_message(conn_id, Jason.encode!(%{"type" => "test", "data" => %{}}))
      
      # Route messages
      Router.route_message(client_id, %{routed: true})
      
      # Collect metrics from all components
      :timer.sleep(100)
      
      # Gateway metrics
      assert_receive {:event_bus, :vsm_s4_metrics, gateway_metrics}
      
      # Pool health
      pool_health = ConnectionPool.health_check()
      assert pool_health == :healthy
      
      # Ring state
      ring_state = ConsistentHash.get_ring_state()
      assert is_map(ring_state)
    end
  end
  
  describe "security and rate limiting" do
    test "enforces rate limits per connection" do
      client_id = "rate_limit_client"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id, rate_limit: 5)
      
      # Send messages up to limit
      for i <- 1..5 do
        message = Jason.encode!(%{"type" => "test", "data" => %{seq: i}})
        WebSocket.handle_message(conn_id, message)
      end
      
      # Should receive all 5
      for _ <- 1..5 do
        assert_receive {:event_bus, :web_gateway_message_received, _}
      end
      
      # Next message should be rate limited
      WebSocket.handle_message(conn_id, Jason.encode!(%{"type" => "test", "data" => %{}}))
      
      # Should receive rate limit error
      assert_receive {:ws_send, error_msg}
      error = Jason.decode!(error_msg)
      assert error["error"] == "rate_limit_exceeded"
      
      # Should trigger algedonic signal
      assert_receive {:event_bus, :vsm_algedonic, signal}
      assert signal.severity == :medium
      assert {:rate_limit_exceeded, ^conn_id} = signal.reason
    end
  end
end