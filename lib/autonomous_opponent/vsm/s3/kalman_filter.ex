defmodule AutonomousOpponent.VSM.S3.KalmanFilter do
  @moduledoc """
  Kalman Filter implementation for predictive resource allocation in S3 Control.

  Uses Kalman filtering to predict future resource demands and optimize
  allocation decisions based on historical patterns and current measurements.
  """

  defstruct [
    :resource_type,
    # Current state estimate
    :state_estimate,
    # Estimation error covariance
    :error_covariance,
    # Process noise covariance (Q)
    :process_noise,
    # Measurement noise covariance (R)
    :measurement_noise,
    # State transition matrix (F)
    :transition_matrix,
    # Measurement matrix (H)
    :measurement_matrix,
    # Historical measurements
    :history,
    :last_update
  ]

  @doc """
  Initialize a new Kalman filter for a specific resource type
  """
  def new(resource_type, opts \\ []) do
    %__MODULE__{
      resource_type: resource_type,
      state_estimate: opts[:initial_state] || default_initial_state(),
      error_covariance: opts[:initial_covariance] || 1.0,
      process_noise: opts[:process_noise] || default_process_noise(resource_type),
      measurement_noise: opts[:measurement_noise] || 0.1,
      # Simple scalar model
      transition_matrix: 1.0,
      # Direct observation
      measurement_matrix: 1.0,
      history: [],
      last_update: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Update the filter with a new measurement
  """
  def update(filter, measurement) do
    # Prediction step
    predicted_state = filter.transition_matrix * filter.state_estimate

    predicted_covariance =
      filter.transition_matrix * filter.error_covariance *
        filter.transition_matrix + filter.process_noise

    # Update step
    innovation = measurement.utilization - filter.measurement_matrix * predicted_state

    innovation_covariance =
      filter.measurement_matrix * predicted_covariance *
        filter.measurement_matrix + filter.measurement_noise

    # Kalman gain
    kalman_gain = predicted_covariance * filter.measurement_matrix / innovation_covariance

    # Updated estimates
    updated_state = predicted_state + kalman_gain * innovation
    updated_covariance = (1 - kalman_gain * filter.measurement_matrix) * predicted_covariance

    # Add to history
    new_history =
      [{measurement.timestamp, measurement} | filter.history]
      # Keep last 100 measurements
      |> Enum.take(100)

    %{
      filter
      | state_estimate: updated_state,
        error_covariance: updated_covariance,
        history: new_history,
        last_update: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Predict future state at given time horizon (in milliseconds)
  """
  def predict(filter, horizon_ms) do
    # Simple linear prediction
    # In a real implementation, this would use more sophisticated models
    # Convert to seconds
    steps = horizon_ms / 1000

    predicted_state =
      filter.state_estimate +
        calculate_trend(filter) * steps

    # Increase uncertainty over time
    predicted_uncertainty =
      filter.error_covariance *
        :math.sqrt(1 + steps / 60)

    %{
      resource_type: filter.resource_type,
      predicted_utilization: max(0, min(1, predicted_state)),
      uncertainty: predicted_uncertainty,
      confidence_interval: {
        max(0, predicted_state - 2 * predicted_uncertainty),
        min(1, predicted_state + 2 * predicted_uncertainty)
      },
      horizon_ms: horizon_ms
    }
  end

  @doc """
  Get filter statistics and diagnostics
  """
  def get_diagnostics(filter) do
    %{
      resource_type: filter.resource_type,
      current_estimate: filter.state_estimate,
      error_covariance: filter.error_covariance,
      measurement_count: length(filter.history),
      trend: calculate_trend(filter),
      last_update: filter.last_update,
      filter_health: assess_filter_health(filter)
    }
  end

  # Private functions

  defp default_initial_state do
    # Start with 50% utilization estimate
    0.5
  end

  defp default_process_noise(resource_type) do
    # Different resources have different volatility
    case resource_type do
      # CPU is quite volatile
      :cpu -> 0.05
      # Memory changes slowly
      :memory -> 0.02
      # Variety is highly variable
      :variety_capacity -> 0.1
      # Slots change moderately
      :processing_slots -> 0.03
      _ -> 0.05
    end
  end

  defp calculate_trend(filter) do
    case filter.history do
      [] ->
        0.0

      [_] ->
        0.0

      history ->
        # Simple linear regression on recent history
        recent = Enum.take(history, 10)

        if length(recent) < 2 do
          0.0
        else
          {times, values} =
            recent
            |> Enum.map(fn {time, measurement} ->
              {time, measurement.utilization}
            end)
            |> Enum.unzip()

          # Calculate slope using least squares
          n = length(times)
          sum_x = Enum.sum(times)
          sum_y = Enum.sum(values)

          sum_xy =
            Enum.zip(times, values)
            |> Enum.map(fn {x, y} -> x * y end)
            |> Enum.sum()

          sum_x2 = Enum.map(times, &(&1 * &1)) |> Enum.sum()

          denominator = n * sum_x2 - sum_x * sum_x

          if denominator == 0 do
            0.0
          else
            # Per second
            (n * sum_xy - sum_x * sum_y) / denominator / 1000
          end
        end
    end
  end

  defp assess_filter_health(filter) do
    cond do
      filter.error_covariance > 1.0 ->
        # High uncertainty
        :poor

      length(filter.history) < 5 ->
        # Not enough data
        :warming_up

      filter.error_covariance < 0.01 ->
        # Might be overfitting
        :overconfident

      true ->
        :healthy
    end
  end

  @doc """
  Batch update with multiple measurements
  """
  def batch_update(filter, measurements) do
    Enum.reduce(measurements, filter, fn measurement, acc ->
      update(acc, measurement)
    end)
  end

  @doc """
  Reset filter to initial state
  """
  def reset(filter) do
    %{
      filter
      | state_estimate: default_initial_state(),
        error_covariance: 1.0,
        history: [],
        last_update: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Adaptive filter tuning based on prediction errors
  """
  def adapt_parameters(filter) do
    case calculate_prediction_errors(filter) do
      {:ok, errors} when length(errors) > 5 ->
        # Adjust noise parameters based on actual vs predicted
        mean_error = Enum.sum(errors) / length(errors)
        error_variance = calculate_variance(errors, mean_error)

        %{
          filter
          | process_noise: filter.process_noise * (1 + mean_error),
            measurement_noise: max(0.01, error_variance)
        }

      _ ->
        filter
    end
  end

  defp calculate_prediction_errors(filter) do
    case filter.history do
      history when length(history) > 10 ->
        errors =
          history
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [{t1, m1}, {t2, m2}] ->
            # Predict from t1 to t2
            horizon = t2 - t1
            prediction = predict(filter, horizon)
            abs(prediction.predicted_utilization - m2.utilization)
          end)
          |> Enum.take(10)

        {:ok, errors}

      _ ->
        {:error, :insufficient_data}
    end
  end

  defp calculate_variance(values, mean) do
    sum_squared_diff =
      values
      |> Enum.map(fn v -> :math.pow(v - mean, 2) end)
      |> Enum.sum()

    sum_squared_diff / length(values)
  end
end
