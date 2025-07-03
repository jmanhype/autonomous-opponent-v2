defmodule AutonomousOpponentV2Core.VSMTest do
  # Not async due to named processes
  use ExUnit.Case, async: false

  alias AutonomousOpponent.VSM
  alias AutonomousOpponent.EventBus

  setup do
    # Start EventBus if not already started
    case EventBus.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Start VSM
    {:ok, _supervisor} = VSM.start_link()

    # Wait for all subsystems to initialize
    Process.sleep(500)

    :ok
  end

  describe "VSM startup and status" do
    test "starts all subsystems successfully" do
      status = VSM.get_status()

      assert status.vsm_status.supervisor_status == :running

      # Check all subsystems are running
      assert status.vsm_status.subsystems.s1 == :running
      assert status.vsm_status.subsystems.s2 == :running
      assert status.vsm_status.subsystems.s3 == :running
      assert status.vsm_status.subsystems.s4 == :running
      assert status.vsm_status.subsystems.s5 == :running

      # Check control loop is operational
      assert is_map(status.vsm_status.control_loop)
      assert status.vsm_status.control_loop.health.overall == :healthy

      # Check algedonic system
      assert is_map(status.vsm_status.algedonic)
    end

    test "performs comprehensive health check" do
      health = VSM.health_check()

      assert health.overall == :healthy
      assert health.subsystems.s1 == :healthy
      assert health.subsystems.s2 == :healthy
      assert health.subsystems.s3 == :healthy
      assert health.subsystems.s4 == :healthy
      assert health.subsystems.s5 == :healthy
      assert health.subsystems.algedonic == :healthy
      assert health.subsystems.control_loop == :healthy
    end
  end

  describe "S1 Operations interface" do
    test "absorbs variety through S1" do
      event = %{
        type: :customer_request,
        data: %{request_id: 123, priority: :high},
        timestamp: System.monotonic_time(:millisecond)
      }

      assert :ok = VSM.absorb_variety(event)
    end

    test "retrieves operational metrics" do
      metrics = VSM.get_operational_metrics()

      assert is_map(metrics)
      assert Map.has_key?(metrics, :absorption_rate)
      assert Map.has_key?(metrics, :buffer_utilization)
      assert Map.has_key?(metrics, :variety_handled)
    end
  end

  describe "S2 Coordination interface" do
    test "gets coordination status" do
      status = VSM.get_coordination_status()

      assert is_map(status)
      assert Map.has_key?(status, :active_units)
      assert Map.has_key?(status, :oscillation_detected)
    end
  end

  describe "S3 Control interface" do
    test "gets resource allocation" do
      allocation = VSM.get_resource_allocation()

      assert is_map(allocation)
      assert Map.has_key?(allocation, :total_resources)
      assert Map.has_key?(allocation, :allocations)
    end

    test "optimizes resources with constraints" do
      constraints = %{
        max_memory: 1000,
        max_cpu: 80,
        priority_units: ["s1_unit_1"]
      }

      result = VSM.optimize_resources(constraints)

      assert is_map(result)
      assert Map.has_key?(result, :optimized_allocations)
    end
  end

  describe "S4 Intelligence interface" do
    test "gets environmental intelligence report" do
      report = VSM.get_intelligence_report()

      assert {:ok, scan_results} = report
      assert Map.has_key?(scan_results, :raw_data)
      assert Map.has_key?(scan_results, :entities)
      assert Map.has_key?(scan_results, :relationships)
    end

    test "gets future scenarios" do
      params = %{
        # 1 hour
        horizon: 3_600_000,
        count: 3
      }

      {:ok, scenarios} = VSM.get_future_scenarios(params)

      assert is_list(scenarios)
      assert length(scenarios) == 3

      Enum.each(scenarios, fn scenario ->
        assert Map.has_key?(scenario, :uncertainty)
        assert Map.has_key?(scenario, :variables)
      end)
    end
  end

  describe "S5 Policy interface" do
    test "gets system identity" do
      identity = VSM.get_system_identity()

      assert identity.name == "Autonomous Opponent"
      assert is_list(identity.core_capabilities)
      assert Map.has_key?(identity.personality_traits, :adaptability)
    end

    test "sets strategic goal" do
      goal = %{
        id: "vsm_test_goal",
        description: "Optimize system performance",
        priority: 0.9,
        purpose: :efficiency,
        success_criteria: %{metric: :throughput, target: 1000}
      }

      {:ok, validated_goal} = VSM.set_strategic_goal(goal)

      assert validated_goal.id == "vsm_test_goal"
      assert validated_goal.validated_at != nil
    end

    test "evaluates actions against policy" do
      action = %{
        type: :resource_allocation,
        purpose: :efficiency,
        subsystem: :s1,
        amount: 100
      }

      evaluation = VSM.evaluate_action(action)

      assert evaluation.decision in [:approved, :rejected]
      assert Map.has_key?(evaluation, :score)
      assert Map.has_key?(evaluation, :reasons)
    end
  end

  describe "Algedonic system interface" do
    test "triggers pain signal" do
      assert :ok = VSM.trigger_algedonic(:pain, :resource_shortage, %{severity: 0.8})
    end

    test "triggers pleasure signal" do
      assert :ok = VSM.trigger_algedonic(:pleasure, :goal_achieved, %{goal_id: "test"})
    end

    test "gets algedonic status" do
      status = VSM.get_algedonic_status()

      assert Map.has_key?(status, :recent_signals)
      assert Map.has_key?(status, :state)
      assert Map.has_key?(status, :metrics)
    end
  end

  describe "Emergency mode" do
    test "enables and disables emergency mode" do
      # Enable emergency mode
      assert :ok = VSM.enable_emergency_mode()

      Process.sleep(100)

      status = VSM.get_status()
      assert status.control_loop.emergency_mode == true

      # Disable emergency mode
      assert :ok = VSM.disable_emergency_mode()

      Process.sleep(100)

      status = VSM.get_status()
      assert status.control_loop.emergency_mode == false
    end
  end

  describe "Control loop operations" do
    test "gets control loop metrics" do
      metrics = VSM.get_control_loop_metrics()

      assert is_map(metrics)
      assert Map.has_key?(metrics, :total_cycles)
      assert Map.has_key?(metrics, :successful_cycles)
      assert Map.has_key?(metrics, :average_cycle_time)
    end

    test "manually triggers control cycle" do
      assert :ok = VSM.trigger_control_cycle()

      # Verify cycle was executed
      metrics = VSM.get_control_loop_metrics()
      assert metrics.total_cycles > 0
    end
  end

  describe "Subsystem restart" do
    test "restarts individual subsystems" do
      # Get initial S1 metrics
      initial_metrics = VSM.get_operational_metrics()

      # Restart S1
      assert {:ok, :restarted} = VSM.restart_subsystem(:s1)

      Process.sleep(200)

      # S1 should be operational again
      new_metrics = VSM.get_operational_metrics()
      assert is_map(new_metrics)

      # Metrics should be reset
      assert new_metrics.variety_handled == 0
    end
  end

  describe "End-to-end VSM operation" do
    test "complete VSM cycle from variety to policy" do
      # Subscribe to events
      EventBus.subscribe(:control_loop_feedback)

      # 1. Submit variety to S1
      event = %{
        type: :test_variety,
        data: %{test_id: 1},
        timestamp: System.monotonic_time(:millisecond)
      }

      VSM.absorb_variety(event)

      # 2. Let control loop process
      # Wait for control cycle
      Process.sleep(1500)

      # 3. Check that variety was processed through system
      metrics = VSM.get_operational_metrics()
      assert metrics.variety_handled > 0

      # 4. Check coordination happened
      coord_status = VSM.get_coordination_status()
      assert length(coord_status.active_units) > 0

      # 5. Check resources were allocated
      resources = VSM.get_resource_allocation()
      assert map_size(resources.allocations) > 0

      # 6. Check intelligence gathered
      {:ok, intelligence} = VSM.get_intelligence_report()
      assert map_size(intelligence.entities) > 0

      # 7. Should receive feedback
      assert_receive {:event, :control_loop_feedback, feedback}, 2000
      assert feedback.source == :s5_policy
      assert feedback.target == :s1_operations
    end
  end
end
