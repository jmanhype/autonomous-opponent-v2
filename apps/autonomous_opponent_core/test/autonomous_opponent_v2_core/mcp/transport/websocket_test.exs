defmodule AutonomousOpponentV2Core.MCP.Transport.WebSocketTest do
  @moduledoc """
  Tests for the WebSocket transport implementation.
  """
  
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.MCP.Transport.WebSocket
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.Core.RateLimiter
  
  setup do
    # Subscribe to relevant events
    EventBus.subscribe(:vsm_s4_metrics)
    EventBus.subscribe(:mcp_message_received)
    
    # Start WebSocket if not already started
    case Process.whereis(WebSocket) do
      nil -> {:ok, _pid} = WebSocket.start_link()
      _pid -> :ok
    end
    
    :ok
  end
  
  describe "connection management" do
    test "registers new WebSocket connection with default options" do
      client_id = "ws_client_#{:rand.uniform(1000)}"
      socket_pid = self()
      
      assert {:ok, conn_id} = WebSocket.register_connection(socket_pid, client_id)
      assert is_binary(conn_id)
    end
    
    test "registers connection with custom options" do
      client_id = "ws_custom_#{:rand.uniform(1000)}"
      opts = [
        compression: false,
        binary: true,
        rate_limit: 50,
        metadata: %{device: "mobile"}
      ]
      
      assert {:ok, conn_id} = WebSocket.register_connection(self(), client_id, opts)
      
      # Verify connection was created with options
      state = :sys.get_state(WebSocket)
      conn = Map.get(state.connections, conn_id)
      
      assert conn.compression_enabled == false
      assert conn.binary_mode == true
      assert conn.metadata.device == "mobile"
    end
    
    test "unregisters connection and cleans up resources" do
      client_id = "ws_unreg_#{:rand.uniform(1000)}"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id)
      
      # Get rate limiter before unregister
      state = :sys.get_state(WebSocket)
      conn = Map.get(state.connections, conn_id)
      rate_limiter_ref = conn.rate_limiter_ref
      
      assert Process.alive?(rate_limiter_ref)
      
      # Unregister
      assert WebSocket.unregister_connection(conn_id) == :ok
      
      # Rate limiter should be stopped
      :timer.sleep(50)
      refute Process.alive?(rate_limiter_ref)
    end
    
    test "handles multiple connections per client" do
      client_id = "ws_multi_#{:rand.uniform(1000)}"
      
      {:ok, conn1} = WebSocket.register_connection(self(), client_id)
      {:ok, conn2} = WebSocket.register_connection(spawn(fn -> :timer.sleep(100) end), client_id)
      
      assert conn1 != conn2
      
      # Both should be tracked
      state = :sys.get_state(WebSocket)
      client_conns = Map.get(state.client_connections, client_id)
      assert length(client_conns) == 2
    end
  end
  
  describe "message handling" do
    test "processes incoming text message" do
      client_id = "ws_msg_#{:rand.uniform(1000)}"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id)
      
      message = Jason.encode!(%{
        "type" => "test_message",
        "data" => %{"value" => 42}
      })
      
      WebSocket.handle_message(conn_id, message)
      
      # Should publish to EventBus
      assert_receive {:event_bus, :mcp_message_received, event_data}
      assert event_data.conn_id == conn_id
      assert event_data.client_id == client_id
      assert event_data.type == "test_message"
      assert event_data.data["value"] == 42
      assert event_data.transport == :websocket
    end
    
    test "handles binary messages with compression" do
      client_id = "ws_binary_#{:rand.uniform(1000)}"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id, binary: true)
      
      # Create compressed message
      original = Jason.encode!(%{"type" => "compressed", "data" => %{"test" => true}})
      compressed = :zlib.compress(original)
      
      WebSocket.handle_message(conn_id, compressed)
      
      assert_receive {:event_bus, :mcp_message_received, event_data}
      assert event_data.type == "compressed"
      assert event_data.data["test"] == true
    end
    
    test "handles invalid message format" do
      client_id = "ws_invalid_#{:rand.uniform(1000)}"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id)
      
      WebSocket.handle_message(conn_id, "invalid json")
      
      # Should receive error message
      assert_receive {:ws_send, error_msg}
      error = Jason.decode!(error_msg)
      assert error["type"] == "error"
      assert error["error"] == "invalid_message"
    end
    
    test "enforces rate limiting" do
      client_id = "ws_rate_#{:rand.uniform(1000)}"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id, rate_limit: 2)
      
      # Send messages up to limit
      message = Jason.encode!(%{"type" => "test", "data" => %{}})
      
      WebSocket.handle_message(conn_id, message)
      WebSocket.handle_message(conn_id, message)
      
      # This should be rate limited
      WebSocket.handle_message(conn_id, message)
      
      # Should receive rate limit error
      assert_receive {:ws_send, error_msg}
      error = Jason.decode!(error_msg)
      assert error["error"] == "rate_limit_exceeded"
    end
  end
  
  describe "message sending" do
    test "sends message to specific client" do
      client_id = "ws_send_#{:rand.uniform(1000)}"
      {:ok, _conn_id} = WebSocket.register_connection(self(), client_id)
      
      WebSocket.send_message(client_id, %{type: "notification", data: "hello"})
      
      assert_receive {:ws_send, message}
      decoded = Jason.decode!(message)
      assert decoded["type"] == "notification"
      assert decoded["data"] == "hello"
    end
    
    test "broadcasts message to all connections" do
      # Register multiple connections
      {:ok, _} = WebSocket.register_connection(self(), "broadcast1")
      
      test_pid = self()
      spawn(fn ->
        {:ok, _} = WebSocket.register_connection(self(), "broadcast2")
        receive do
          {:ws_send, data} -> send(test_pid, {:broadcast2_received, data})
        end
      end)
      
      :timer.sleep(50)
      
      WebSocket.broadcast_message(%{type: "announcement", message: "test"})
      
      # Both should receive
      assert_receive {:ws_send, msg1}
      assert_receive {:broadcast2_received, msg2}
      
      assert Jason.decode!(msg1) == Jason.decode!(msg2)
    end
    
    test "applies compression for large messages" do
      client_id = "ws_compress_#{:rand.uniform(1000)}"
      {:ok, _conn_id} = WebSocket.register_connection(self(), client_id, compression: true)
      
      # Create large message
      large_data = String.duplicate("x", 2000)
      WebSocket.send_message(client_id, %{data: large_data})
      
      assert_receive {:ws_send, compressed}
      
      # Should be compressed (much smaller than original)
      assert byte_size(compressed) < 2000
      
      # Should decompress correctly
      decompressed = :zlib.uncompress(compressed)
      decoded = Jason.decode!(decompressed)
      assert decoded["data"] == large_data
    end
  end
  
  describe "ping/pong mechanism" do
    test "sends ping messages" do
      client_id = "ws_ping_#{:rand.uniform(1000)}"
      {:ok, _conn_id} = WebSocket.register_connection(self(), client_id)
      
      # Trigger ping manually
      send(WebSocket, :send_pings)
      
      assert_receive :ws_ping
    end
    
    test "handles pong response" do
      client_id = "ws_pong_#{:rand.uniform(1000)}"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id)
      
      # Simulate ping being sent
      send(WebSocket, :send_pings)
      :timer.sleep(50)
      
      # Send pong response
      WebSocket.handle_pong(conn_id)
      
      # Connection should still be active
      state = :sys.get_state(WebSocket)
      assert Map.has_key?(state.connections, conn_id)
    end
    
    test "disconnects on pong timeout" do
      client_id = "ws_timeout_#{:rand.uniform(1000)}"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id)
      
      # Trigger pong timeout
      send(WebSocket, {:pong_timeout, conn_id})
      
      :timer.sleep(50)
      
      # Connection should be removed
      state = :sys.get_state(WebSocket)
      refute Map.has_key?(state.connections, conn_id)
    end
  end
  
  describe "process monitoring" do
    test "cleans up when socket process dies" do
      client_id = "ws_monitor_#{:rand.uniform(1000)}"
      
      pid = spawn(fn -> 
        receive do
          :stop -> :ok
        end
      end)
      
      {:ok, conn_id} = WebSocket.register_connection(pid, client_id)
      
      # Kill the process
      Process.exit(pid, :kill)
      :timer.sleep(100)
      
      # Connection should be cleaned up
      state = :sys.get_state(WebSocket)
      refute Map.has_key?(state.connections, conn_id)
    end
  end
  
  describe "VSM integration" do
    test "forwards VSM broadcasts to WebSocket clients" do
      client_id = "ws_vsm_#{:rand.uniform(1000)}"
      {:ok, _conn_id} = WebSocket.register_connection(self(), client_id)
      
      EventBus.publish(:vsm_broadcast, %{update: "system_state"})
      
      assert_receive {:ws_send, message}
      decoded = Jason.decode!(message)
      assert decoded["type"] == "vsm_update"
      assert decoded["data"]["update"] == "system_state"
    end
    
    test "reports metrics to VSM S4" do
      client_id = "ws_metrics_#{:rand.uniform(1000)}"
      {:ok, _conn_id} = WebSocket.register_connection(self(), client_id)
      
      assert_receive {:event_bus, :vsm_s4_metrics, metrics}
      assert metrics.source == :mcp_gateway
      assert metrics.metrics.transport == :websocket
      assert metrics.metrics.active_connections > 0
    end
  end
  
  describe "statistics tracking" do
    test "tracks message and byte statistics" do
      client_id = "ws_stats_#{:rand.uniform(1000)}"
      {:ok, conn_id} = WebSocket.register_connection(self(), client_id)
      
      # Get initial stats
      initial_state = :sys.get_state(WebSocket)
      initial_sent = initial_state.stats.messages_sent
      initial_received = initial_state.stats.messages_received
      
      # Send and receive messages
      WebSocket.send_message(client_id, %{test: "data"})
      
      message = Jason.encode!(%{"type" => "test", "data" => %{}})
      WebSocket.handle_message(conn_id, message)
      
      :timer.sleep(50)
      
      # Check stats updated
      final_state = :sys.get_state(WebSocket)
      assert final_state.stats.messages_sent > initial_sent
      assert final_state.stats.messages_received > initial_received
      assert final_state.stats.bytes_sent > 0
      assert final_state.stats.bytes_received > 0
    end
  end
end