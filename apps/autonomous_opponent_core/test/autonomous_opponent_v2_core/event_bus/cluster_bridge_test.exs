defmodule AutonomousOpponentV2Core.EventBus.ClusterBridgeTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.EventBus.ClusterBridge
  
  @moduletag :distributed
  
  setup do
    # Ensure we have a unique node name for each test
    node_name = :"test_#{System.unique_integer([:positive])}@127.0.0.1"
    
    # Start distributed Erlang
    case Node.start(node_name) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      error -> flunk("Failed to start node: #{inspect(error)}")
    end
    
    # Set cookie for node communication
    Node.set_cookie(:test_cookie)
    
    on_exit(fn -> 
      # Clean shutdown
      Node.stop()
    end)
    
    {:ok, %{main_node: node_name}}
  end
  
  describe "basic clustering" do
    test "can add and remove nodes from cluster", %{main_node: main_node} do
      # Start ClusterBridge
      {:ok, _pid} = ClusterBridge.start_link()
      
      # Add a node
      assert :ok = ClusterBridge.add_node(:"remote@127.0.0.1")
      
      # Check status
      status = ClusterBridge.cluster_status()
      assert main_node == status.node_id
      assert :"remote@127.0.0.1" in status.active_nodes
      
      # Remove the node
      assert :ok = ClusterBridge.remove_node(:"remote@127.0.0.1")
      
      # Verify removal
      status = ClusterBridge.cluster_status()
      refute :"remote@127.0.0.1" in status.active_nodes
    end
    
    test "cannot add self as cluster node" do
      {:ok, _pid} = ClusterBridge.start_link()
      
      status = ClusterBridge.cluster_status()
      assert {:error, :self_node} = ClusterBridge.add_node(status.node_id)
    end
  end
  
  describe "circuit breaker" do
    test "opens circuit after threshold failures" do
      {:ok, _pid} = ClusterBridge.start_link()
      
      # Add a non-existent node
      ClusterBridge.add_node(:"nonexistent@127.0.0.1")
      
      # Simulate multiple failures by sending events
      for _ <- 1..6 do
        send(ClusterBridge, {:replication_failure, :"nonexistent@127.0.0.1"})
        Process.sleep(10)
      end
      
      # Check circuit breaker state
      status = ClusterBridge.cluster_status()
      breaker = status.circuit_breakers[:"nonexistent@127.0.0.1"]
      assert breaker.state == :open
      assert breaker.failure_count >= 5
    end
  end
  
  describe "event replication" do
    @tag :skip
    test "events are replicated across nodes" do
      # This test requires actual distributed nodes
      # Shown here for demonstration purposes
      
      # Start main node components
      {:ok, _} = EventBus.start_link()
      {:ok, _} = ClusterBridge.start_link()
      
      # Start slave node
      {:ok, slave} = :slave.start('127.0.0.1', :test_slave, '-setcookie test_cookie')
      
      # Start components on slave
      :rpc.call(slave, EventBus, :start_link, [])
      :rpc.call(slave, ClusterBridge, :start_link, [[auto_discovery: false]])
      
      # Connect nodes
      ClusterBridge.add_node(slave)
      :rpc.call(slave, ClusterBridge, :add_node, [node()])
      
      # Set up listener on slave
      test_pid = self()
      :rpc.call(slave, EventBus, :subscribe, [:test_event, fn event ->
        send(test_pid, {:received_on_slave, event})
      end])
      
      # Publish event on main node
      EventBus.publish(:test_event, %{data: "cross-node test"})
      
      # Verify receipt on slave
      assert_receive {:received_on_slave, event}, 1000
      assert event.data == %{data: "cross-node test"}
      
      # Cleanup
      :slave.stop(slave)
    end
  end
  
  describe "node monitoring" do
    test "detects nodeup events" do
      {:ok, pid} = ClusterBridge.start_link(auto_discovery: true)
      
      # Simulate nodeup
      send(pid, {:nodeup, :"new_node@127.0.0.1", []})
      Process.sleep(50)
      
      status = ClusterBridge.cluster_status()
      assert :"new_node@127.0.0.1" in status.active_nodes
    end
    
    test "handles nodedown events" do
      {:ok, pid} = ClusterBridge.start_link()
      
      # Add node first
      ClusterBridge.add_node(:"remote@127.0.0.1")
      
      # Simulate nodedown
      send(pid, {:nodedown, :"remote@127.0.0.1", []})
      Process.sleep(50)
      
      # Circuit breaker should be open
      status = ClusterBridge.cluster_status()
      breaker = status.circuit_breakers[:"remote@127.0.0.1"]
      assert breaker.state == :open
    end
  end
  
  describe "filtering and configuration" do
    test "respects event filter configuration" do
      filter = fn event -> 
        event.type in [:allowed_event]
      end
      
      {:ok, _pid} = ClusterBridge.start_link(
        replication_config: %{event_filter: filter}
      )
      
      # This would be filtered out
      event = %{type: :forbidden_event, data: %{}}
      refute ClusterBridge.should_replicate?(event, %{
        replication_config: %{event_filter: filter}
      })
      
      # This would pass
      event = %{type: :allowed_event, data: %{}}
      assert ClusterBridge.should_replicate?(event, %{
        replication_config: %{event_filter: filter}
      })
    end
  end
end