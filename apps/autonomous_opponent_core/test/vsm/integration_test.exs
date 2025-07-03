defmodule AutonomousOpponentV2Core.VSM.IntegrationTest do
  @moduledoc """
  Integration tests for the complete VSM implementation.
  
  These tests validate complex scenarios involving multiple subsystems,
  emergency responses, and the full cybernetic control loop.
  """
  
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.{
    Supervisor,
    S1.Operations,
    S2.Coordination,
    S3.Control,
    S4.Intelligence,
    S5.Policy,
    Algedonic.Channel
  }
  
  setup do
    # VSM components are already started by the application
    # Just verify they're running
    vsm_sup = Process.whereis(Supervisor)
    
    # Allow VSM to stabilize
    Process.sleep(1500)
    
    %{vsm_supervisor: vsm_sup}
  end
  
  describe "Scenario: Resource Overload" do
    @tag :integration
    test "VSM handles resource overload through coordinated response" do
      # Subscribe to relevant events
      EventBus.subscribe(:algedonic_pain)
      EventBus.subscribe(:s3_control)
      EventBus.subscribe(:s1_operations)
      
      # Simulate high load on S1
      tasks = for i <- 1..20 do
        Task.async(fn ->
          Operations.process_request(%{
            type: :heavy_compute,
            id: i,
            load: 0.9
          })
        end)
      end
      
      # S1 should report pain due to overload
      assert_receive {:event, :algedonic_pain, pain_signal}, 5000
      assert pain_signal.source == :s1_operations
      
      # S3 should intervene
      assert_receive {:event, :s3_control, {:dampening_required, _}}, 5000
      
      # Wait for tasks to complete or be throttled
      results = Task.yield_many(tasks, 5000)
      
      # System should have adapted
      state = Operations.get_state()
      assert state.control_mode in [:throttled, :emergency_stop]
    end
  end
  
  describe "Scenario: Environmental Shift" do
    @tag :integration
    test "S4 detects environmental change and S5 adapts policy" do
      # Subscribe to intelligence and policy events
      EventBus.subscribe(:s4_intelligence)
      EventBus.subscribe(:s5_policy)
      EventBus.subscribe(:all_subsystems)
      
      # Get baseline
      baseline_identity = Policy.get_identity()
      
      # Trigger multiple environmental scans
      for _ <- 1..5 do
        Intelligence.scan_environment()
        Process.sleep(100)
      end
      
      # S4 should detect patterns and report to S5
      assert_receive {:event, :s4_intelligence, report}, 3000
      assert length(report.patterns) > 0
      
      # If significant change, S5 may adjust constraints
      current_identity = Policy.get_identity()
      
      # Identity coherence should be tracked
      assert current_identity.coherence >= 0
      assert current_identity.coherence <= 1.0
    end
  end
  
  describe "Scenario: Coordination Breakdown" do
    @tag :integration
    test "S2 prevents and resolves coordination conflicts" do
      # Create conflicting requests
      EventBus.subscribe(:s2_coordination)
      
      # Multiple S1 units competing for same resource
      conflicts = for i <- 1..10 do
        Task.async(fn ->
          Coordination.coordinate_request(:"s1_unit_#{i}", %{
            resource: :exclusive_lock,
            amount: 100
          })
        end)
      end
      
      # S2 should coordinate and prevent oscillation
      results = Task.yield_many(conflicts, 2000)
      
      # Check coordination state
      coord_state = Coordination.get_coordination_state()
      
      # Should have managed conflicts
      assert coord_state.oscillation_risk < 1.0
      assert coord_state.active_units > 0
      
      # Not all requests should succeed (coordination in action)
      successful = Enum.count(results, fn {_task, res} ->
        match?({:ok, {:ok, _}}, res)
      end)
      
      assert successful < 10  # Some should be redirected/delayed
    end
  end
  
  describe "Scenario: Emergency Response" do
    @tag :integration
    test "Algedonic bypass triggers immediate system-wide response" do
      # Subscribe to emergency events
      EventBus.subscribe(:emergency_algedonic)
      EventBus.subscribe(:all_subsystems)
      
      # Trigger emergency
      Channel.emergency_scream(:critical_failure, "System integrity compromised!")
      
      # All subsystems should receive emergency signal
      assert_receive {:event, :emergency_algedonic, emergency}, 1000
      assert emergency.bypass_all == true
      
      # S5 should respond with emergency override
      assert_receive {:event, :all_subsystems, {:s5_emergency_override, response}}, 2000
      assert response.type == :emergency_override
      
      # System should enter emergency mode
      Process.sleep(500)
      
      # Check various subsystem states
      s1_state = Operations.get_state()
      s3_state = Control.get_control_state()
      
      # At least one should reflect emergency
      assert s1_state.control_mode == :emergency_stop or
             s3_state.mode == :emergency
    end
  end
  
  describe "Scenario: Learning and Adaptation" do
    @tag :integration
    test "S4 learns from S3 decisions and improves predictions" do
      # Make several control decisions
      for i <- 1..5 do
        Control.optimize_resources()
        Process.sleep(200)
        
        # Simulate different outcomes
        outcome = if rem(i, 2) == 0, do: :success, else: :failure
        Intelligence.learn_from_audit(%{
          type: :optimization,
          outcome: outcome,
          timestamp: DateTime.utc_now()
        })
      end
      
      # S4 should have learned patterns
      {:ok, intel_report} = Intelligence.get_intelligence_report()
      
      assert is_list(intel_report.detected_patterns)
      assert is_list(intel_report.recommendations)
      
      # Future scenarios should be based on learning
      {:ok, scenarios} = Intelligence.model_scenario(%{
        type: :resource_optimization,
        current_load: 0.7
      })
      
      assert length(scenarios) > 0
    end
  end
  
  describe "Scenario: Identity Crisis" do
    @tag :integration
    test "S5 maintains identity coherence under pressure" do
      # Subscribe to policy events
      EventBus.subscribe(:s5_policy)
      EventBus.subscribe(:algedonic_pain)
      
      # Get baseline identity
      baseline = Policy.get_identity()
      
      # Attempt to violate core values repeatedly
      for _ <- 1..5 do
        decision = %{
          action: :violate_autonomy,
          severity: :high
        }
        
        result = Policy.evaluate_decision(decision)
        assert elem(result, 0) == :violation
      end
      
      # S5 should detect identity crisis
      assert_receive {:event, :algedonic_pain, pain}, 3000
      assert pain.source == :s5_policy
      assert pain.type in [:identity_crisis, :existential_health]
      
      # But core identity should remain
      current = Policy.get_identity()
      assert current.core.purpose == baseline.core.purpose
    end
  end
  
  describe "Scenario: Full Cybernetic Loop" do
    @tag :integration
    test "Complete control loop from sensing to action" do
      # This tests the full Beer loop:
      # Environment → S4 → S5 → S3 → S1 → Environment
      
      # Subscribe to all major events
      EventBus.subscribe(:s4_intelligence)
      EventBus.subscribe(:s5_policy)
      EventBus.subscribe(:s3_control)
      EventBus.subscribe(:s1_operations)
      
      # 1. S4 scans environment and detects pattern
      {:ok, scan} = Intelligence.scan_environment()
      assert length(scan.patterns) > 0
      
      # 2. S5 receives intelligence
      assert_receive {:event, :s4_intelligence, _}, 2000
      
      # 3. S3 makes control decision
      Control.optimize_resources()
      
      # 4. S1 executes operations
      assert_receive {:event, :s1_operations, op_report}, 2000
      assert op_report.unit_id != nil
      
      # 5. Loop closes - S3 can see S1 results
      state = Control.get_control_state()
      assert state.performance != nil
      
      # VSM should remain viable throughout
      Supervisor.validate_vsm_viability()
    end
  end
  
  describe "Scenario: Graceful Degradation" do
    @tag :integration
    test "VSM degrades gracefully under extreme load" do
      # Push system to limits
      extreme_load = for i <- 1..100 do
        Task.async(fn ->
          try do
            Operations.process_request(%{
              type: :extreme_load,
              id: i
            })
          catch
            _ -> {:error, :overloaded}
          end
        end)
      end
      
      # System should not crash
      Process.sleep(2000)
      
      # Should have engaged protective mechanisms
      s1_state = Operations.get_state()
      s2_state = Coordination.get_coordination_state()
      s3_state = Control.get_control_state()
      
      # At least one protection engaged
      assert s1_state.control_mode in [:throttled, :emergency_stop] or
             s2_state.oscillation_risk > 0.5 or
             s3_state.mode == :emergency
      
      # Clean up tasks
      Task.yield_many(extreme_load, 1000)
      
      # System should still be viable
      assert Process.alive?(Process.whereis(Operations))
      assert Process.alive?(Process.whereis(Supervisor))
    end
  end
  
  describe "Health Monitoring" do
    @tag :integration
    test "all subsystems report health metrics" do
      # Subscribe to health events
      EventBus.subscribe(:s1_health)
      EventBus.subscribe(:s2_health)
      EventBus.subscribe(:s3_health)
      EventBus.subscribe(:s4_health)
      EventBus.subscribe(:s5_health)
      
      # Wait for health reports
      assert_receive {:event, :s1_health, s1}, 2000
      assert_receive {:event, :s2_health, s2}, 2000
      assert_receive {:event, :s3_health, s3}, 2000
      assert_receive {:event, :s4_health, s4}, 2000
      assert_receive {:event, :s5_health, s5}, 2000
      
      # All should have health scores
      assert s1.health >= 0 and s1.health <= 1
      assert s2.health >= 0 and s2.health <= 1
      assert s3.health >= 0 and s3.health <= 1
      assert s4.health >= 0 and s4.health <= 1
      assert s5.health >= 0 and s5.health <= 1
      
      # System average health
      avg_health = (s1.health + s2.health + s3.health + s4.health + s5.health) / 5
      assert avg_health > 0.3  # System should be reasonably healthy
    end
  end
end