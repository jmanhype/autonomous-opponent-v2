defmodule AutonomousOpponent.VSM.S4.PatternExtractor do
  @moduledoc """
  Pattern extraction component for S4 Intelligence.

  Extracts meaningful patterns from operational data and environmental
  scans using statistical analysis and pattern recognition algorithms.
  """

  use GenServer
  require Logger

  defstruct [
    :pattern_algorithms,
    :extraction_history,
    :pattern_cache
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def extract(server \\ __MODULE__, data_source, existing_patterns) do
    GenServer.call(server, {:extract, data_source, existing_patterns})
  end

  def extract_from_scan(server \\ __MODULE__, scan_results, pattern_library) do
    GenServer.call(server, {:extract_from_scan, scan_results, pattern_library})
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      pattern_algorithms: init_algorithms(),
      extraction_history: [],
      pattern_cache: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:extract, data_source, existing_patterns}, _from, state) do
    patterns = extract_patterns(data_source, existing_patterns, state)

    # Cache results
    cache_key = generate_cache_key(data_source)
    new_cache = Map.put(state.pattern_cache, cache_key, patterns)

    # Record extraction
    history_entry = %{
      timestamp: System.monotonic_time(:millisecond),
      source: data_source,
      patterns_found: length(patterns)
    }

    new_history = [history_entry | state.extraction_history] |> Enum.take(100)

    new_state = %{state | pattern_cache: new_cache, extraction_history: new_history}

    {:reply, patterns, new_state}
  end

  @impl true
  def handle_call({:extract_from_scan, scan_results, pattern_library}, _from, state) do
    patterns = extract_scan_patterns(scan_results, pattern_library, state)
    {:reply, patterns, state}
  end

  defp init_algorithms do
    %{
      statistical: [:mean_variance, :correlation, :regression],
      temporal: [:trend_detection, :seasonality, :cycle_analysis],
      structural: [:clustering, :graph_patterns, :hierarchy_detection],
      behavioral: [:sequence_mining, :anomaly_detection, :classification]
    }
  end

  defp extract_patterns(data_source, existing_patterns, state) do
    # Apply different pattern extraction algorithms
    patterns = []

    # Statistical patterns
    patterns = patterns ++ extract_statistical_patterns(data_source)

    # Temporal patterns
    patterns = patterns ++ extract_temporal_patterns(data_source)

    # Structural patterns
    patterns = patterns ++ extract_structural_patterns(data_source)

    # Behavioral patterns
    patterns = patterns ++ extract_behavioral_patterns(data_source)

    # Filter and score patterns
    patterns
    |> score_patterns(existing_patterns)
    |> filter_significant_patterns()
  end

  defp extract_scan_patterns(scan_results, pattern_library, state) do
    patterns = []

    # Extract patterns from entities
    if entities = scan_results[:entities] do
      patterns = patterns ++ extract_entity_patterns(entities)
    end

    # Extract patterns from relationships
    if relationships = scan_results[:relationships] do
      patterns = patterns ++ extract_relationship_patterns(relationships)
    end

    # Extract patterns from changes
    if changes = scan_results[:changes] do
      patterns = patterns ++ extract_change_patterns(changes)
    end

    # Extract patterns from anomalies
    if anomalies = scan_results[:anomalies] do
      patterns = patterns ++ extract_anomaly_patterns(anomalies)
    end

    patterns
  end

  defp extract_statistical_patterns(data) do
    patterns = []

    # Mean and variance patterns
    if numeric_data = extract_numeric_values(data) do
      mean = calculate_mean(numeric_data)
      variance = calculate_variance(numeric_data, mean)

      patterns =
        patterns ++
          [
            %{
              type: :statistical,
              subtype: :distribution,
              mean: mean,
              variance: variance,
              confidence: confidence_from_sample_size(length(numeric_data))
            }
          ]
    end

    # Correlation patterns
    if paired_data = extract_paired_values(data) do
      correlations = calculate_correlations(paired_data)

      patterns =
        patterns ++
          Enum.map(correlations, fn {pair, corr} ->
            %{
              type: :statistical,
              subtype: :correlation,
              variables: pair,
              correlation: corr,
              confidence: abs(corr)
            }
          end)
    end

    patterns
  end

  defp extract_temporal_patterns(data) do
    patterns = []

    # Time series analysis
    if time_series = extract_time_series(data) do
      # Trend detection
      trend = detect_trend(time_series)

      if trend != :none do
        patterns =
          patterns ++
            [
              %{
                type: :temporal,
                subtype: :trend,
                direction: trend,
                strength: calculate_trend_strength(time_series),
                confidence: 0.7
              }
            ]
      end

      # Seasonality detection
      if seasonality = detect_seasonality(time_series) do
        patterns =
          patterns ++
            [
              %{
                type: :temporal,
                subtype: :seasonality,
                period: seasonality.period,
                amplitude: seasonality.amplitude,
                confidence: seasonality.confidence
              }
            ]
      end
    end

    patterns
  end

  defp extract_structural_patterns(data) do
    patterns = []

    # Graph-based patterns
    if graph_data = extract_graph_structure(data) do
      # Clustering
      clusters = detect_clusters(graph_data)

      if length(clusters) > 1 do
        patterns =
          patterns ++
            [
              %{
                type: :structural,
                subtype: :clustering,
                cluster_count: length(clusters),
                cluster_sizes: Enum.map(clusters, &length/1),
                confidence: 0.6
              }
            ]
      end

      # Hierarchy detection
      if hierarchy = detect_hierarchy(graph_data) do
        patterns =
          patterns ++
            [
              %{
                type: :structural,
                subtype: :hierarchy,
                levels: hierarchy.levels,
                root_nodes: hierarchy.roots,
                confidence: 0.7
              }
            ]
      end
    end

    patterns
  end

  defp extract_behavioral_patterns(data) do
    patterns = []

    # Sequence patterns
    if sequences = extract_sequences(data) do
      frequent_sequences = mine_frequent_sequences(sequences)

      patterns =
        patterns ++
          Enum.map(frequent_sequences, fn seq ->
            %{
              type: :behavioral,
              subtype: :sequence,
              pattern: seq.pattern,
              frequency: seq.count,
              confidence: seq.count / length(sequences)
            }
          end)
    end

    # Anomaly patterns
    if anomalies = detect_behavioral_anomalies(data) do
      patterns =
        patterns ++
          Enum.map(anomalies, fn anomaly ->
            %{
              type: :behavioral,
              subtype: :anomaly,
              description: anomaly.description,
              severity: anomaly.severity,
              confidence: anomaly.confidence
            }
          end)
    end

    patterns
  end

  defp extract_entity_patterns(entities) do
    # Group entities by type
    grouped = Enum.group_by(entities, fn {_, entity} -> entity[:type] end)

    Enum.map(grouped, fn {type, entity_list} ->
      %{
        type: :entity_distribution,
        entity_type: type,
        count: length(entity_list),
        confidence: 1.0
      }
    end)
  end

  defp extract_relationship_patterns(relationships) do
    # Analyze relationship patterns
    rel_types = Enum.group_by(relationships, & &1.type)

    Enum.map(rel_types, fn {type, rels} ->
      %{
        type: :relationship_pattern,
        relationship_type: type,
        count: length(rels),
        density: calculate_relationship_density(rels),
        confidence: 0.8
      }
    end)
  end

  defp extract_change_patterns(changes) do
    # Group changes by type
    change_types = Enum.group_by(changes, & &1.type)

    Enum.map(change_types, fn {type, change_list} ->
      %{
        type: :change_pattern,
        change_type: type,
        frequency: length(change_list),
        # per minute
        rate: length(change_list) / 60.0,
        confidence: 0.9
      }
    end)
  end

  defp extract_anomaly_patterns(anomalies) do
    Enum.map(anomalies, fn {anomaly_type, value} ->
      %{
        type: :anomaly_pattern,
        anomaly_type: anomaly_type,
        severity: calculate_anomaly_severity(anomaly_type, value),
        value: value,
        confidence: 0.95
      }
    end)
  end

  defp score_patterns(patterns, existing_patterns) do
    Enum.map(patterns, fn pattern ->
      # Base score on confidence
      base_score = pattern.confidence

      # Adjust for novelty
      novelty_score = calculate_novelty(pattern, existing_patterns)

      # Adjust for significance
      significance_score = calculate_significance(pattern)

      Map.put(pattern, :score, (base_score + novelty_score + significance_score) / 3)
    end)
  end

  defp filter_significant_patterns(patterns) do
    Enum.filter(patterns, fn pattern ->
      pattern.score >= 0.5
    end)
  end

  defp generate_cache_key(data_source) do
    :erlang.phash2(data_source)
  end

  # Helper functions

  defp extract_numeric_values(data) when is_list(data) do
    Enum.filter(data, &is_number/1)
  end

  defp extract_numeric_values(data) when is_map(data) do
    data
    |> Map.values()
    |> Enum.filter(&is_number/1)
  end

  defp extract_numeric_values(_), do: nil

  defp calculate_mean([]), do: 0

  defp calculate_mean(values) do
    Enum.sum(values) / length(values)
  end

  defp calculate_variance([], _), do: 0

  defp calculate_variance(values, mean) do
    sum_squared_diff =
      values
      |> Enum.map(fn v -> :math.pow(v - mean, 2) end)
      |> Enum.sum()

    sum_squared_diff / length(values)
  end

  defp confidence_from_sample_size(size) do
    min(1.0, size / 100)
  end

  defp extract_paired_values(_data), do: nil
  defp calculate_correlations(_paired_data), do: []

  defp extract_time_series(data) when is_list(data) do
    # Try to extract time-value pairs
    if Enum.all?(data, fn item ->
         is_map(item) and Map.has_key?(item, :timestamp) and Map.has_key?(item, :value)
       end) do
      Enum.map(data, fn item -> {item.timestamp, item.value} end)
    else
      nil
    end
  end

  defp extract_time_series(_), do: nil

  defp detect_trend(time_series) when length(time_series) < 3, do: :none

  defp detect_trend(time_series) do
    values = Enum.map(time_series, fn {_, v} -> v end)

    first_third = Enum.take(values, div(length(values), 3))
    last_third = Enum.drop(values, div(length(values) * 2, 3))

    first_avg = calculate_mean(first_third)
    last_avg = calculate_mean(last_third)

    cond do
      last_avg > first_avg * 1.1 -> :increasing
      last_avg < first_avg * 0.9 -> :decreasing
      true -> :stable
    end
  end

  defp calculate_trend_strength(time_series) do
    # Simple linear regression slope
    # Placeholder
    0.5
  end

  defp detect_seasonality(_time_series) do
    # Placeholder for seasonality detection
    nil
  end

  defp extract_graph_structure(_data), do: nil
  defp detect_clusters(_graph), do: []
  defp detect_hierarchy(_graph), do: nil

  defp extract_sequences(_data), do: nil
  defp mine_frequent_sequences(_sequences), do: []
  defp detect_behavioral_anomalies(_data), do: nil

  defp calculate_relationship_density(relationships) do
    # Simple density calculation
    unique_nodes =
      relationships
      |> Enum.flat_map(fn r -> [r.from, r.to] end)
      |> Enum.uniq()
      |> length()

    if unique_nodes > 1 do
      length(relationships) / (unique_nodes * (unique_nodes - 1))
    else
      0.0
    end
  end

  defp calculate_anomaly_severity(:high_resource_usage, value) do
    cond do
      value > 0.95 -> :critical
      value > 0.9 -> :high
      true -> :medium
    end
  end

  defp calculate_anomaly_severity(_, _), do: :low

  defp calculate_novelty(pattern, existing_patterns) do
    # Check if pattern is novel
    similar_count =
      Enum.count(existing_patterns, fn existing ->
        pattern_similarity(pattern, existing) > 0.8
      end)

    if similar_count == 0, do: 1.0, else: 0.5
  end

  defp calculate_significance(pattern) do
    case pattern.type do
      :anomaly_pattern -> 0.9
      :change_pattern -> 0.8
      :behavioral -> 0.7
      :temporal -> 0.6
      _ -> 0.5
    end
  end

  defp pattern_similarity(p1, p2) do
    if p1.type == p2.type and p1[:subtype] == p2[:subtype] do
      0.9
    else
      0.1
    end
  end
end
