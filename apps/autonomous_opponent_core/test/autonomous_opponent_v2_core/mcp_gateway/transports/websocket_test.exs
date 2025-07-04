defmodule AutonomousOpponentV2Core.MCPGateway.Transports.WebSocketTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.MCPGateway.Transports.WebSocket
  alias AutonomousOpponentV2Core.MCPGateway.TransportRegistry
  alias AutonomousOpponentV2Core.Core.RateLimiter
  
  setup do
    # Start dependencies
    {:ok, _} = start_supervised({RateLimiter, name: :mcp_gateway_limiter_ws_test})
    {:ok, _} = start_supervised({TransportRegistry, name: :test_registry_ws})
    
    {:ok, transport} = start_supervised({
      WebSocket,
      name: :test_ws,
      max_connections: 10,
      ping_interval: 60_000,
      pong_timeout: 10_000
    })
    
    %{transport: transport}
  end
  
  describe "connect/3" do
    test "successfully creates WebSocket connection", %{transport: _transport} do
      socket_pid = self()
      
      assert {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      assert is_binary(connection_id)
      
      # Should receive welcome message
      assert_receive {:websocket_frame, :text, data}
      decoded = Jason.decode!(data)
      assert decoded["type"] == "connected"
      assert decoded["id"] == connection_id
    end
    
    test "respects max connections limit", %{transport: _transport} do
      # Fill up connection pool
      for _ <- 1..10 do
        {:ok, _} = WebSocket.connect(:test_ws, spawn(fn -> :ok end))
      end
      
      # Next connection should fail
      assert {:error, :max_connections_reached} = WebSocket.connect(:test_ws, self())
    end
    
    test "handles rate limiting", %{transport: _transport} do
      # Consume all rate limit tokens
      for _ <- 1..100 do
        RateLimiter.consume(:mcp_gateway_limiter_ws_test)
      end
      
      assert {:error, :rate_limited} = WebSocket.connect(:test_ws, self())
    end
  end
  
  describe "handle_message/3" do
    test "handles request messages", %{transport: _transport} do
      socket_pid = self()
      {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Clear welcome message
      assert_receive {:websocket_frame, :text, _}
      
      # Send request
      request = %{
        "type" => "request",
        "method" => "echo",
        "params" => %{"message" => "hello"},
        "id" => "req-123"
      }
      
      WebSocket.handle_message(:test_ws, connection_id, request)
      
      # Should receive response (eventually)
      # Note: In test, the actual processing is async
      Process.sleep(10)
    end
    
    test "handles event messages", %{transport: _transport} do
      socket_pid = self()
      {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Clear welcome message
      assert_receive {:websocket_frame, :text, _}
      
      # Send event
      event = %{
        "type" => "event",
        "event" => "user_action",
        "data" => %{"action" => "click"}
      }
      
      WebSocket.handle_message(:test_ws, connection_id, event)
      
      # Should not crash
      Process.sleep(10)
      assert Process.alive?(:test_ws)
    end
    
    test "handles pong messages", %{transport: _transport} do
      socket_pid = self()
      {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Send pong
      WebSocket.handle_message(:test_ws, connection_id, %{"type" => "pong"})
      
      # Should update last pong time internally
      Process.sleep(10)
      assert Process.alive?(:test_ws)
    end
    
    test "handles invalid JSON", %{transport: _transport} do
      socket_pid = self()
      {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Clear welcome message
      assert_receive {:websocket_frame, :text, _}
      
      # Send invalid message
      WebSocket.handle_message(:test_ws, connection_id, "invalid json")
      
      # Should receive error
      assert_receive {:websocket_frame, :text, data}
      decoded = Jason.decode!(data)
      assert decoded["type"] == "error"
      assert decoded["error"] == :invalid_json
    end
  end
  
  describe "send_message/3" do
    test "sends message to connected client", %{transport: _transport} do
      socket_pid = self()
      {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Clear welcome message
      assert_receive {:websocket_frame, :text, _}
      
      # Send message
      message = %{
        type: "notification",
        data: %{alert: "test"}
      }
      
      WebSocket.send_message(:test_ws, connection_id, message)
      
      # Should receive formatted message
      assert_receive {:websocket_frame, :text, data}
      decoded = Jason.decode!(data)
      assert decoded["type"] == "notification"
      assert decoded["data"]["alert"] == "test"
      assert decoded["timestamp"]
    end
    
    test "ignores messages to non-existent connections", %{transport: _transport} do
      # Should not crash
      WebSocket.send_message(:test_ws, "fake-connection", %{data: "test"})
      
      # Transport should still be running
      Process.sleep(10)
      assert Process.alive?(:test_ws)
    end
  end
  
  describe "close/3" do
    test "closes connection with normal reason", %{transport: _transport} do
      socket_pid = self()
      {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Clear welcome message
      assert_receive {:websocket_frame, :text, _}
      
      WebSocket.close(:test_ws, connection_id, :normal)
      
      # Should receive close frame
      assert_receive {:websocket_frame, :close, {1000, "normal"}}
    end
    
    test "closes connection with custom reason", %{transport: _transport} do
      socket_pid = self()
      {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Clear welcome message
      assert_receive {:websocket_frame, :text, _}
      
      WebSocket.close(:test_ws, connection_id, :going_away)
      
      # Should receive close frame with appropriate code
      assert_receive {:websocket_frame, :close, {1001, "going_away"}}
    end
  end
  
  describe "ping/pong" do
    test "sends ping to all connections", %{transport: _transport} do
      socket_pid = self()
      {:ok, _connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Clear welcome message
      assert_receive {:websocket_frame, :text, _}
      
      # Trigger ping
      send(:test_ws, :ping_all)
      
      # Should receive ping frame
      assert_receive {:websocket_frame, :ping, ""}
    end
    
    test "handles process death", %{transport: _transport} do
      # Create a process that will die
      socket_pid = spawn(fn -> 
        receive do
          :stop -> :ok
        end
      end)
      
      {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Kill the process
      Process.exit(socket_pid, :kill)
      
      # Transport should handle the DOWN message
      Process.sleep(50)
      assert Process.alive?(:test_ws)
      
      # Connection should be removed
      WebSocket.send_message(:test_ws, connection_id, %{test: "message"})
      
      # Should not receive anything (connection gone)
      refute_receive {:websocket_frame, _, _}, 100
    end
  end
  
  describe "message validation" do
    test "validates message type", %{transport: _transport} do
      socket_pid = self()
      {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Clear welcome message
      assert_receive {:websocket_frame, :text, _}
      
      # Send message without type
      WebSocket.handle_message(:test_ws, connection_id, %{"data" => "test"})
      
      # Should receive error
      assert_receive {:websocket_frame, :text, data}
      decoded = Jason.decode!(data)
      assert decoded["type"] == "error"
      assert decoded["error"] == :missing_or_invalid_type
    end
    
    test "validates message type values", %{transport: _transport} do
      socket_pid = self()
      {:ok, connection_id} = WebSocket.connect(:test_ws, socket_pid)
      
      # Clear welcome message
      assert_receive {:websocket_frame, :text, _}
      
      # Send message with invalid type
      WebSocket.handle_message(:test_ws, connection_id, %{"type" => "invalid"})
      
      # Should receive error
      assert_receive {:websocket_frame, :text, data}
      decoded = Jason.decode!(data)
      assert decoded["type"] == "error"
      assert decoded["error"] == :missing_or_invalid_type
    end
  end
end