defmodule AutonomousOpponentV2Core.MCPGateway.IntegrationTest do
  use ExUnit.Case
  
  alias AutonomousOpponentV2Core.Core.{RateLimiter, Metrics, CircuitBreaker}
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.MCPGateway.{
    Supervisor,
    Router,
    ConnectionPool,
    TransportRegistry,
    HealthMonitor
  }
  alias AutonomousOpponentV2Core.MCPGateway.Transports.{HTTPSSE, WebSocket}
  
  setup do
    # Start EventBus
    {:ok, _} = start_supervised({EventBus, name: :test_event_bus})
    
    # Start core dependencies
    {:ok, _} = start_supervised({CircuitBreaker, name: :test_circuit_breaker})
    {:ok, _} = start_supervised({RateLimiter, name: :test_rate_limiter})
    {:ok, _} = start_supervised({RateLimiter, name: :mcp_gateway_limiter, bucket_size: 100})
    {:ok, _} = start_supervised({Metrics, name: :mcp_gateway_metrics})
    
    # Start MCP Gateway
    {:ok, gateway} = start_supervised({
      Supervisor,
      name: :test_gateway,
      pool_size: 10,
      hash_ring_size: 256
    })
    
    # Wait for initialization
    Process.sleep(100)
    
    %{gateway: gateway}
  end
  
  describe "MCP Gateway Integration" do
    test "all components start successfully", %{gateway: _gateway} do
      # Check that all components are running
      assert Process.whereis(TransportRegistry) != nil
      assert Process.whereis(ConnectionPool) != nil
      assert Process.whereis(Router) != nil
      assert Process.whereis(HealthMonitor) != nil
    end
    
    test "transport registry registers transports", %{gateway: _gateway} do
      # Transports should be auto-registered
      transports = TransportRegistry.list_transports()
      assert :http_sse in transports
      assert :websocket in transports
    end
    
    test "health monitor reports system status", %{gateway: _gateway} do
      status = HealthMonitor.status()
      
      assert status.overall in [:healthy, :degraded, :unhealthy]
      assert is_map(status.components)
      assert status.components[:connection_pool]
      assert status.components[:router]
      assert status.components[:transport_registry]
    end
    
    test "router handles route registration and lookup", %{gateway: _gateway} do
      # Register a test route
      {:ok, route_id} = Router.register_route("/test/path", TestIntegrationHandler)
      assert is_binary(route_id)
      
      # Get router status
      status = Router.status()
      assert status.total_routes > 0
    end
    
    test "connection pool manages connections", %{gateway: _gateway} do
      # Get pool status
      status = ConnectionPool.status()
      
      assert is_map(status.pools)
      assert status.total_connections >= 0
      assert status.waiting_queue_size >= 0
    end
    
    test "HTTP+SSE transport integration", %{gateway: _gateway} do
      # Wait for transport to register
      Process.sleep(50)
      
      # Create SSE connection
      client_ref = self()
      {:ok, conn_id} = HTTPSSE.connect(client_ref)
      
      # Should receive connection event
      assert_receive {:sse_data, data}
      assert data =~ "event: connected"
      
      # Send event
      HTTPSSE.send_event(conn_id, %{
        event: "test",
        data: %{message: "integration test"}
      })
      
      # Should receive event
      assert_receive {:sse_data, event_data}
      assert event_data =~ "integration test"
      
      # Close connection
      HTTPSSE.close(conn_id)
    end
    
    test "WebSocket transport integration", %{gateway: _gateway} do
      # Wait for transport to register
      Process.sleep(50)
      
      # Create WebSocket connection
      socket_pid = self()
      {:ok, conn_id} = WebSocket.connect(socket_pid)
      
      # Should receive welcome message
      assert_receive {:websocket_frame, :text, data}
      decoded = Jason.decode!(data)
      assert decoded["type"] == "connected"
      
      # Send message
      WebSocket.send_message(conn_id, %{
        type: "test",
        data: "integration test"
      })
      
      # Should receive message
      assert_receive {:websocket_frame, :text, msg_data}
      decoded_msg = Jason.decode!(msg_data)
      assert decoded_msg["data"] == "integration test"
      
      # Close connection
      WebSocket.close(conn_id)
      assert_receive {:websocket_frame, :close, _}
    end
    
    test "rate limiting across transports", %{gateway: _gateway} do
      # Create many connections quickly
      results = for _ <- 1..150 do
        HTTPSSE.connect(self())
      end
      
      # Some should be rate limited
      rate_limited = Enum.count(results, fn
        {:error, :rate_limited} -> true
        _ -> false
      end)
      
      assert rate_limited > 0
    end
    
    test "metrics collection", %{gateway: _gateway} do
      # Perform some operations
      HTTPSSE.connect(self())
      WebSocket.connect(self())
      
      # Get metrics
      all_metrics = Metrics.get_all_metrics(:mcp_gateway_metrics)
      
      # Should have recorded some metrics
      assert length(all_metrics) > 0
      
      # Check for specific metrics
      metric_names = Enum.map(all_metrics, fn {name, _} -> name end)
      assert Enum.any?(metric_names, &String.contains?(&1, "sse.connections"))
      assert Enum.any?(metric_names, &String.contains?(&1, "websocket.connections"))
    end
    
    test "event bus integration", %{gateway: _gateway} do
      # Subscribe to MCP events
      EventBus.subscribe(:mcp_transport_registered, :test_event_bus)
      EventBus.subscribe(:mcp_health_degraded, :test_event_bus)
      
      # Events should have been published during startup
      assert_receive {:event, :mcp_transport_registered, data}
      assert data.type in [:http_sse, :websocket]
    end
    
    test "concurrent connections stress test", %{gateway: _gateway} do
      # Create multiple connections concurrently
      tasks = for i <- 1..20 do
        Task.async(fn ->
          case rem(i, 2) do
            0 -> HTTPSSE.connect(self())
            1 -> WebSocket.connect(self())
          end
        end)
      end
      
      # Wait for all tasks
      results = Task.await_many(tasks, 5000)
      
      # Most should succeed
      successful = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      assert successful > 10
    end
  end
end

defmodule TestIntegrationHandler do
  def handle_request(_request, _connection, _backend) do
    {:ok, %{status: "success", handler: "integration_test"}}
  end
end