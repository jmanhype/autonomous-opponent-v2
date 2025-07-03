defmodule AutonomousOpponentV2Core.VSM.ControlLoopTest do
  use ExUnit.Case, async: true

  alias AutonomousOpponent.VSM.ControlLoop
  alias AutonomousOpponent.EventBus

  setup do
    # Start EventBus if not already started
    case Process.whereis(AutonomousOpponent.EventBus) do
      nil -> {:ok, _} = EventBus.start_link()
      _ -> :ok
    end

    # Start all subsystems
    {:ok, s1} = AutonomousOpponent.VSM.S1.Operations.start_link(id: "test_s1")
    {:ok, s2} = AutonomousOpponent.VSM.S2.Coordination.start_link(id: "test_s2")
    {:ok, s3} = AutonomousOpponent.VSM.S3.Control.start_link(id: "test_s3")
    {:ok, s4} = AutonomousOpponent.VSM.S4.Intelligence.start_link(id: "test_s4")
    {:ok, s5} = AutonomousOpponent.VSM.S5.Policy.start_link(id: "test_s5")
    {:ok, alg} = AutonomousOpponent.VSM.Algedonic.System.start_link(id: "test_alg")

    # Start control loop with test subsystems
    {:ok, cl} =
      ControlLoop.start_link(
        id: "test_control_loop",
        s1_pid: s1,
        s2_pid: s2,
        s3_pid: s3,
        s4_pid: s4,
        s5_pid: s5,
        algedonic_pid: alg
      )

    {:ok,
     %{
       control_loop: cl,
       s1: s1,
       s2: s2,
       s3: s3,
       s4: s4,
       s5: s5,
       algedonic: alg
     }}
  end

  describe "system status" do
    test "returns comprehensive system status", %{control_loop: cl} do
      status = ControlLoop.get_system_status(cl)

      assert status.id == "test_control_loop"
      assert status.emergency_mode == false
      assert Map.has_key?(status, :health)
      assert Map.has_key?(status, :control_state)
      assert Map.has_key?(status, :metrics)
      assert Map.has_key?(status, :subsystem_status)

      # Check subsystem availability
      assert status.subsystem_status.s1 == :available
      assert status.subsystem_status.s2 == :available
      assert status.subsystem_status.s3 == :available
      assert status.subsystem_status.s4 == :available
      assert status.subsystem_status.s5 == :available
      assert status.subsystem_status.algedonic == :available
    end
  end

  describe "control cycle" do
    test "executes successful control cycle", %{control_loop: cl} do
      result = ControlLoop.trigger_control_cycle(cl)

      assert result == :ok

      # Check metrics were updated
      status = ControlLoop.get_system_status(cl)
      assert status.control_state.cycles_completed > 0
      assert status.control_state.last_cycle != nil
    end

    test "control loop runs automatically", %{control_loop: cl} do
      # Wait for automatic cycles
      # Wait for at least 2 cycles
      Process.sleep(2500)

      status = ControlLoop.get_system_status(cl)
      assert status.control_state.cycles_completed >= 2
      assert status.metrics.total_cycles >= 2
    end
  end

  describe "emergency mode" do
    test "enables and disables emergency mode", %{control_loop: cl} do
      # Enable emergency mode
      ControlLoop.enable_emergency_mode(cl)

      status = ControlLoop.get_system_status(cl)
      assert status.emergency_mode == true

      # Disable emergency mode
      ControlLoop.disable_emergency_mode(cl)

      status = ControlLoop.get_system_status(cl)
      assert status.emergency_mode == false
    end

    test "emergency mode uses simplified cycle", %{control_loop: cl} do
      # Enable emergency mode
      ControlLoop.enable_emergency_mode(cl)

      # Trigger cycle
      result = ControlLoop.trigger_control_cycle(cl)
      assert result == :ok

      # In emergency mode, S2 and S4 are bypassed
      # This would be observable in the cycle behavior
    end
  end

  describe "algedonic bypass" do
    test "handles algedonic signals with bypass", %{control_loop: cl} do
      # Subscribe to see if bypass works
      EventBus.subscribe(:control_mode_change)

      # Send algedonic signal
      EventBus.publish(:algedonic_signal, %{
        type: :pain,
        intensity: 0.9,
        source: :resource_critical,
        timestamp: System.monotonic_time(:millisecond)
      })

      # Wait for processing
      Process.sleep(100)

      # Check that signal was processed
      status = ControlLoop.get_system_status(cl)
      assert status.metrics.information_flow_rate > 0
    end
  end

  describe "health monitoring" do
    test "performs health checks on subsystems", %{control_loop: cl} do
      # Wait for health check
      # Wait for health check interval
      Process.sleep(5500)

      status = ControlLoop.get_system_status(cl)
      assert status.health.overall == :healthy
      assert status.health.subsystems.s1 == :operational
      assert status.health.subsystems.s2 == :operational
      assert status.health.subsystems.s3 == :operational
      assert status.health.subsystems.s4 == :operational
      assert status.health.subsystems.s5 == :operational
      assert status.health.subsystems.algedonic == :operational
    end

    test "detects subsystem failures", %{control_loop: cl, s2: s2} do
      # Subscribe to viability threats
      EventBus.subscribe(:viability_threat)

      # Kill a subsystem
      Process.exit(s2, :kill)
      Process.sleep(100)

      # Trigger health check
      send(cl, :health_check)
      Process.sleep(100)

      # Should detect failure
      status = ControlLoop.get_system_status(cl)
      assert status.health.overall == :degraded
      assert status.health.subsystems.s2 == :failed

      # Should publish viability threat
      assert_receive {:event, :viability_threat, threat}, 1000
      assert threat.type == :subsystem_failure
    end
  end

  describe "channel management" do
    test "maintains active channels", %{control_loop: cl} do
      status = ControlLoop.get_system_status(cl)

      # All channels should be active initially
      assert :s1_s2 in status.control_state.active_channels
      assert :s2_s3 in status.control_state.active_channels
      assert :s3_s4 in status.control_state.active_channels
      assert :s4_s5 in status.control_state.active_channels
      assert :s5_s1 in status.control_state.active_channels

      assert status.control_state.blocked_channels == []
    end

    test "blocks failed channels", %{control_loop: cl} do
      # Send subsystem failure event
      EventBus.publish(:subsystem_failure, %{
        subsystem: :s2,
        reason: :process_exit
      })

      Process.sleep(100)

      status = ControlLoop.get_system_status(cl)
      assert :s2_s3 in status.control_state.blocked_channels
      assert :s2_s3 not in status.control_state.active_channels
    end
  end

  describe "metrics tracking" do
    test "tracks cycle metrics", %{control_loop: cl} do
      # Trigger multiple cycles
      ControlLoop.trigger_control_cycle(cl)
      ControlLoop.trigger_control_cycle(cl)
      ControlLoop.trigger_control_cycle(cl)

      status = ControlLoop.get_system_status(cl)

      assert status.metrics.total_cycles >= 3
      assert status.metrics.successful_cycles >= 3
      assert status.metrics.average_cycle_time > 0
    end
  end

  describe "viability threats" do
    test "responds to critical viability threats", %{control_loop: cl} do
      # Send critical threat
      EventBus.publish(:viability_threat, %{
        type: :resource_depletion,
        severity: :critical,
        affected_subsystems: [:s1, :s3]
      })

      Process.sleep(100)

      # Should enable emergency mode
      status = ControlLoop.get_system_status(cl)
      assert status.emergency_mode == true
    end

    test "handles non-critical threats normally", %{control_loop: cl} do
      # Send non-critical threat
      EventBus.publish(:viability_threat, %{
        type: :performance_degradation,
        severity: :medium,
        affected_subsystems: [:s2]
      })

      Process.sleep(100)

      # Should not enable emergency mode
      status = ControlLoop.get_system_status(cl)
      assert status.emergency_mode == false
    end
  end
end
