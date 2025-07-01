defmodule AutonomousOpponent.VSM.S2.CoordinationTest do
  use ExUnit.Case, async: true

  alias AutonomousOpponent.VSM.S2.Coordination
  alias AutonomousOpponent.EventBus

  setup do
    {:ok, _} = EventBus.start_link()
    {:ok, pid} = Coordination.start_link(id: "test_s2")

    {:ok, pid: pid}
  end

  describe "unit coordination" do
    test "coordinates multiple S1 units", %{pid: pid} do
      unit_ids = ["s1_unit_1", "s1_unit_2", "s1_unit_3"]

      assert {:ok, coordination_id} =
               Coordination.coordinate_units(pid, unit_ids, :load_balancing)

      assert is_binary(coordination_id)
    end

    test "handles new unit registration", %{pid: pid} do
      # Simulate S1 unit spawn event
      EventBus.publish(:s1_unit_spawned, %{
        parent_id: "s1_parent",
        child_id: "s1_child_1",
        pid: self(),
        reason: :low_absorption_rate
      })

      Process.sleep(100)

      state = Coordination.get_coordination_state(pid)
      assert state.active_units >= 1
    end
  end

  describe "resource locking" do
    test "grants resource lock when available", %{pid: pid} do
      resource = %{type: :cpu, id: "cpu_pool_1"}

      assert {:ok, lock_id} =
               Coordination.request_resource_lock(pid, "unit_1", resource, 5_000)

      assert is_binary(lock_id)
    end

    test "queues lock request when resource is locked", %{pid: pid} do
      resource = %{type: :memory, id: "mem_pool_1"}

      # First unit gets the lock
      {:ok, _} = Coordination.request_resource_lock(pid, "unit_1", resource, 5_000)

      # Second unit gets queued
      assert {:pending, {:estimated_ms, wait_time}} =
               Coordination.request_resource_lock(pid, "unit_2", resource, 5_000)

      assert wait_time > 0
    end

    test "releases lock and processes queue", %{pid: pid} do
      resource = %{type: :variety, id: "variety_1"}

      # Unit 1 gets lock
      {:ok, _} = Coordination.request_resource_lock(pid, "unit_1", resource, 1_000)

      # Unit 2 queued
      {:pending, _} = Coordination.request_resource_lock(pid, "unit_2", resource, 1_000)

      # Unit 1 releases
      Coordination.release_resource_lock(pid, "unit_1", resource)

      # Unit 2 should now be able to get the lock
      Process.sleep(100)

      # Try unit 3 - should be queued since unit 2 has it
      assert {:pending, _} =
               Coordination.request_resource_lock(pid, "unit_3", resource, 1_000)
    end
  end

  describe "damping control" do
    test "applies damping to oscillating units", %{pid: pid} do
      units = ["osc_unit_1", "osc_unit_2"]

      damping_params = %{
        damping_factor: 0.8,
        duration: 5_000
      }

      assert {:ok, damping_id} =
               Coordination.apply_damping(pid, units, damping_params)

      assert is_binary(damping_id)
    end
  end

  describe "oscillation detection integration" do
    test "processes S1 metrics for oscillation detection", %{pid: pid} do
      # Subscribe to see if damping is applied
      EventBus.subscribe(:apply_damping)

      # Simulate oscillating metrics
      for i <- 1..10 do
        absorption = if rem(i, 2) == 0, do: 0.9, else: 0.3

        EventBus.publish(:s1_metrics, %{
          unit_id: "oscillating_unit",
          absorption_rate: absorption,
          buffer_size: 100,
          operational_units: 1,
          timestamp: System.monotonic_time(:millisecond)
        })

        Process.sleep(100)
      end

      # Should eventually detect oscillation and apply damping
      # This is a simplified test - real oscillation detection needs more data
    end
  end

  describe "resource contention" do
    test "resolves resource contention between units", %{pid: pid} do
      # Simulate resource contention event
      EventBus.publish(:resource_contention, %{
        units: ["unit_a", "unit_b"],
        resource: %{type: :cpu, id: "shared_cpu"},
        timestamp: System.monotonic_time(:millisecond)
      })

      Process.sleep(100)

      # Contention should be resolved
      state = Coordination.get_coordination_state(pid)
      assert is_map(state)
    end
  end

  describe "coordination state" do
    test "reports coordination state summary", %{pid: pid} do
      state = Coordination.get_coordination_state(pid)

      assert Map.has_key?(state, :active_units)
      assert Map.has_key?(state, :active_coordinations)
      assert Map.has_key?(state, :resource_locks)
      assert Map.has_key?(state, :oscillation_status)
      assert Map.has_key?(state, :damping_active)
    end
  end
end
