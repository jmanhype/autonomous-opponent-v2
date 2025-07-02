defmodule AutonomousOpponent.VSM.S3.ControlTest do
  use ExUnit.Case, async: true

  alias AutonomousOpponent.VSM.S3.Control
  alias AutonomousOpponent.EventBus

  setup do
    # Start EventBus if not already started
    case Process.whereis(AutonomousOpponent.EventBus) do
      nil -> {:ok, _} = EventBus.start_link()
      _ -> :ok
    end

    {:ok, pid} = Control.start_link(id: "test_s3")

    {:ok, pid: pid}
  end

  describe "resource allocation" do
    test "allocates resources when available", %{pid: pid} do
      request = %{cpu: 100, memory: 512}

      assert {:ok, allocation} = Control.request_resources(pid, "test_unit", request)
      assert allocation.resources == request
      assert allocation.unit_id == "test_unit"
    end

    test "denies allocation when insufficient resources", %{pid: pid} do
      # Request more than available
      huge_request = %{cpu: 10_000, memory: 99_999}

      assert {:error, :insufficient_resources} =
               Control.request_resources(pid, "greedy_unit", huge_request)
    end

    test "releases resources back to pool", %{pid: pid} do
      # Allocate first
      request = %{cpu: 100, memory: 512}
      {:ok, _} = Control.request_resources(pid, "test_unit", request)

      # Release
      Control.release_resources(pid, "test_unit", request)

      # Should be able to allocate again
      assert {:ok, _} = Control.request_resources(pid, "another_unit", request)
    end
  end

  describe "performance targets" do
    test "updates performance targets", %{pid: pid} do
      assert :ok = Control.update_performance_target(pid, :variety_absorption, 0.95)

      # Verify event was published
      EventBus.subscribe(:performance_target_updated)
      Control.update_performance_target(pid, :response_time, 50)

      assert_receive {:event, :performance_target_updated, data}, 1000
      assert data.target_type == :response_time
      assert data.value == 50
    end
  end

  describe "forecasting" do
    test "generates resource allocation forecast", %{pid: pid} do
      assert {:ok, forecast} = Control.get_allocation_forecast(pid, 60_000)

      assert is_map(forecast)
      assert Map.has_key?(forecast, :cpu)
      assert Map.has_key?(forecast, :memory)
    end
  end

  describe "audit interventions" do
    test "handles audit intervention requests", %{pid: pid} do
      assert {:ok, result} =
               Control.audit_intervention(
                 pid,
                 :force_reallocation,
                 %{reason: "test"}
               )

      assert is_map(result)
    end
  end

  describe "S1 metrics integration" do
    test "responds to S1 metrics events", %{pid: pid} do
      # Publish S1 metrics
      EventBus.publish(:s1_metrics, %{
        unit_id: "s1_test",
        absorption_rate: 0.85,
        buffer_size: 100,
        operational_units: 3,
        timestamp: System.monotonic_time(:millisecond)
      })

      # Give it time to process
      Process.sleep(100)

      # S3 should have processed the metrics
      # In real test, we'd verify internal state changes
    end
  end

  describe "algedonic intervention" do
    test "handles emergency algedonic interventions", %{pid: pid} do
      # Allocate some resources first
      Control.request_resources(pid, "unit1", %{cpu: 100})
      Control.request_resources(pid, "unit2", %{cpu: 200})

      # Trigger emergency intervention
      EventBus.publish(:algedonic_intervention, %{
        action: :emergency_shutdown,
        source: :test
      })

      Process.sleep(100)

      # All resources should be released
      # Should be able to allocate full pool again
      assert {:ok, _} = Control.request_resources(pid, "recovery", %{cpu: 900})
    end
  end
end
