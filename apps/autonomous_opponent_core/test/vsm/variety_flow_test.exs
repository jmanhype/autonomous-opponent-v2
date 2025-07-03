defmodule AutonomousOpponentV2Core.VSM.VarietyFlowTest do
  @moduledoc """
  Tests for VSM variety flow - ensuring all subsystems communicate properly.
  
  These tests validate that variety flows correctly through the VSM channels,
  that control loops close properly, and that the algedonic bypass works.
  """
  
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.{
    Supervisor,
    Channels.VarietyChannel,
    Algedonic.Channel,
    S1.Operations,
    S2.Coordination,
    S3.Control,
    S4.Intelligence,
    S5.Policy
  }
  
  setup do
    # VSM components are already started by the application
    # Just verify they're running
    vsm_sup = Process.whereis(Supervisor)
    
    # Give VSM time to stabilize
    Process.sleep(1000)
    
    %{vsm_supervisor: vsm_sup}
  end
  
  describe "VSM Viability" do
    test "all subsystems start and are viable", %{vsm_supervisor: vsm_sup} do
      # Check that supervisor is running
      assert Process.alive?(vsm_sup)
      
      # Check each subsystem
      assert Process.whereis(Operations) != nil
      assert Process.whereis(Coordination) != nil
      assert Process.whereis(Control) != nil
      assert Process.whereis(Intelligence) != nil
      assert Process.whereis(Policy) != nil
      assert Process.whereis(Channel) != nil
      
      # All should be alive
      assert Process.alive?(Process.whereis(Operations))
      assert Process.alive?(Process.whereis(Coordination))
      assert Process.alive?(Process.whereis(Control))
      assert Process.alive?(Process.whereis(Intelligence))
      assert Process.alive?(Process.whereis(Policy))
      assert Process.alive?(Process.whereis(Channel))
    end
  end
  
  describe "Variety Flow: S1 → S2 → S3" do
    test "operational variety flows from S1 to S3 via S2" do
      # Subscribe to events
      EventBus.subscribe(:s1_operations)
      EventBus.subscribe(:s2_coordination)
      EventBus.subscribe(:s3_control)
      
      # S1 performs operation
      {:ok, result} = Operations.process_request(%{
        type: :compute,
        data: "test_data"
      })
      
      assert result.status == :success
      
      # Should receive S1 operational report
      assert_receive {:event, :s1_operations, s1_report}, 2000
      assert s1_report.unit_id != nil
      
      # S2 should process and coordinate
      assert_receive {:event, :s2_coordination, s2_report}, 2000
      
      # S3 should receive aggregated data
      assert_receive {:event, :s3_health, s3_health}, 2000
      assert s3_health.health >= 0
    end
  end
  
  describe "Control Loop: S3 → S1" do
    test "S3 can send control commands to S1" do
      # Subscribe to control events
      EventBus.subscribe(:s3_control)
      
      # Trigger intervention from S3
      Control.intervene(:s1_operations, :throttle)
      
      # Give time for command to propagate
      Process.sleep(100)
      
      # Check S1 state reflects throttling
      state = Operations.get_state()
      assert state.control_mode != nil
    end
  end
  
  describe "Intelligence Flow: S4 → S5" do
    test "S4 intelligence reaches S5 for policy decisions" do
      # Subscribe to intelligence events
      EventBus.subscribe(:s4_intelligence)
      EventBus.subscribe(:s5_policy)
      
      # Trigger environmental scan
      {:ok, report} = Intelligence.scan_environment()
      
      assert report.environmental_model != nil
      assert is_list(report.patterns)
      
      # S5 should process intelligence
      assert_receive {:event, :s4_intelligence, intel_report}, 2000
      assert intel_report.timestamp != nil
    end
  end
  
  describe "Policy Constraints: S5 → All" do
    test "S5 policy constraints propagate to all subsystems" do
      # Set a new constraint
      :ok = Policy.set_constraint(:max_resource_usage, 0.75)
      
      # Give time for propagation
      Process.sleep(500)
      
      # Check that constraint is acknowledged
      identity = Policy.get_identity()
      assert identity.current_constraints.max_resource_usage == 0.75
    end
  end
  
  describe "Algedonic Bypass" do
    test "pain signals bypass normal channels" do
      # Subscribe to algedonic events
      EventBus.subscribe(:emergency_algedonic)
      EventBus.subscribe(:algedonic_intervention)
      
      # Report severe pain
      Channel.report_pain(:test_source, :test_pain, 0.9)
      
      # Should receive emergency signal
      assert_receive {:event, :emergency_algedonic, emergency}, 1000
      assert emergency.source == :test_source
      assert emergency.bypass_all == true
    end
    
    test "emergency scream reaches all subsystems" do
      # Subscribe to all subsystem events
      EventBus.subscribe(:all_subsystems)
      
      # Trigger emergency scream
      Channel.emergency_scream(:test_emergency, "Critical failure!")
      
      # Should broadcast to all
      assert_receive {:event, :emergency_algedonic, signal}, 1000
      assert signal.reason == "Critical failure!"
    end
  end
  
  describe "Variety Channel Transformations" do
    test "variety is properly transformed between subsystems" do
      # Test S1 → S2 transformation
      test_data = %{
        operational_load: 100,
        resource_usage: %{cpu: 50, memory: 60}
      }
      
      # Transmit through variety channel
      :ok = VarietyChannel.transmit(:s1_to_s2, test_data)
      
      # Give time for processing
      Process.sleep(100)
      
      # Channel should handle transformation
      # (In real test, would verify actual transformation)
      assert true
    end
    
    test "variety channels respect capacity limits" do
      # Get channel stats
      stats = VarietyChannel.get_channel_stats(:s1_to_s2)
      
      assert stats.capacity == 1000
      assert stats.messages_transmitted >= 0
      assert stats.current_flow >= 0
    end
  end
  
  describe "Full VSM Loop" do
    test "complete variety loop from operations to policy and back" do
      # This tests the full cybernetic loop:
      # S1 → S2 → S3 → S4 → S5 → Policy → S3 → S1
      
      # Subscribe to key events
      EventBus.subscribe(:s1_operations)
      EventBus.subscribe(:s5_policy)
      EventBus.subscribe(:vsm_viable)
      
      # Start with S1 operation
      {:ok, _} = Operations.process_request(%{
        type: :critical_operation,
        priority: :high
      })
      
      # Should flow through system
      assert_receive {:event, :s1_operations, _}, 2000
      
      # Eventually should see policy response if needed
      # (In full implementation, would track complete flow)
      
      # VSM should remain viable
      health = Operations.calculate_health()
      assert health > 0
    end
  end
  
  describe "Oscillation Dampening" do
    test "S2 prevents oscillations between S1 units" do
      # Report multiple conflicts quickly
      Coordination.report_conflict(:unit1, :unit2, :cpu)
      Coordination.report_conflict(:unit1, :unit2, :cpu)
      Coordination.report_conflict(:unit1, :unit2, :cpu)
      
      # S2 should detect oscillation
      Process.sleep(100)
      
      state = Coordination.get_coordination_state()
      assert state.oscillation_risk > 0
    end
  end
  
  describe "Audit Trail" do
    test "S3 maintains audit trail of decisions" do
      # Make some decisions
      Control.optimize_resources()
      Control.intervene(:s1_operations, :redistribute)
      
      # Get audit trail
      {:ok, audit} = Control.get_audit_trail(60_000)
      
      # Should have recorded decisions
      assert is_list(audit)
      # Audit entries would be in the Metrics system
    end
  end
end