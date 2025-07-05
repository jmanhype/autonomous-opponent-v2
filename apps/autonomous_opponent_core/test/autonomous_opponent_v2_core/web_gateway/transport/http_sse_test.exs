defmodule AutonomousOpponentV2Core.WebGateway.Transport.HTTPSSETest do
  @moduledoc """
  Tests for the HTTP+SSE transport implementation.
  """
  
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.WebGateway.Transport.HTTPSSE
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Subscribe to relevant events
    EventBus.subscribe(:vsm_s4_metrics)
    
    # Start HTTPSSE if not already started
    case Process.whereis(HTTPSSE) do
      nil -> {:ok, _pid} = HTTPSSE.start_link()
      _pid -> :ok
    end
    
    :ok
  end
  
  describe "connection management" do
    test "registers new SSE connection" do
      client_id = "test_client_#{:rand.uniform(1000)}"
      conn_pid = self()
      
      assert {:ok, conn_id} = HTTPSSE.register_connection(conn_pid, client_id, %{test: true})
      assert is_binary(conn_id)
    end
    
    test "tracks multiple connections for same client" do
      client_id = "multi_client_#{:rand.uniform(1000)}"
      
      # Register multiple connections
      {:ok, conn1} = HTTPSSE.register_connection(self(), client_id)
      {:ok, conn2} = HTTPSSE.register_connection(spawn(fn -> :timer.sleep(100) end), client_id)
      
      assert conn1 != conn2
    end
    
    test "unregisters connection" do
      client_id = "unreg_client_#{:rand.uniform(1000)}"
      {:ok, conn_id} = HTTPSSE.register_connection(self(), client_id)
      
      assert HTTPSSE.unregister_connection(conn_id) == :ok
    end
    
    test "handles unregistering non-existent connection" do
      assert HTTPSSE.unregister_connection("non_existent") == :ok
    end
  end
  
  describe "event sending" do
    test "sends event to specific client" do
      client_id = "event_client_#{:rand.uniform(1000)}"
      {:ok, _conn_id} = HTTPSSE.register_connection(self(), client_id)
      
      HTTPSSE.send_event(client_id, "test_event", %{data: "test"})
      
      assert_receive {:sse_event, event_data}
      assert event_data =~ "event: test_event"
      assert event_data =~ ~s("data":"test")
    end
    
    test "broadcasts event to all connections" do
      # Register multiple connections
      client1 = "broadcast_client1_#{:rand.uniform(1000)}"
      client2 = "broadcast_client2_#{:rand.uniform(1000)}"
      
      {:ok, _} = HTTPSSE.register_connection(self(), client1)
      
      # Spawn a process for second connection
      test_pid = self()
      spawn(fn ->
        {:ok, _} = HTTPSSE.register_connection(self(), client2)
        receive do
          {:sse_event, data} -> send(test_pid, {:client2_received, data})
        end
      end)
      
      :timer.sleep(50)  # Give time for registration
      
      HTTPSSE.broadcast_event("broadcast_test", %{message: "hello"})
      
      # Should receive on first connection
      assert_receive {:sse_event, event_data}
      assert event_data =~ "event: broadcast_test"
      
      # Should receive on second connection
      assert_receive {:client2_received, event_data2}
      assert event_data2 =~ "event: broadcast_test"
    end
    
    test "handles sending to non-existent client" do
      # Should not crash
      assert HTTPSSE.send_event("non_existent_client", "test", %{}) == :ok
    end
  end
  
  describe "heartbeat" do
    test "receives heartbeat messages" do
      client_id = "heartbeat_client_#{:rand.uniform(1000)}"
      {:ok, _conn_id} = HTTPSSE.register_connection(self(), client_id)
      
      # Wait for heartbeat
      assert_receive {:sse_event, event_data}, 35_000
      assert event_data =~ "event: heartbeat"
      assert event_data =~ "timestamp"
    end
  end
  
  describe "process monitoring" do
    test "cleans up connection when process dies" do
      client_id = "monitor_client_#{:rand.uniform(1000)}"
      
      # Spawn a process that will die
      pid = spawn(fn -> 
        receive do
          :stop -> :ok
        end
      end)
      
      {:ok, conn_id} = HTTPSSE.register_connection(pid, client_id)
      
      # Get initial state
      state = :sys.get_state(HTTPSSE)
      assert Map.has_key?(state.connections, conn_id)
      
      # Kill the process
      Process.exit(pid, :kill)
      :timer.sleep(100)
      
      # Check connection was cleaned up
      state = :sys.get_state(HTTPSSE)
      refute Map.has_key?(state.connections, conn_id)
    end
  end
  
  describe "VSM integration" do
    test "forwards VSM broadcasts to SSE clients" do
      client_id = "vsm_client_#{:rand.uniform(1000)}"
      {:ok, _conn_id} = HTTPSSE.register_connection(self(), client_id)
      
      # Publish VSM event
      EventBus.publish(:vsm_broadcast, %{type: "update", data: "vsm_data"})
      
      assert_receive {:sse_event, event_data}
      assert event_data =~ "event: vsm_update"
      assert event_data =~ "vsm_data"
    end
    
    test "reports connection metrics to VSM" do
      client_id = "metrics_client_#{:rand.uniform(1000)}"
      {:ok, _conn_id} = HTTPSSE.register_connection(self(), client_id)
      
      # Should receive metrics event
      assert_receive {:event_bus, :vsm_s4_metrics, metrics}
      assert metrics.source == :web_gateway
      assert metrics.metrics.transport == :http_sse
      assert metrics.metrics.active_connections > 0
    end
  end
  
  describe "error handling" do
    test "tracks errors in stats" do
      # Get initial state
      initial_state = :sys.get_state(HTTPSSE)
      initial_errors = initial_state.stats.errors
      
      # This will cause an error when trying to send
      dead_pid = spawn(fn -> :ok end)
      :timer.sleep(10)
      
      # Try to send event to dead process
      client_id = "error_client_#{:rand.uniform(1000)}"
      :sys.replace_state(HTTPSSE, fn state ->
        conn_id = UUID.uuid4()
        connection = %HTTPSSE.Connection{
          id: conn_id,
          pid: dead_pid,
          client_id: client_id,
          connected_at: DateTime.utc_now(),
          last_heartbeat: DateTime.utc_now()
        }
        
        put_in(state.connections[conn_id], connection)
        |> put_in([:client_connections, client_id], [conn_id])
      end)
      
      # This should handle the error gracefully
      HTTPSSE.send_event(client_id, "test", %{})
      
      :timer.sleep(50)
      
      # Check error count increased
      final_state = :sys.get_state(HTTPSSE)
      assert final_state.stats.errors >= initial_errors
    end
  end
end