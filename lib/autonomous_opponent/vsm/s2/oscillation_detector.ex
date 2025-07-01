defmodule AutonomousOpponent.VSM.S2.OscillationDetector do
  @moduledoc """
  Oscillation detection for S2 Coordination.
  
  Detects oscillatory behaviors in S1 units using frequency analysis
  and pattern recognition. Implements Beer's oscillation detection
  algorithms for cybernetic systems.
  """
  
  use GenServer
  require Logger
  
  @window_size 20  # Number of measurements to keep
  @detection_threshold 0.3  # Minimum oscillation strength to report
  
  defstruct [
    :measurements,
    :detected_oscillations,
    :frequency_analysis,
    :pattern_buffer
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end
  
  def add_measurement(server \\ __MODULE__, unit_id, measurement) do
    GenServer.cast(server, {:add_measurement, unit_id, measurement})
  end
  
  def analyze(server \\ __MODULE__) do
    GenServer.call(server, :analyze)
  end
  
  def get_status(server \\ __MODULE__) do
    GenServer.call(server, :get_status)
  end
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      measurements: %{},
      detected_oscillations: [],
      frequency_analysis: %{},
      pattern_buffer: []
    }
    
    # Start periodic analysis
    Process.send_after(self(), :periodic_analysis, 5_000)
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:add_measurement, unit_id, measurement}, state) do
    # Add to rolling window
    new_measurements = Map.update(
      state.measurements,
      unit_id,
      [measurement],
      fn existing ->
        [measurement | existing] |> Enum.take(@window_size)
      end
    )
    
    {:noreply, %{state | measurements: new_measurements}}
  end
  
  @impl true
  def handle_call(:analyze, _from, state) do
    analysis = perform_oscillation_analysis(state)
    {:reply, analysis, state}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      units_monitored: map_size(state.measurements),
      oscillations_detected: length(state.detected_oscillations),
      active_oscillations: Enum.count(state.detected_oscillations, &(&1.active))
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_info(:periodic_analysis, state) do
    # Run periodic oscillation detection
    new_oscillations = detect_oscillations(state.measurements)
    
    # Update state with new detections
    new_state = %{state | 
      detected_oscillations: new_oscillations,
      frequency_analysis: analyze_frequencies(state.measurements)
    }
    
    # Alert if significant oscillations detected
    if Enum.any?(new_oscillations, &(&1.severity > @detection_threshold)) do
      Logger.warning("S2 OscillationDetector: Significant oscillations detected")
    end
    
    Process.send_after(self(), :periodic_analysis, 5_000)
    {:noreply, new_state}
  end
  
  defp perform_oscillation_analysis(state) do
    oscillations = detect_oscillations(state.measurements)
    
    %{
      oscillations: oscillations,
      frequency_spectrum: state.frequency_analysis,
      recommendations: generate_recommendations(oscillations)
    }
  end
  
  defp detect_oscillations(measurements) do
    measurements
    |> Enum.flat_map(fn {unit_id, unit_measurements} ->
      detect_unit_oscillations(unit_id, unit_measurements)
    end)
    |> Enum.filter(&(&1.severity > @detection_threshold))
  end
  
  defp detect_unit_oscillations(unit_id, measurements) when length(measurements) < 3 do
    []  # Not enough data
  end
  
  defp detect_unit_oscillations(unit_id, measurements) do
    # Extract time series data
    time_series = measurements
    |> Enum.map(&extract_metric(&1, :absorption_rate))
    |> Enum.reverse()  # Oldest first
    
    # Simple oscillation detection using zero-crossing method
    oscillations = detect_zero_crossings(time_series)
    
    # Calculate oscillation characteristics
    if length(oscillations) > 1 do
      [%{
        unit_id: unit_id,
        affected_units: [unit_id],
        frequency: calculate_frequency(oscillations),
        amplitude: calculate_amplitude(time_series),
        phase: calculate_phase(oscillations),
        severity: calculate_severity(oscillations, time_series),
        active: true
      }]
    else
      []
    end
  end
  
  defp extract_metric(measurement, metric) do
    Map.get(measurement, metric, 0.0)
  end
  
  defp detect_zero_crossings(time_series) do
    mean = Enum.sum(time_series) / length(time_series)
    
    time_series
    |> Enum.map(&(&1 - mean))  # Center around mean
    |> Enum.with_index()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [{v1, _}, {v2, _}] ->
      # Detect sign change
      v1 * v2 < 0
    end)
    |> Enum.map(fn [{_, i1}, {_, i2}] ->
      (i1 + i2) / 2  # Interpolated crossing point
    end)
  end
  
  defp calculate_frequency(crossings) when length(crossings) < 2, do: 0.0
  defp calculate_frequency(crossings) do
    # Average time between crossings
    periods = crossings
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [c1, c2] -> c2 - c1 end)
    
    if Enum.empty?(periods) do
      0.0
    else
      avg_period = Enum.sum(periods) / length(periods)
      1.0 / (avg_period * 2)  # Full cycle is 2 crossings
    end
  end
  
  defp calculate_amplitude(time_series) do
    if Enum.empty?(time_series) do
      0.0
    else
      max_val = Enum.max(time_series)
      min_val = Enum.min(time_series)
      (max_val - min_val) / 2
    end
  end
  
  defp calculate_phase(_crossings) do
    # Simplified phase calculation
    0.0
  end
  
  defp calculate_severity(oscillations, time_series) do
    amplitude = calculate_amplitude(time_series)
    frequency = calculate_frequency(oscillations)
    
    # Severity based on amplitude and frequency
    min(1.0, amplitude * frequency * 2)
  end
  
  defp analyze_frequencies(measurements) do
    # Simple frequency spectrum analysis
    measurements
    |> Enum.map(fn {unit_id, data} ->
      {unit_id, estimate_dominant_frequency(data)}
    end)
    |> Map.new()
  end
  
  defp estimate_dominant_frequency(measurements) when length(measurements) < 4 do
    0.0
  end
  
  defp estimate_dominant_frequency(measurements) do
    # Very simplified FFT alternative - count peaks
    series = measurements
    |> Enum.map(&extract_metric(&1, :absorption_rate))
    |> Enum.reverse()
    
    peaks = count_peaks(series)
    peaks / length(series) * 2  # Rough frequency estimate
  end
  
  defp count_peaks(series) when length(series) < 3, do: 0
  defp count_peaks(series) do
    series
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.count(fn [a, b, c] ->
      b > a and b > c  # Local maximum
    end)
  end
  
  defp generate_recommendations(oscillations) do
    oscillations
    |> Enum.map(fn osc ->
      %{
        unit_id: osc.unit_id,
        action: recommend_action(osc),
        damping_factor: recommend_damping(osc)
      }
    end)
  end
  
  defp recommend_action(oscillation) do
    cond do
      oscillation.severity > 0.8 -> :immediate_damping
      oscillation.severity > 0.5 -> :gradual_damping
      true -> :monitor
    end
  end
  
  defp recommend_damping(oscillation) do
    # Damping factor inversely proportional to frequency
    base_damping = 0.3
    frequency_factor = 1 / (1 + oscillation.frequency)
    
    min(0.9, base_damping + oscillation.severity * frequency_factor)
  end
end