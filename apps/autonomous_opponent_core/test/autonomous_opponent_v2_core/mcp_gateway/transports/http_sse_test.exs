defmodule AutonomousOpponentV2Core.MCPGateway.Transports.HTTPSSETest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.MCPGateway.Transports.HTTPSSE
  alias AutonomousOpponentV2Core.MCPGateway.TransportRegistry
  alias AutonomousOpponentV2Core.Core.RateLimiter
  
  setup do
    # Start dependencies
    {:ok, _} = start_supervised({RateLimiter, name: :mcp_gateway_limiter_sse_test})
    {:ok, _} = start_supervised({TransportRegistry, name: :test_registry})
    
    {:ok, transport} = start_supervised({
      HTTPSSE,
      name: :test_sse,
      max_connections: 10,
      heartbeat_interval: 60_000,
      buffer_size: 5
    })
    
    %{transport: transport}
  end
  
  describe "connect/3" do
    test "successfully creates SSE connection", %{transport: _transport} do
      client_ref = self()
      
      assert {:ok, connection_id} = HTTPSSE.connect(:test_sse, client_ref)
      assert is_binary(connection_id)
      
      # Should receive connection event
      assert_receive {:sse_data, data}
      assert data =~ "event: connected"
    end
    
    test "respects max connections limit", %{transport: _transport} do
      # Fill up connection pool
      for _ <- 1..10 do
        {:ok, _} = HTTPSSE.connect(:test_sse, self())
      end
      
      # Next connection should fail
      assert {:error, :max_connections_reached} = HTTPSSE.connect(:test_sse, self())
    end
    
    test "handles rate limiting", %{transport: _transport} do
      # Consume all rate limit tokens
      for _ <- 1..100 do
        RateLimiter.consume(:mcp_gateway_limiter_sse_test)
      end
      
      assert {:error, :rate_limited} = HTTPSSE.connect(:test_sse, self())
    end
  end
  
  describe "send_event/3" do
    test "sends event to connected client", %{transport: _transport} do
      client_ref = self()
      {:ok, connection_id} = HTTPSSE.connect(:test_sse, client_ref)
      
      # Clear connection message
      assert_receive {:sse_data, _}
      
      # Send event
      HTTPSSE.send_event(:test_sse, connection_id, %{
        event: "test",
        data: %{message: "hello"}
      })
      
      # Should receive formatted SSE event
      assert_receive {:sse_data, data}
      assert data =~ "event: test"
      assert data =~ "data:"
      assert data =~ "hello"
    end
    
    test "handles backpressure when buffer is full", %{transport: _transport} do
      client_ref = self()
      {:ok, connection_id} = HTTPSSE.connect(:test_sse, client_ref)
      
      # Clear connection message
      assert_receive {:sse_data, _}
      
      # Fill buffer (buffer_size is 5)
      for i <- 1..6 do
        HTTPSSE.send_event(:test_sse, connection_id, %{
          event: "test",
          data: %{count: i}
        })
      end
      
      # Buffer should be full, so events are sent
      assert_received {:sse_data, _}
    end
    
    test "ignores events to non-existent connections", %{transport: _transport} do
      # Should not crash
      HTTPSSE.send_event(:test_sse, "fake-connection", %{data: "test"})
      
      # Transport should still be running
      Process.sleep(10)
      assert Process.alive?(:test_sse)
    end
  end
  
  describe "close/2" do
    test "closes connection and sends close event", %{transport: _transport} do
      client_ref = self()
      {:ok, connection_id} = HTTPSSE.connect(:test_sse, client_ref)
      
      # Clear connection message
      assert_receive {:sse_data, _}
      
      HTTPSSE.close(:test_sse, connection_id)
      
      # Should receive close event
      assert_receive {:sse_data, data}
      assert data =~ "event: close"
    end
  end
  
  describe "heartbeat" do
    test "sends heartbeat to all connections", %{transport: _transport} do
      client_ref = self()
      {:ok, _connection_id} = HTTPSSE.connect(:test_sse, client_ref)
      
      # Clear connection message
      assert_receive {:sse_data, _}
      
      # Trigger heartbeat
      send(:test_sse, :heartbeat)
      
      # Should receive heartbeat
      assert_receive {:sse_data, data}
      assert data =~ "event: heartbeat"
    end
  end
  
  describe "SSE formatting" do
    test "formats events correctly", %{transport: _transport} do
      client_ref = self()
      {:ok, connection_id} = HTTPSSE.connect(:test_sse, client_ref)
      
      # Clear connection message
      assert_receive {:sse_data, _}
      
      # Send event with all fields
      HTTPSSE.send_event(:test_sse, connection_id, %{
        event: "custom",
        data: "test message",
        id: "123",
        retry: 10000
      })
      
      assert_receive {:sse_data, data}
      
      # Check SSE format
      assert data =~ "event: custom"
      assert data =~ "id: 123"
      assert data =~ "retry: 10000"
      assert data =~ "data: test message"
      assert data =~ "\n\n"  # Double newline at end
    end
    
    test "handles multiline data", %{transport: _transport} do
      client_ref = self()
      {:ok, connection_id} = HTTPSSE.connect(:test_sse, client_ref)
      
      # Clear connection message
      assert_receive {:sse_data, _}
      
      # Send multiline data
      HTTPSSE.send_event(:test_sse, connection_id, %{
        data: "line1\nline2\nline3"
      })
      
      assert_receive {:sse_data, data}
      
      # Each line should be prefixed with "data: "
      assert data =~ "data: line1"
      assert data =~ "data: line2"
      assert data =~ "data: line3"
    end
  end
end