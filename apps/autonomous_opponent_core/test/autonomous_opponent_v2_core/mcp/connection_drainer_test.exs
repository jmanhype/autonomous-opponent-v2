defmodule AutonomousOpponentV2Core.MCP.ConnectionDrainerTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.MCP.ConnectionDrainer
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Start a new drainer for each test
    {:ok, pid} = start_supervised(ConnectionDrainer)
    %{drainer: pid}
  end
  
  describe "start_draining/1" do
    test "starts draining process successfully" do
      assert :ok = ConnectionDrainer.start_draining(timeout: 5000)
      assert ConnectionDrainer.draining?()
      refute ConnectionDrainer.accepting_connections?()
    end
    
    test "prevents double draining" do
      assert :ok = ConnectionDrainer.start_draining()
      assert {:error, :already_draining} = ConnectionDrainer.start_draining()
    end
    
    test "executes callback on completion", %{drainer: _} do
      test_pid = self()
      
      callback = fn reason ->
        send(test_pid, {:drain_complete, reason})
      end
      
      # Mock no active connections
      Registry.unregister(AutonomousOpponentV2Core.MCP.TransportRegistry, {:transport, :websocket})
      Registry.unregister(AutonomousOpponentV2Core.MCP.TransportRegistry, {:transport, :http_sse})
      
      assert :ok = ConnectionDrainer.start_draining(
        timeout: 100,
        callback: callback
      )
      
      # Should complete immediately since no connections
      assert_receive {:drain_complete, :success}, 1000
    end
    
    test "times out with remaining connections" do
      test_pid = self()
      
      callback = fn reason ->
        send(test_pid, {:drain_complete, reason})
      end
      
      # Register fake connections
      Registry.register(AutonomousOpponentV2Core.MCP.TransportRegistry, {:transport, :websocket}, nil)
      
      assert :ok = ConnectionDrainer.start_draining(
        timeout: 100,
        callback: callback
      )
      
      # Should timeout
      assert_receive {:drain_complete, :timeout}, 200
    end
  end
  
  describe "force_shutdown/0" do
    test "forces immediate shutdown" do
      # Start draining
      assert :ok = ConnectionDrainer.start_draining()
      assert ConnectionDrainer.draining?()
      
      # Force shutdown
      ConnectionDrainer.force_shutdown()
      
      # Should no longer be draining
      refute ConnectionDrainer.draining?()
    end
  end
  
  describe "connection notifications" do
    test "sends shutdown notifications via PubSub" do
      # Subscribe to notifications
      Phoenix.PubSub.subscribe(AutonomousOpponentV2.PubSub, "mcp:all")
      
      # Start draining
      assert :ok = ConnectionDrainer.start_draining(timeout: 1000)
      
      # Should receive shutdown notification
      assert_receive {:system_notification, :shutdown_pending, data}, 500
      assert data.message =~ "shutting down"
      assert is_integer(data.reconnect_after)
    end
    
    test "sends countdown notifications" do
      # Subscribe to notifications
      Phoenix.PubSub.subscribe(AutonomousOpponentV2.PubSub, "mcp:all")
      
      # Start draining with longer timeout
      assert :ok = ConnectionDrainer.start_draining(timeout: 10_000)
      
      # Should receive countdown notification
      assert_receive {:system_notification, :shutdown_countdown, data}, 6000
      assert data.message =~ "shutdown in progress"
      assert data.time_remaining_ms > 0
    end
  end
  
  describe "VSM integration" do
    test "publishes drain events to VSM" do
      # Subscribe to VSM events
      EventBus.subscribe(:vsm_s3_control)
      
      # Start draining
      assert :ok = ConnectionDrainer.start_draining(timeout: 100)
      
      # Should receive start event
      assert_receive {:event_bus, :vsm_s3_control, %{event: :connection_draining_started}}, 500
      
      # Wait for completion
      Process.sleep(150)
      
      # Should receive complete event
      assert_receive {:event_bus, :vsm_s3_control, %{event: :connection_draining_complete}}, 500
    end
  end
end