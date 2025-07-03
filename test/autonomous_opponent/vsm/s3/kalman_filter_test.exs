defmodule AutonomousOpponentV2Core.VSM.S3.KalmanFilterTest do
  use ExUnit.Case, async: true

  alias AutonomousOpponent.VSM.S3.KalmanFilter

  describe "filter initialization" do
    test "creates new filter with defaults" do
      filter = KalmanFilter.new(:cpu)

      assert filter.resource_type == :cpu
      assert filter.state_estimate == 0.5
      assert filter.error_covariance == 1.0
      assert filter.history == []
    end

    test "creates filter with custom initial state" do
      filter = KalmanFilter.new(:memory, initial_state: 0.7, process_noise: 0.1)

      assert filter.state_estimate == 0.7
      assert filter.process_noise == 0.1
    end
  end

  describe "filter updates" do
    test "updates state with new measurement" do
      filter = KalmanFilter.new(:cpu)

      measurement = %{
        utilization: 0.6,
        demand_rate: 1.2,
        timestamp: System.monotonic_time(:millisecond)
      }

      updated = KalmanFilter.update(filter, measurement)

      assert updated.state_estimate != filter.state_estimate
      assert length(updated.history) == 1
      assert updated.last_update > filter.last_update
    end

    test "maintains history limit" do
      filter = KalmanFilter.new(:memory)

      # Add many measurements
      updated =
        Enum.reduce(1..150, filter, fn i, acc ->
          measurement = %{
            utilization: 0.5 + i * 0.001,
            demand_rate: 1.0,
            timestamp: System.monotonic_time(:millisecond) + i
          }

          KalmanFilter.update(acc, measurement)
        end)

      # History should be capped at 100
      assert length(updated.history) == 100
    end
  end

  describe "predictions" do
    test "predicts future state" do
      filter = KalmanFilter.new(:variety_capacity)

      # Add some measurements to establish trend
      filter =
        Enum.reduce(1..10, filter, fn i, acc ->
          measurement = %{
            # Increasing trend
            utilization: 0.4 + i * 0.05,
            demand_rate: 1.0,
            timestamp: System.monotonic_time(:millisecond) + i * 1000
          }

          KalmanFilter.update(acc, measurement)
        end)

      # Predict 30 seconds ahead
      prediction = KalmanFilter.predict(filter, 30_000)

      assert prediction.resource_type == :variety_capacity
      assert prediction.predicted_utilization > filter.state_estimate
      assert prediction.horizon_ms == 30_000
      assert elem(prediction.confidence_interval, 0) < prediction.predicted_utilization
      assert elem(prediction.confidence_interval, 1) > prediction.predicted_utilization
    end

    test "clamps predictions to valid range" do
      filter = KalmanFilter.new(:cpu, initial_state: 0.95)

      # Predict far future
      prediction = KalmanFilter.predict(filter, 300_000)

      assert prediction.predicted_utilization <= 1.0
      assert elem(prediction.confidence_interval, 0) >= 0.0
    end
  end

  describe "diagnostics" do
    test "provides filter health assessment" do
      filter = KalmanFilter.new(:memory)
      diagnostics = KalmanFilter.get_diagnostics(filter)

      assert diagnostics.resource_type == :memory
      # Not enough data
      assert diagnostics.filter_health == :warming_up

      # Add measurements
      filter =
        Enum.reduce(1..10, filter, fn i, acc ->
          KalmanFilter.update(acc, %{
            utilization: 0.5,
            demand_rate: 1.0,
            timestamp: System.monotonic_time(:millisecond) + i
          })
        end)

      new_diagnostics = KalmanFilter.get_diagnostics(filter)
      assert new_diagnostics.filter_health == :healthy
    end
  end

  describe "batch updates" do
    test "processes multiple measurements" do
      filter = KalmanFilter.new(:processing_slots)

      measurements =
        Enum.map(1..5, fn i ->
          %{
            utilization: 0.3 + i * 0.1,
            demand_rate: 1.5,
            timestamp: System.monotonic_time(:millisecond) + i * 1000
          }
        end)

      updated = KalmanFilter.batch_update(filter, measurements)

      assert length(updated.history) == 5
      assert updated.state_estimate > filter.state_estimate
    end
  end

  describe "adaptive tuning" do
    test "adapts parameters based on prediction errors" do
      filter = KalmanFilter.new(:cpu, process_noise: 0.01)

      # Add measurements with high variance
      filter =
        Enum.reduce(1..20, filter, fn i, acc ->
          utilization = if rem(i, 2) == 0, do: 0.8, else: 0.2

          KalmanFilter.update(acc, %{
            utilization: utilization,
            demand_rate: 1.0,
            timestamp: System.monotonic_time(:millisecond) + i * 1000
          })
        end)

      adapted = KalmanFilter.adapt_parameters(filter)

      # Process noise should increase due to high variance
      assert adapted.process_noise >= filter.process_noise
    end
  end

  describe "filter reset" do
    test "resets filter to initial state" do
      filter =
        KalmanFilter.new(:memory)
        |> KalmanFilter.update(%{utilization: 0.8, demand_rate: 2.0, timestamp: 1000})
        |> KalmanFilter.update(%{utilization: 0.9, demand_rate: 2.5, timestamp: 2000})

      reset_filter = KalmanFilter.reset(filter)

      assert reset_filter.state_estimate == 0.5
      assert reset_filter.error_covariance == 1.0
      assert reset_filter.history == []
    end
  end
end
