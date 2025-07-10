defmodule AutonomousOpponentV2Core.AMCP.Memory.EPMDDiscoveryTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.AMCP.Memory.EPMDDiscovery
  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
  
  @moduletag :distributed
  
  setup do
    # Ensure we're running in distributed mode
    unless Node.alive?() do
      node_name = :"test_epmd_#{System.unique_integer([:positive])}@127.0.0.1"
      {:ok, _} = Node.start(node_name)
      Node.set_cookie(:test_cookie)
    end
    
    # Stop any running instances
    if pid = Process.whereis(EPMDDiscovery) do
      GenServer.stop(pid, :normal, 1000)
    end
    
    if pid = Process.whereis(CRDTStore) do
      GenServer.stop(pid, :normal, 1000)
    end
    
    on_exit(fn ->
      # Clean up
      if pid = Process.whereis(EPMDDiscovery) do
        GenServer.stop(pid, :normal, 1000)
      end
      
      if pid = Process.whereis(CRDTStore) do
        GenServer.stop(pid, :normal, 1000)
      end
    end)
    
    :ok
  end
  
  describe "basic functionality" do
    test "starts successfully with default configuration" do
      assert {:ok, pid} = EPMDDiscovery.start_link()
      assert Process.alive?(pid)
    end
    
    test "can be enabled and disabled" do
      {:ok, _} = EPMDDiscovery.start_link()
      
      # Should be enabled by default
      status = EPMDDiscovery.status()
      assert status.discovery_enabled == true
      
      # Disable
      assert :ok = EPMDDiscovery.set_enabled(false)
      status = EPMDDiscovery.status()
      assert status.discovery_enabled == false
      
      # Re-enable
      assert :ok = EPMDDiscovery.set_enabled(true)
      status = EPMDDiscovery.status()
      assert status.discovery_enabled == true
    end
    
    test "respects custom discovery interval" do
      {:ok, _} = EPMDDiscovery.start_link(discovery_interval: 5_000)
      
      status = EPMDDiscovery.status()
      # With adaptive interval and 0 nodes, should use base interval
      assert status.adaptive_interval == 5_000
    end
    
    test "respects custom configuration options" do
      {:ok, _} = EPMDDiscovery.start_link(
        stability_threshold: 5,
        sync_cooldown_ms: 2_000
      )
      
      status = EPMDDiscovery.status()
      assert status.stability_threshold == 5
      assert status.sync_cooldown_ms == 2_000
    end
  end
  
  describe "node discovery" do
    @tag :skip
    test "discovers new nodes within 10 seconds" do
      # This test requires actual distributed nodes
      # Start CRDT Store and EPMD Discovery
      {:ok, _} = CRDTStore.start_link()
      {:ok, _} = EPMDDiscovery.start_link(discovery_interval: 1_000)
      
      # Get initial peer count
      initial_stats = CRDTStore.get_stats()
      initial_peers = initial_stats.peer_count
      
      # Start a new node
      {:ok, slave} = :slave.start('127.0.0.1', :test_slave, '-setcookie test_cookie')
      
      # Start CRDT Store on slave
      :rpc.call(slave, CRDTStore, :start_link, [])
      
      # Wait for discovery (should happen within 10s per requirement)
      Process.sleep(11_000)
      
      # Check that peer was discovered
      final_stats = CRDTStore.get_stats()
      assert final_stats.peer_count > initial_peers
      
      # Cleanup
      :slave.stop(slave)
    end
    
    test "removes departed nodes" do
      {:ok, _} = EPMDDiscovery.start_link()
      
      # Simulate nodedown event
      send(EPMDDiscovery, {:nodedown, :"departed@127.0.0.1", []})
      
      Process.sleep(100)
      
      status = EPMDDiscovery.status()
      refute :"departed@127.0.0.1" in status.known_nodes
    end
    
    test "applies node filter correctly" do
      # Custom filter that only accepts "crdt_" prefixed nodes
      filter = fn node ->
        node |> to_string() |> String.starts_with?("crdt_")
      end
      
      {:ok, _} = EPMDDiscovery.start_link(
        node_filter: filter,
        stability_threshold: 1  # Set to 1 for immediate addition in tests
      )
      
      # Simulate nodeup events
      send(EPMDDiscovery, {:nodeup, :"crdt_node@127.0.0.1", []})
      send(EPMDDiscovery, {:nodeup, :"other_node@127.0.0.1", []})
      
      Process.sleep(200)
      
      status = EPMDDiscovery.status()
      assert :"crdt_node@127.0.0.1" in status.known_nodes
      refute :"other_node@127.0.0.1" in status.known_nodes
    end
  end
  
  describe "stability tracking" do
    test "requires multiple sightings before adding as CRDT peer" do
      {:ok, _} = CRDTStore.start_link()
      {:ok, _} = EPMDDiscovery.start_link(stability_threshold: 3)
      
      # First sighting - should track but not add
      send(EPMDDiscovery, {:nodeup, :"stable_test@127.0.0.1", []})
      Process.sleep(100)
      
      stats = CRDTStore.get_stats()
      # Should not be added as peer yet
      assert stats.peer_count == 0
      
      # Check stability tracking
      status = EPMDDiscovery.status()
      assert :"stable_test@127.0.0.1" in status.known_nodes
      assert status.peer_stability[:"stable_test@127.0.0.1"] == 1
      
      # Trigger periodic discovery to increment stability
      # In real usage, this happens automatically
      EPMDDiscovery.discover_now()
      Process.sleep(100)
      
      # Should still not be added (stability = 2)
      stats = CRDTStore.get_stats()
      assert stats.peer_count == 0
    end
  end
  
  describe "adaptive discovery interval" do
    test "adjusts interval based on cluster size" do
      {:ok, _} = EPMDDiscovery.start_link(discovery_interval: 10_000)
      
      # With no nodes, should use base interval
      status = EPMDDiscovery.status()
      assert status.adaptive_interval == 10_000
      
      # Simulate adding many nodes (with low stability threshold for testing)
      {:ok, _} = GenServer.stop(EPMDDiscovery)
      {:ok, _} = EPMDDiscovery.start_link(
        discovery_interval: 10_000,
        stability_threshold: 1
      )
      
      # Add 15 nodes
      for i <- 1..15 do
        send(EPMDDiscovery, {:nodeup, :"node#{i}@127.0.0.1", []})
      end
      Process.sleep(200)
      
      # Should now use 2x interval (20 seconds)
      status = EPMDDiscovery.status()
      assert status.adaptive_interval == 20_000
    end
  end
  
  describe "manual discovery" do
    test "can trigger discovery manually" do
      {:ok, _} = EPMDDiscovery.start_link(enabled: false)
      
      # Manual trigger
      EPMDDiscovery.discover_now()
      
      # Should complete without error
      Process.sleep(100)
      status = EPMDDiscovery.status()
      assert is_integer(status.last_discovery)
    end
  end
  
  describe "integration with CRDT Store" do
    test "discover_peers/0 uses EPMD discovery when available" do
      {:ok, _} = CRDTStore.start_link()
      {:ok, _} = EPMDDiscovery.start_link()
      
      # This should trigger EPMD discovery
      CRDTStore.discover_peers()
      
      Process.sleep(100)
      
      # Verify discovery happened
      status = EPMDDiscovery.status()
      assert status.last_discovery != nil
    end
  end
end