defmodule AutonomousOpponentV2Core.WebGateway.LoadBalancer.ConsistentHashTest do
  @moduledoc """
  Tests for the consistent hash load balancer implementation.
  """
  
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.WebGateway.LoadBalancer.ConsistentHash
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Subscribe to ring change events
    EventBus.subscribe(:mcp_ring_change)
    
    # Start with fresh consistent hash instance
    {:ok, pid} = ConsistentHash.start_link(vnodes: 150)
    
    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)
    
    {:ok, %{hash_pid: pid}}
  end
  
  describe "node management" do
    test "adds nodes to the hash ring" do
      assert ConsistentHash.add_node(:node1) == :ok
      assert ConsistentHash.add_node(:node2, 2) == :ok  # Weight 2
      
      # Should receive ring change events
      assert_receive {:event_bus, :mcp_ring_change, %{action: :node_added, node: :node1}}
      assert_receive {:event_bus, :mcp_ring_change, %{action: :node_added, node: :node2}}
      
      # Check ring state
      state = ConsistentHash.get_ring_state()
      assert :node1 in state.nodes
      assert :node2 in state.nodes
      assert state.weights[:node2] == 2
    end
    
    test "prevents duplicate node addition" do
      assert ConsistentHash.add_node(:duplicate) == :ok
      assert {:error, :already_exists} = ConsistentHash.add_node(:duplicate)
    end
    
    test "removes nodes from the hash ring" do
      ConsistentHash.add_node(:to_remove)
      assert ConsistentHash.remove_node(:to_remove) == :ok
      
      # Should receive ring change event
      assert_receive {:event_bus, :mcp_ring_change, %{action: :node_removed, node: :to_remove}}
      
      # Check node is gone
      state = ConsistentHash.get_ring_state()
      refute :to_remove in state.nodes
    end
    
    test "handles removing non-existent node" do
      assert {:error, :not_found} = ConsistentHash.remove_node(:non_existent)
    end
  end
  
  describe "key routing" do
    test "routes keys to nodes consistently" do
      # Add nodes
      ConsistentHash.add_node(:server1)
      ConsistentHash.add_node(:server2)
      ConsistentHash.add_node(:server3)
      
      # Route same key multiple times
      key = "user:12345"
      node1 = ConsistentHash.get_node(key)
      node2 = ConsistentHash.get_node(key)
      node3 = ConsistentHash.get_node(key)
      
      # Should always return same node
      assert node1 == node2
      assert node2 == node3
      assert node1 in [:server1, :server2, :server3]
    end
    
    test "distributes keys across nodes" do
      # Add nodes
      ConsistentHash.add_node(:dist1)
      ConsistentHash.add_node(:dist2)
      ConsistentHash.add_node(:dist3)
      
      # Route many keys
      distributions = for i <- 1..100 do
        ConsistentHash.get_node("key_#{i}")
      end
      
      # Check distribution
      freq = Enum.frequencies(distributions)
      assert map_size(freq) == 3  # All nodes used
      
      # Each node should get reasonable share (not perfect due to hash)
      Enum.each(freq, fn {_node, count} ->
        assert count > 10  # At least 10% of keys
      end)
    end
    
    test "respects allowed nodes list" do
      # Add nodes
      ConsistentHash.add_node(:allowed1)
      ConsistentHash.add_node(:allowed2)
      ConsistentHash.add_node(:forbidden)
      
      # Route with restrictions
      node = ConsistentHash.get_node("test_key", [:allowed1, :allowed2])
      assert node in [:allowed1, :allowed2]
      refute node == :forbidden
    end
    
    test "handles empty ring" do
      # Don't add any nodes
      assert ConsistentHash.get_node("any_key") == nil
    end
    
    test "handles routing with single node" do
      ConsistentHash.add_node(:only_node)
      
      # All keys should go to the only node
      for i <- 1..10 do
        assert ConsistentHash.get_node("key_#{i}") == :only_node
      end
    end
  end
  
  describe "weighted distribution" do
    test "distributes according to weights" do
      # Add nodes with different weights
      ConsistentHash.add_node(:light, 1)
      ConsistentHash.add_node(:heavy, 3)
      
      # Route many keys
      distributions = for i <- 1..200 do
        ConsistentHash.get_node("weighted_key_#{i}")
      end
      
      freq = Enum.frequencies(distributions)
      
      # Heavy node should get roughly 3x more keys
      ratio = freq[:heavy] / freq[:light]
      assert ratio > 2.0 && ratio < 4.0
    end
  end
  
  describe "replication support" do
    test "gets multiple nodes for replication" do
      # Add enough nodes
      for i <- 1..5 do
        ConsistentHash.add_node(:"replica_node_#{i}")
      end
      
      # Get 3 nodes for replication
      nodes = ConsistentHash.get_nodes("replicated_key", 3)
      
      assert length(nodes) == 3
      assert length(Enum.uniq(nodes)) == 3  # All different
    end
    
    test "handles replication with fewer nodes than requested" do
      # Add only 2 nodes
      ConsistentHash.add_node(:rep1)
      ConsistentHash.add_node(:rep2)
      
      # Request 3 nodes
      nodes = ConsistentHash.get_nodes("key", 3)
      
      # Should return only available nodes
      assert length(nodes) == 2
      assert :rep1 in nodes
      assert :rep2 in nodes
    end
  end
  
  describe "ring rebalancing" do
    test "rebalances the ring" do
      # Add initial nodes
      ConsistentHash.add_node(:rebal1)
      ConsistentHash.add_node(:rebal2)
      
      # Trigger rebalance
      ConsistentHash.rebalance()
      
      # Should receive rebalance event
      assert_receive {:event_bus, :mcp_ring_change, %{action: :rebalanced}}
      
      # Ring should still work
      assert ConsistentHash.get_node("test") in [:rebal1, :rebal2]
    end
  end
  
  describe "dynamic node management via events" do
    test "adds nodes via EventBus" do
      EventBus.publish(:mcp_node_events, %{
        action: :add,
        node: :event_node,
        weight: 2
      })
      
      :timer.sleep(50)
      
      # Node should be added
      state = ConsistentHash.get_ring_state()
      assert :event_node in state.nodes
      assert state.weights[:event_node] == 2
    end
    
    test "removes nodes via EventBus" do
      # Add node first
      ConsistentHash.add_node(:event_remove)
      
      # Remove via event
      EventBus.publish(:mcp_node_events, %{
        action: :remove,
        node: :event_remove
      })
      
      :timer.sleep(50)
      
      # Node should be removed
      state = ConsistentHash.get_ring_state()
      refute :event_remove in state.nodes
    end
  end
  
  describe "consistency after changes" do
    test "minimal key redistribution when adding node" do
      # Add initial nodes
      ConsistentHash.add_node(:consist1)
      ConsistentHash.add_node(:consist2)
      
      # Record initial key mappings
      keys = for i <- 1..100, do: "consist_key_#{i}"
      initial_mappings = Map.new(keys, fn key ->
        {key, ConsistentHash.get_node(key)}
      end)
      
      # Add new node
      ConsistentHash.add_node(:consist3)
      
      # Check how many keys moved
      moved_count = Enum.count(keys, fn key ->
        ConsistentHash.get_node(key) != initial_mappings[key]
      end)
      
      # Should move roughly 1/3 of keys
      assert moved_count > 20 && moved_count < 45
    end
    
    test "keys redistribute when node is removed" do
      # Add nodes
      ConsistentHash.add_node(:remove1)
      ConsistentHash.add_node(:remove2)
      ConsistentHash.add_node(:remove3)
      
      # Find keys that map to remove2
      keys_for_remove2 = Enum.filter(1..100, fn i ->
        ConsistentHash.get_node("remove_key_#{i}") == :remove2
      end)
      
      # Remove the node
      ConsistentHash.remove_node(:remove2)
      
      # Those keys should now map to other nodes
      Enum.each(keys_for_remove2, fn i ->
        node = ConsistentHash.get_node("remove_key_#{i}")
        assert node in [:remove1, :remove3]
      end)
    end
  end
  
  describe "ring state inspection" do
    test "provides ring statistics" do
      # Add nodes with weights
      ConsistentHash.add_node(:stat1, 1)
      ConsistentHash.add_node(:stat2, 2)
      ConsistentHash.add_node(:stat3, 1.5)
      
      state = ConsistentHash.get_ring_state()
      
      assert length(state.nodes) == 3
      assert state.weights == %{stat1: 1, stat2: 2, stat3: 1.5}
      assert state.vnodes_per_node == 150
      
      # Total vnodes should be proportional to weights
      expected_total = round(150 * (1 + 2 + 1.5))
      assert state.total_vnodes == expected_total
    end
  end
end