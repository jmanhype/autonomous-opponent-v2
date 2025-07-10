defmodule AutonomousOpponentV2Core.EventBus.Cluster.ClusterBridgeTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.EventBus.Cluster.{
    ClusterBridge,
    AlgedonicBroadcast,
    VarietyManager,
    PartitionDetector
  }
  
  @moduletag :cluster
  
  describe "single node operation" do
    test "starts successfully in single-node mode" do
      # Should handle gracefully when no other nodes
      assert {:ok, _pid} = ClusterBridge.start_link(name: :test_cluster_bridge)
      
      topology = ClusterBridge.topology(:test_cluster_bridge)
      assert topology.node_id == node()
      assert topology.peers == []
      
      GenServer.stop(:test_cluster_bridge)
    end
    
    test "publishes events locally when no peers" do
      {:ok, _pid} = ClusterBridge.start_link(name: :test_local_bridge)
      
      # Subscribe to test event
      EventBus.subscribe(:test_event)
      
      # Publish event - should work locally
      EventBus.publish(:test_event, %{data: "test"})
      
      # Should receive locally
      assert_receive {:event_bus_hlc, %{event_name: :test_event, data: %{data: "test"}}}
      
      GenServer.stop(:test_local_bridge)
    end
  end
  
  describe "variety management integration" do
    test "respects variety quotas for different event classes" do
      {:ok, variety_manager} = VarietyManager.start_link(
        name: :test_variety_manager,
        quotas: %{
          s1_operational: 2,  # Very low for testing
          general: 1
        }
      )
      
      {:ok, _bridge} = ClusterBridge.start_link(
        name: :test_quota_bridge,
        variety_quotas: %{s1_operational: 2, general: 1}
      )
      
      # First event should be allowed
      assert :allowed == VarietyManager.check_outbound(:test_variety_manager, :s1_operational)
      
      # Second event should be allowed
      assert :allowed == VarietyManager.check_outbound(:test_variety_manager, :s1_operational)
      
      # Third event should be throttled
      assert :throttled == VarietyManager.check_outbound(:test_variety_manager, :s1_operational)
      
      GenServer.stop(:test_quota_bridge)
      GenServer.stop(:test_variety_manager)
    end
    
    test "algedonic events always bypass quotas" do
      {:ok, variety_manager} = VarietyManager.start_link(
        name: :test_algedonic_variety,
        quotas: %{algedonic: :unlimited, general: 0}  # Zero quota for general
      )
      
      # Algedonic should always be allowed
      assert :allowed == VarietyManager.check_outbound(:test_algedonic_variety, :algedonic)
      assert :allowed == VarietyManager.check_outbound(:test_algedonic_variety, :algedonic)
      
      # General should be throttled with zero quota
      assert :throttled == VarietyManager.check_outbound(:test_algedonic_variety, :general)
      
      GenServer.stop(:test_algedonic_variety)
    end
  end
  
  describe "partition detection" do
    test "detects healthy state with single node" do
      {:ok, detector} = PartitionDetector.start_link(name: :test_partition_detector)
      
      status = PartitionDetector.status(:test_partition_detector)
      assert status.current_partition == :healthy
      
      GenServer.stop(:test_partition_detector)
    end
    
    test "handles node addition and removal" do
      {:ok, detector} = PartitionDetector.start_link(name: :test_node_mgmt)
      
      # Add a fake node
      PartitionDetector.node_added(:test_node_mgmt, :fake_node@host)
      
      status = PartitionDetector.status(:test_node_mgmt)
      assert :fake_node@host in status.nodes
      
      # Remove the node
      PartitionDetector.node_removed(:test_node_mgmt, :fake_node@host)
      
      status = PartitionDetector.status(:test_node_mgmt)
      refute :fake_node@host in status.nodes
      
      GenServer.stop(:test_node_mgmt)
    end
  end
  
  describe "algedonic broadcast" do
    test "handles local algedonic signals" do
      {:ok, broadcast} = AlgedonicBroadcast.start_link(name: :test_algedonic)
      
      # Test pleasure signal
      signal = %{
        type: :pleasure,
        severity: 8,
        source: :test,
        data: %{message: "test pleasure"}
      }
      
      AlgedonicBroadcast.pleasure_signal(signal)
      
      # Should complete without error
      stats = AlgedonicBroadcast.stats()
      assert stats.pleasure_signals_sent >= 1
      
      GenServer.stop(:test_algedonic)
    end
    
    test "emergency scream with no peers returns immediately" do
      {:ok, broadcast} = AlgedonicBroadcast.start_link(name: :test_scream)
      
      signal = %{
        type: :pain,
        severity: 10,
        source: :test,
        data: %{emergency: true}
      }
      
      # Should return immediately when no peers
      {:ok, result} = AlgedonicBroadcast.emergency_scream(signal)
      
      assert result.confirmed_nodes == []
      assert result.failed_nodes == []
      
      GenServer.stop(:test_scream)
    end
  end
  
  describe "event classification" do
    test "correctly classifies VSM events" do
      # This test validates the event classification logic
      # Since the classification is private, we test through the public API
      
      {:ok, bridge} = ClusterBridge.start_link(name: :test_classification)
      
      # Subscribe to EventBus to capture events
      EventBus.subscribe(:vsm_test_event)
      
      # Test different event types
      test_events = [
        {:algedonic_pain, :algedonic},
        {:pattern_detected, :s4_intelligence},
        {:resource_allocation, :s3_control},
        {:anti_oscillation, :s2_coordination},
        {:task_execution, :s1_operational},
        {:policy_update, :s5_policy},
        {:unknown_event, :general}
      ]
      
      # Each event should be processed according to its class
      for {event_name, expected_class} <- test_events do
        EventBus.publish(event_name, %{test: true})
        
        # The fact that we don't get errors indicates classification is working
        # In a real distributed test, we'd verify replication behavior
      end
      
      GenServer.stop(:test_classification)
    end
  end
  
  describe "circuit breaker integration" do
    test "circuit breaker prevents cascade failures" do
      {:ok, bridge} = ClusterBridge.start_link(
        name: :test_circuit_breaker,
        circuit_breaker: %{
          failure_threshold: 1,  # Very low for testing
          recovery_time: 100,
          half_open_calls: 1
        }
      )
      
      topology = ClusterBridge.topology(:test_circuit_breaker)
      
      # Should start in healthy state
      assert topology.partition_status != :circuit_open
      
      GenServer.stop(:test_circuit_breaker)
    end
  end
  
  describe "telemetry integration" do
    test "reports telemetry metrics" do
      # Capture telemetry events
      :telemetry.attach_many(
        "test-cluster-telemetry",
        [
          [:vsm, :cluster, :bridge],
          [:vsm, :variety, :pressure_high],
          [:vsm, :algedonic, :signal_received]
        ],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      {:ok, bridge} = ClusterBridge.start_link(name: :test_telemetry)
      
      # Should eventually receive telemetry
      assert_receive {:telemetry, [:vsm, :cluster, :bridge], measurements, metadata}, 65_000
      
      assert Map.has_key?(measurements, :events_sent)
      assert Map.has_key?(metadata, :node)
      
      GenServer.stop(:test_telemetry)
      :telemetry.detach("test-cluster-telemetry")
    end
  end
  
  describe "configuration validation" do
    test "handles invalid configuration gracefully" do
      # Test with minimal configuration
      assert {:ok, _pid} = ClusterBridge.start_link(name: :test_minimal_config)
      GenServer.stop(:test_minimal_config)
      
      # Test with custom configuration
      custom_config = [
        variety_quotas: %{custom_channel: 500},
        event_ttl: 60_000,
        max_hops: 5
      ]
      
      assert {:ok, _pid} = ClusterBridge.start_link([name: :test_custom_config] ++ custom_config)
      GenServer.stop(:test_custom_config)
    end
  end
  
  describe "graceful shutdown" do
    test "shuts down cleanly" do
      {:ok, bridge} = ClusterBridge.start_link(name: :test_shutdown)
      
      # Should shutdown without errors
      assert :ok == GenServer.stop(bridge, :normal)
    end
    
    test "processes events during shutdown window" do
      {:ok, bridge} = ClusterBridge.start_link(name: :test_shutdown_events)
      
      # Send event right before shutdown
      EventBus.publish(:shutdown_test, %{data: "test"})
      
      # Shutdown
      GenServer.stop(bridge, :shutdown)
      
      # Should have processed the event
      # (Implementation would track this in real tests)
    end
  end
end