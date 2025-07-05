defmodule AutonomousOpponentV2Web.WebGatewayChannelTest do
  @moduledoc """
  Tests for the Web Gateway WebSocket channel.
  """
  
  use AutonomousOpponentV2Web.ChannelCase
  
  alias AutonomousOpponentV2Web.WebGatewayChannel
  alias AutonomousOpponentV2Core.WebGateway.Transport.WebSocket
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Mock WebSocket transport
    test_pid = self()
    
    mock_pid = spawn(fn ->
      Process.register(self(), WebSocket)
      
      # Handle multiple registration requests
      Stream.repeatedly(fn ->
        receive do
          {:"$gen_call", from, {:register, _socket_pid, client_id, _opts}} ->
            GenServer.reply(from, {:ok, "conn_#{client_id}"})
            
          {:"$gen_cast", _, {:handle_message, conn_id, message}} ->
            send(test_pid, {:message_handled, conn_id, message})
            
          {:"$gen_cast", _, {:pong_received, conn_id}} ->
            send(test_pid, {:pong_received, conn_id})
            
          _ ->
            :ok
        end
      end)
      |> Enum.take(100)
    end)
    
    on_exit(fn ->
      Process.exit(mock_pid, :kill)
      Process.unregister(WebSocket) rescue nil
    end)
    
    {:ok, socket} = connect(AutonomousOpponentV2Web.WebGatewaySocket, %{})
    
    %{socket: socket}
  end
  
  describe "join/3" do
    test "successfully joins mcp:gateway channel", %{socket: socket} do
      assert {:ok, socket} = subscribe_and_join(socket, WebGatewayChannel, "web_gateway:gateway", %{})
      
      # Should have connection info
      assert socket.assigns.client_id != nil
      assert socket.assigns.connection_id != nil
      assert socket.assigns.joined_at != nil
    end
    
    test "receives welcome message on join", %{socket: socket} do
      {:ok, _socket} = subscribe_and_join(socket, WebGatewayChannel, "mcp:gateway", %{})
      
      assert_push "connected", %{
        client_id: client_id,
        connection_id: connection_id,
        transport: "websocket"
      }
      
      assert is_binary(client_id)
      assert is_binary(connection_id)
    end
    
    test "accepts custom client_id", %{socket: socket} do
      custom_id = "custom_client_123"
      
      {:ok, socket} = subscribe_and_join(socket, WebGatewayChannel, "mcp:gateway", %{
        "client_id" => custom_id
      })
      
      assert socket.assigns.client_id == custom_id
    end
    
    test "configures connection options", %{socket: socket} do
      params = %{
        "client_id" => "options_client",
        "compression" => false,
        "binary" => true,
        "rate_limit" => 50
      }
      
      {:ok, _socket} = subscribe_and_join(socket, WebGatewayChannel, "mcp:gateway", params)
      
      # WebSocket should have received these options
      # (Would verify in integration test with real WebSocket)
    end
  end
  
  describe "handle_in/3 - message" do
    setup %{socket: socket} do
      {:ok, socket} = subscribe_and_join(socket, WebGatewayChannel, "mcp:gateway")
      %{socket: socket, conn_id: socket.assigns.connection_id}
    end
    
    test "handles incoming message", %{socket: socket, conn_id: conn_id} do
      payload = %{"type" => "test", "data" => %{"value" => 42}}
      
      ref = push(socket, "message", payload)
      assert_reply ref, :ok, %{received: true}
      
      # WebSocket should handle the message
      assert_receive {:message_handled, ^conn_id, message}
      assert Jason.decode!(message) == payload
    end
    
    test "acknowledges message receipt", %{socket: socket} do
      ref = push(socket, "message", %{"test" => "data"})
      assert_reply ref, :ok, %{received: true}
    end
  end
  
  describe "handle_in/3 - ping/pong" do
    setup %{socket: socket} do
      {:ok, socket} = subscribe_and_join(socket, WebGatewayChannel, "mcp:gateway")
      %{socket: socket, conn_id: socket.assigns.connection_id}
    end
    
    test "responds to ping with pong", %{socket: socket} do
      ref = push(socket, "ping", %{})
      
      assert_reply ref, :ok, %{
        type: "pong",
        timestamp: timestamp
      }
      
      assert is_binary(timestamp)
    end
    
    test "handles pong from client", %{socket: socket, conn_id: conn_id} do
      push(socket, "pong", %{})
      
      # WebSocket should receive pong
      assert_receive {:pong_received, ^conn_id}
    end
  end
  
  describe "handle_in/3 - subscriptions" do
    setup %{socket: socket} do
      {:ok, socket} = subscribe_and_join(socket, WebGatewayChannel, "mcp:gateway")
      %{socket: socket}
    end
    
    test "subscribes to specific events", %{socket: socket} do
      events = ["trade_updates", "price_alerts"]
      
      ref = push(socket, "subscribe", %{"events" => events})
      assert_reply ref, :ok, %{subscribed: ^events}
      
      # Should track subscriptions
      assert socket.assigns.subscriptions == events
    end
    
    test "unsubscribes from events", %{socket: socket} do
      # First subscribe
      events = ["event1", "event2", "event3"]
      ref1 = push(socket, "subscribe", %{"events" => events})
      assert_reply ref1, :ok, _
      
      # Then unsubscribe from some
      unsubscribe = ["event1", "event3"]
      ref2 = push(socket, "unsubscribe", %{"events" => unsubscribe})
      assert_reply ref2, :ok, %{unsubscribed: ^unsubscribe}
      
      # Should only have event2 left
      assert socket.assigns.subscriptions == ["event2"]
    end
  end
  
  describe "EventBus integration" do
    setup %{socket: socket} do
      {:ok, socket} = subscribe_and_join(socket, WebGatewayChannel, "mcp:gateway")
      %{socket: socket, client_id: socket.assigns.client_id}
    end
    
    test "forwards client-specific events", %{client_id: client_id} do
      # Publish event for this client
      EventBus.publish({:mcp_client_events, client_id}, %{
        type: "notification",
        message: "Hello client"
      })
      
      assert_push "client_event", %{
        type: "notification",
        message: "Hello client"
      }
    end
    
    test "forwards subscribed event types", %{socket: socket} do
      # Subscribe to event type
      push(socket, "subscribe", %{"events" => ["market_data"]})
      
      # Publish event of that type
      EventBus.publish({:mcp_event_type, "market_data"}, %{
        symbol: "BTC",
        price: 50000
      })
      
      assert_push "market_data", %{
        symbol: "BTC",
        price: 50000
      }
    end
  end
  
  describe "direct messaging" do
    setup %{socket: socket} do
      {:ok, socket} = subscribe_and_join(socket, WebGatewayChannel, "mcp:gateway")
      %{socket: socket}
    end
    
    test "receives direct messages from transport", %{socket: _socket} do
      # Simulate message from WebSocket transport
      send(self(), {:ws_send, %{direct: "message"}})
      
      assert_push "message", %{direct: "message"}
    end
    
    test "receives ping from transport", %{socket: _socket} do
      # Simulate ping from transport
      send(self(), :ws_ping)
      
      assert_push "ping", %{timestamp: timestamp}
      assert is_binary(timestamp)
    end
  end
  
  describe "disconnection handling" do
    setup %{socket: socket} do
      {:ok, socket} = subscribe_and_join(socket, WebGatewayChannel, "mcp:gateway")
      %{socket: socket}
    end
    
    test "cleans up on disconnect", %{socket: socket} do
      # Get connection info before disconnect
      conn_id = socket.assigns.connection_id
      client_id = socket.assigns.client_id
      
      # Mock unregister
      test_pid = self()
      spawn(fn ->
        receive do
          {:"$gen_cast", _, {:unregister, ^conn_id}} ->
            send(test_pid, :unregistered)
        end
      end)
      
      # Disconnect
      Process.unlink(socket.channel_pid)
      ref = leave(socket)
      assert_reply ref, :ok
      
      # Should unregister from WebSocket
      # (In real scenario, terminate/2 would be called)
    end
  end
  
  describe "error scenarios" do
    test "handles WebSocket registration failure", %{socket: socket} do
      # Replace mock to return error
      Process.unregister(WebSocket)
      
      spawn(fn ->
        Process.register(self(), WebSocket)
        
        receive do
          {:"$gen_call", from, {:register, _, _, _}} ->
            GenServer.reply(from, {:error, :registration_failed})
        end
      end)
      
      :timer.sleep(10)
      
      # Should fail to join
      assert {:error, %{reason: "connection_failed"}} = 
        subscribe_and_join(socket, WebGatewayChannel, "mcp:gateway")
    end
  end
end