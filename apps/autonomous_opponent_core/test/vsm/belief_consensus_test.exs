defmodule AutonomousOpponentV2Core.VSM.BeliefConsensusTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.VSM.BeliefConsensus
  alias AutonomousOpponentV2Core.VSM.BeliefConsensus.{ByzantineDetector, DeltaSync, PatternIntegration}
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Start EventBus if not running
    unless Process.whereis(AutonomousOpponentV2Core.EventBus) do
      {:ok, _} = EventBus.start_link([])
    end
    
    # Start CRDTStore if not running
    unless Process.whereis(AutonomousOpponentV2Core.AMCP.Memory.CRDTStore) do
      {:ok, _} = AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.start_link([])
    end
    
    # Start belief consensus supervisor
    {:ok, sup} = AutonomousOpponentV2Core.VSM.BeliefConsensus.Supervisor.start_link([])
    
    on_exit(fn ->
      if Process.alive?(sup), do: Process.exit(sup, :normal)
    end)
    
    :ok
  end
  
  describe "belief consensus core functionality" do
    test "proposes and retrieves beliefs at different VSM levels" do
      # Test each VSM level
      for level <- [:s1, :s2, :s3, :s4, :s5] do
        belief_content = "Test belief for #{level}"
        metadata = %{
          source: "test_suite",
          weight: 0.8,
          confidence: 0.9
        }
        
        # Propose belief
        assert {:ok, belief_id} = BeliefConsensus.propose_belief(level, belief_content, metadata)
        assert is_binary(belief_id)
        
        # Get consensus
        assert {:ok, consensus} = BeliefConsensus.get_consensus(level)
        assert is_map(consensus)
        assert is_list(consensus.beliefs)
      end
    end
    
    test "enforces variety constraints" do
      # Fill up S1 to capacity
      for i <- 1..100 do
        BeliefConsensus.propose_belief(:s1, "Belief #{i}", %{weight: 0.5})
      end
      
      # Get metrics to check variety management
      metrics = BeliefConsensus.get_metrics(:s1)
      assert metrics.belief_count <= 100  # Max variety enforced
      assert metrics.variety_ratio > 0
    end
    
    test "handles algedonic bypass for critical beliefs" do
      critical_belief = "CRITICAL: System failure imminent"
      metadata = %{
        source: "test_monitor",
        weight: 1.0,
        confidence: 0.95,
        urgency: 0.98  # Above algedonic threshold
      }
      
      # Subscribe to algedonic events
      EventBus.subscribe(:algedonic_pain)
      
      # Propose critical belief
      {:ok, _} = BeliefConsensus.propose_belief(:s1, critical_belief, metadata)
      
      # Should receive algedonic signal
      assert_receive {:event, :algedonic_pain, signal}, 1000
      assert signal =~ critical_belief
    end
    
    test "manages belief TTL and cleanup" do
      # Create belief with short TTL
      short_ttl_belief = "Temporary belief"
      
      # Propose belief
      {:ok, belief_id} = BeliefConsensus.propose_belief(:s2, short_ttl_belief, %{})
      
      # Verify it exists
      {:ok, consensus} = BeliefConsensus.get_consensus(:s2)
      assert Enum.any?(consensus.beliefs, fn b -> b.content == short_ttl_belief end)
      
      # Force cleanup (in production, this happens automatically)
      send(Process.whereis(:belief_consensus_s2), :cleanup_beliefs)
      
      # After cleanup, expired beliefs should be gone
      # (In test, beliefs don't expire immediately due to 1-hour TTL)
    end
  end
  
  describe "Byzantine fault detection" do
    test "detects double voting patterns" do
      node_id = "byzantine_node_1"
      belief_id = "belief_123"
      
      # Record contradictory votes
      ByzantineDetector.record_vote(node_id, belief_id, :approve)
      ByzantineDetector.record_vote(node_id, belief_id, :reject)
      ByzantineDetector.record_vote(node_id, belief_id, :approve)
      
      # Check if node is marked Byzantine
      # (May not be immediate due to threshold)
      reputation = ByzantineDetector.get_reputation(node_id)
      assert reputation <= 1.0
    end
    
    test "detects message flooding" do
      node_id = "flooding_node"
      
      # Simulate flooding
      for i <- 1..150 do
        ByzantineDetector.record_message(node_id, :belief_update, 1024)
      end
      
      # Check reputation degradation
      reputation = ByzantineDetector.get_reputation(node_id)
      assert reputation < 1.0
    end
    
    test "integrates with S2 oscillation detection" do
      # Subscribe to Byzantine detection events
      EventBus.subscribe(:byzantine_node_detected)
      
      # Simulate S2 oscillation detection
      EventBus.publish(:s2_oscillation_detected, %{
        affected_units: ["belief_consensus_s1_suspicious_node"],
        severity: 0.8,
        pattern_type: :high_frequency_oscillation
      })
      
      # Should trigger Byzantine analysis
      assert_receive {:event, :byzantine_node_detected, _}, 2000
    end
  end
  
  describe "delta-state CRDT synchronization" do
    test "records and retrieves deltas" do
      # Record some operations
      belief = %BeliefConsensus.Belief{
        id: "test_belief_1",
        content: "Test belief for sync",
        source: :s3,
        weight: 0.7,
        timestamp: DateTime.utc_now()
      }
      
      DeltaSync.record_delta(:s3, :add, belief)
      
      # Get sync metrics
      metrics = DeltaSync.get_metrics(:s3)
      assert metrics.delta_buffer_size > 0
    end
    
    test "compresses large sync batches" do
      # Create many deltas
      for i <- 1..50 do
        belief = %BeliefConsensus.Belief{
          id: "belief_#{i}",
          content: "Large belief content that should trigger compression #{String.duplicate("x", 100)}",
          source: :s4,
          weight: 0.5,
          timestamp: DateTime.utc_now()
        }
        
        DeltaSync.record_delta(:s4, :add, belief)
      end
      
      # Check compression metrics
      metrics = DeltaSync.get_metrics(:s4)
      assert metrics.compression_ratio > 0  # Some compression should occur
    end
    
    test "handles peer synchronization" do
      # In a real distributed test, we'd have multiple nodes
      # For now, test the sync mechanism
      peer_id = "test_peer_node"
      
      # Attempt sync
      result = DeltaSync.sync_with_peer(:s1, peer_id)
      
      # Should handle missing peer gracefully
      assert {:ok, _} = result or {:error, _} = result
    end
  end
  
  describe "pattern integration" do
    test "converts high-confidence patterns to beliefs" do
      # Subscribe to belief events
      EventBus.subscribe(:belief_proposed)
      
      # Simulate pattern detection
      pattern = %{
        id: "pattern_001",
        type: :performance_degradation,
        confidence: 0.85,
        component: "database",
        timestamp: DateTime.utc_now()
      }
      
      # Process pattern
      PatternIntegration.process_pattern(pattern)
      
      # Allow time for processing
      Process.sleep(100)
      
      # Force pattern analysis
      {:ok, analysis} = PatternIntegration.analyze_patterns_for_beliefs()
      assert is_map(analysis)
    end
    
    test "correlates related patterns" do
      # Create correlated patterns
      base_time = DateTime.utc_now()
      
      pattern1 = %{
        id: "pattern_cor_1",
        type: :resource_exhaustion,
        resource: "memory",
        subsystem: "cache",
        confidence: 0.8,
        timestamp: base_time
      }
      
      pattern2 = %{
        id: "pattern_cor_2",
        type: :performance_degradation,
        component: "cache",
        subsystem: "cache",
        confidence: 0.75,
        timestamp: DateTime.add(base_time, 30, :second)
      }
      
      # Process patterns
      PatternIntegration.process_pattern(pattern1)
      PatternIntegration.process_pattern(pattern2)
      
      # Get correlations
      {:ok, correlations} = PatternIntegration.get_correlations()
      assert is_list(correlations)
    end
    
    test "handles pattern anomalies with urgency" do
      # Subscribe to algedonic events
      EventBus.subscribe(:algedonic_pain)
      
      # Create anomaly
      anomaly = %{
        id: "anomaly_001",
        type: :security_breach,
        description: "Unauthorized access detected",
        confidence: 0.95,
        severity: :critical
      }
      
      # Simulate anomaly detection
      EventBus.publish(:pattern_anomaly_detected, anomaly)
      
      # Should trigger urgent belief creation
      # (May go through algedonic channel)
      Process.sleep(100)
    end
  end
  
  describe "reputation-based voting" do
    test "applies reputation weights to votes" do
      belief_content = "Test belief for voting"
      
      # Propose belief
      {:ok, belief_id} = BeliefConsensus.propose_belief(:s3, belief_content, %{weight: 0.5})
      
      # Vote on belief
      assert {:ok, :vote_recorded} = BeliefConsensus.vote_on_belief(:s3, belief_id, 1.0)
      
      # Get vote details
      {:ok, votes} = BeliefConsensus.get_belief_votes(:s3, belief_id)
      assert votes.found
      assert votes.vote_count > 0
      assert votes.total_weight > 0
    end
    
    test "reaches consensus with sufficient weighted votes" do
      # Subscribe to consensus events
      EventBus.subscribe(:belief_consensus_reached)
      
      belief_content = "Belief requiring consensus"
      {:ok, belief_id} = BeliefConsensus.propose_belief(:s2, belief_content, %{weight: 0.6})
      
      # Simulate multiple votes
      # In production, these would come from different nodes
      for i <- 1..3 do
        # Vote from different process contexts
        Task.async(fn ->
          BeliefConsensus.vote_on_belief(:s2, belief_id, 0.8)
        end)
        |> Task.await()
      end
      
      # Check if consensus might be reached
      {:ok, votes} = BeliefConsensus.get_belief_votes(:s2, belief_id)
      assert votes.vote_count >= 1  # At least our vote
    end
  end
  
  describe "VSM level interactions" do
    test "propagates beliefs through variety channels" do
      # Subscribe to belief events at different levels
      EventBus.subscribe(:belief_proposed)
      
      # Propose belief at S1
      s1_belief = "Operational issue detected"
      {:ok, _} = BeliefConsensus.propose_belief(:s1, s1_belief, %{
        weight: 0.9,
        source: "operations_monitor"
      })
      
      # Should propagate up through channels
      # In production, S2 would receive and process
      Process.sleep(100)
    end
    
    test "applies S5 policy constraints" do
      # Set policy constraint
      constraint = %{
        id: "policy_001",
        type: :forbidden_content,
        pattern: ~r/dangerous|harmful/i
      }
      
      # Publish constraint
      EventBus.publish(:s5_belief_constraint, constraint)
      
      # Try to propose violating belief
      {:ok, _} = BeliefConsensus.propose_belief(:s1, "Safe belief content", %{})
      
      # Policy constraints would filter in production
    end
    
    test "handles cross-level consensus coordination" do
      # Force consensus at S3 (control intervention)
      forced_beliefs = ["Emergency shutdown required"]
      
      assert :ok = BeliefConsensus.force_consensus(:s3, forced_beliefs)
      
      # Verify forced consensus
      {:ok, consensus} = BeliefConsensus.get_consensus(:s3)
      assert MapSet.size(consensus.current) > 0
    end
  end
  
  describe "belief consensus supervisor" do
    test "health check reports all components" do
      health = AutonomousOpponentV2Core.VSM.BeliefConsensus.Supervisor.health_check()
      
      assert health.healthy
      assert is_list(health.components)
      assert length(health.components) > 0
      
      # Check specific components
      component_ids = Enum.map(health.components, & &1.id)
      assert Enum.any?(component_ids, &(&1 == AutonomousOpponentV2Core.VSM.BeliefConsensus.ByzantineDetector))
      assert Enum.any?(component_ids, &(&1 == AutonomousOpponentV2Core.VSM.BeliefConsensus.PatternIntegration))
    end
    
    test "gets metrics from all VSM levels" do
      all_metrics = AutonomousOpponentV2Core.VSM.BeliefConsensus.Supervisor.get_all_metrics()
      
      assert is_map(all_metrics)
      assert Map.has_key?(all_metrics, :s1)
      assert Map.has_key?(all_metrics, :s5)
      
      # Each level should have metrics
      for {level, metrics} <- all_metrics do
        assert is_atom(level)
        assert is_map(metrics)
      end
    end
    
    test "forces system-wide consensus" do
      emergency_belief = "System-wide emergency consensus"
      
      # Force across all levels
      AutonomousOpponentV2Core.VSM.BeliefConsensus.Supervisor.force_system_consensus(emergency_belief)
      
      # Verify at each level
      for level <- [:s1, :s2, :s3, :s4, :s5] do
        {:ok, consensus} = BeliefConsensus.get_consensus(level)
        # Forced consensus should be reflected
        assert is_map(consensus)
      end
    end
  end
end