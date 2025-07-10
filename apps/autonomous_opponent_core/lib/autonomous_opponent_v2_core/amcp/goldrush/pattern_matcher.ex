defmodule AutonomousOpponentV2Core.AMCP.Goldrush.PatternMatcher do
  @moduledoc """
  High-performance pattern matching engine for Goldrush event streams.
  
  Supports complex pattern matching with:
  - Value comparisons (eq, gt, lt, gte, lte, in, regex)
  - Logical operators (and, or, not)
  - Temporal patterns (within, sequence)
  - Statistical patterns (threshold, trend)
  - Semantic patterns (intent, causality)
  
  Examples:
  - Temperature alerts: %{type: :temperature, value: %{gt: 90}}
  - System overload: %{and: [%{cpu: %{gt: 80}}, %{memory: %{gt: 70}}]}
  - VSM patterns: %{source: :vsm_s1, urgency: %{gte: 0.8}}
  """
  
  require Logger
  
  @type pattern_spec :: map()
  @type compiled_pattern :: %{
    type: atom(),
    conditions: list(),
    metadata: map()
  }
  @type match_result :: {:match, map()} | :no_match
  
  @doc """
  Compiles a pattern specification into an optimized matcher.
  """
  @spec compile_pattern(pattern_spec()) :: {:ok, compiled_pattern()} | {:error, term()}
  def compile_pattern(pattern_spec) when is_map(pattern_spec) do
    try do
      compiled = do_compile_pattern(pattern_spec)
      {:ok, compiled}
    rescue
      error ->
        {:error, {:compilation_failed, error}}
    end
  end
  
  def compile_pattern(_invalid) do
    {:error, :invalid_pattern_spec}
  end
  
  @doc """
  Matches an event against a compiled pattern.
  """
  @spec match_event(compiled_pattern(), map()) :: match_result()
  def match_event(compiled_pattern, event) when is_map(event) do
    case evaluate_pattern(compiled_pattern, event) do
      {true, context} ->
        {:match, context}
      {false, _} ->
        :no_match
      false ->
        :no_match
    end
  end
  
  @doc """
  Tests if a simple key-value pattern matches.
  """
  def simple_match?(pattern, event) when is_map(pattern) and is_map(event) do
    Enum.all?(pattern, fn {key, expected} ->
      case Map.get(event, key) do
        nil -> false
        actual -> compare_values(actual, expected)
      end
    end)
  end
  
  # Pattern Compilation
  
  defp do_compile_pattern(%{and: conditions}) when is_list(conditions) do
    compiled_conditions = Enum.map(conditions, &do_compile_pattern/1)
    %{
      type: :and,
      conditions: compiled_conditions,
      metadata: %{operator: :and, count: length(conditions)}
    }
  end
  
  defp do_compile_pattern(%{or: conditions}) when is_list(conditions) do
    compiled_conditions = Enum.map(conditions, &do_compile_pattern/1)
    %{
      type: :or,
      conditions: compiled_conditions,
      metadata: %{operator: :or, count: length(conditions)}
    }
  end
  
  defp do_compile_pattern(%{not: condition}) do
    compiled_condition = do_compile_pattern(condition)
    %{
      type: :not,
      conditions: [compiled_condition],
      metadata: %{operator: :not}
    }
  end
  
  defp do_compile_pattern(%{within: time_spec, events: event_patterns}) do
    compiled_events = Enum.map(event_patterns, &do_compile_pattern/1)
    %{
      type: :temporal_within,
      conditions: compiled_events,
      metadata: %{
        time_window: parse_time_spec(time_spec),
        event_count: length(event_patterns)
      }
    }
  end
  
  defp do_compile_pattern(%{sequence: event_patterns}) when is_list(event_patterns) do
    compiled_events = Enum.map(event_patterns, &do_compile_pattern/1)
    %{
      type: :temporal_sequence,
      conditions: compiled_events,
      metadata: %{sequence_length: length(event_patterns)}
    }
  end
  
  defp do_compile_pattern(%{threshold: %{field: field, operator: op, value: val, count: count}}) do
    %{
      type: :statistical_threshold,
      conditions: [{field, op, val, count}],
      metadata: %{field: field, threshold_type: :count}
    }
  end
  
  defp do_compile_pattern(%{trend: %{field: field, direction: direction, window: window}}) do
    %{
      type: :statistical_trend,
      conditions: [{field, direction, window}],
      metadata: %{field: field, trend_type: direction}
    }
  end
  
  defp do_compile_pattern(simple_pattern) when is_map(simple_pattern) do
    # Simple field-value pattern
    conditions = Enum.map(simple_pattern, fn {field, value_spec} ->
      {field, compile_value_spec(value_spec)}
    end)
    
    %{
      type: :simple,
      conditions: conditions,
      metadata: %{fields: Map.keys(simple_pattern)}
    }
  end
  
  defp compile_value_spec(%{eq: value}), do: {:eq, value}
  defp compile_value_spec(%{gt: value}), do: {:gt, value}
  defp compile_value_spec(%{lt: value}), do: {:lt, value}
  defp compile_value_spec(%{gte: value}), do: {:gte, value}
  defp compile_value_spec(%{lte: value}), do: {:lte, value}
  defp compile_value_spec(%{in: values}) when is_list(values), do: {:in, values}
  defp compile_value_spec(%{regex: pattern}), do: {:regex, Regex.compile!(pattern)}
  defp compile_value_spec(%{contains: substring}), do: {:contains, substring}
  defp compile_value_spec(%{range: %{min: min, max: max}}), do: {:range, min, max}
  defp compile_value_spec(direct_value), do: {:eq, direct_value}
  
  # Pattern Evaluation
  
  defp evaluate_pattern(%{type: :simple, conditions: conditions}, event) do
    results = Enum.map(conditions, fn {field, value_spec} ->
      event_value = get_nested_value(event, field)
      {evaluate_value_spec(event_value, value_spec), %{field => event_value}}
    end)
    
    all_match = Enum.all?(results, fn {match, _} -> match end)
    context = results |> Enum.map(fn {_, ctx} -> ctx end) |> Enum.reduce(%{}, &Map.merge/2)
    
    {all_match, context}
  end
  
  defp evaluate_pattern(%{type: :and, conditions: conditions}, event) do
    results = Enum.map(conditions, &evaluate_pattern(&1, event))
    
    all_match = Enum.all?(results, fn {match, _} -> match end)
    context = results |> Enum.map(fn {_, ctx} -> ctx end) |> Enum.reduce(%{}, &Map.merge/2)
    
    {all_match, Map.put(context, :logical_operator, :and)}
  end
  
  defp evaluate_pattern(%{type: :or, conditions: conditions}, event) do
    results = Enum.map(conditions, &evaluate_pattern(&1, event))
    
    any_match = Enum.any?(results, fn {match, _} -> match end)
    matched_contexts = results |> Enum.filter(fn {match, _} -> match end) |> Enum.map(fn {_, ctx} -> ctx end)
    context = matched_contexts |> Enum.reduce(%{}, &Map.merge/2)
    
    {any_match, Map.put(context, :logical_operator, :or)}
  end
  
  defp evaluate_pattern(%{type: :not, conditions: [condition]}, event) do
    {match, context} = evaluate_pattern(condition, event)
    {not match, Map.put(context, :logical_operator, :not)}
  end
  
  defp evaluate_pattern(%{type: :temporal_within, metadata: %{time_window: window}, conditions: event_conditions}, event) do
    # Full temporal pattern implementation using EventStore
    alias AutonomousOpponentV2Core.AMCP.Temporal.EventStore
    alias AutonomousOpponentV2Core.VSM.Clock
    
    case Clock.now() do
      {:ok, current_time} ->
        window_start = current_time.physical - window
        
        # Get events in time window
        window_events = EventStore.get_events_in_window(
          %{physical: window_start, logical: 0, node_id: ""},
          current_time,
          []
        )
        
        # Check if required events occurred within window
        matches = Enum.map(event_conditions, fn condition ->
          count_matching_events(window_events, condition)
        end)
        
        required_matches = length(event_conditions)
        actual_matches = Enum.count(matches, & &1 > 0)
        
        match_result = actual_matches >= required_matches
        
        context = %{
          pattern_type: :temporal_within,
          time_window: window,
          window_events: length(window_events),
          required_matches: required_matches,
          actual_matches: actual_matches,
          match_details: matches
        }
        
        Logger.debug("Temporal within pattern: #{match_result} (#{actual_matches}/#{required_matches} conditions met)")
        {match_result, context}
        
      {:error, error} ->
        Logger.error("Failed to get current time for temporal pattern: #{inspect(error)}")
        {false, %{pattern_type: :temporal_within, error: error}}
    end
  end
  
  defp evaluate_pattern(%{type: :temporal_sequence, conditions: sequence_conditions, metadata: metadata}, event) do
    # Full temporal sequence implementation
    alias AutonomousOpponentV2Core.AMCP.Temporal.EventStore
    alias AutonomousOpponentV2Core.VSM.Clock
    
    sequence_length = metadata[:sequence_length] || length(sequence_conditions)
    max_sequence_time = metadata[:max_sequence_time] || 30_000  # 30s default
    
    case Clock.now() do
      {:ok, current_time} ->
        # Get recent events for sequence analysis
        window_start = current_time.physical - max_sequence_time
        
        window_events = EventStore.get_events_in_window(
          %{physical: window_start, logical: 0, node_id: ""},
          current_time,
          []
        )
        
        # Order events by HLC timestamp
        ordered_events = Clock.order_events(window_events)
        
        # Find matching sequences
        sequence_match = find_temporal_sequence(ordered_events, sequence_conditions, max_sequence_time)
        
        context = %{
          pattern_type: :temporal_sequence,
          sequence_length: sequence_length,
          max_sequence_time: max_sequence_time,
          window_events: length(window_events),
          sequence_found: sequence_match != nil
        }
        
        if sequence_match do
          context = Map.merge(context, %{
            sequence_events: sequence_match.events,
            sequence_duration: sequence_match.duration,
            sequence_start: sequence_match.start_time
          })
          Logger.debug("Temporal sequence pattern matched: #{length(sequence_match.events)} events over #{sequence_match.duration}ms")
          {true, context}
        else
          Logger.debug("Temporal sequence pattern not matched")
          {false, context}
        end
        
      {:error, error} ->
        Logger.error("Failed to get current time for sequence pattern: #{inspect(error)}")
        {false, %{pattern_type: :temporal_sequence, error: error}}
    end
  end
  
  defp evaluate_pattern(%{type: :statistical_threshold, conditions: [{field, operator, value, count}], metadata: metadata}, event) do
    # Full statistical threshold implementation
    alias AutonomousOpponentV2Core.AMCP.Temporal.EventStore
    alias AutonomousOpponentV2Core.VSM.Clock
    
    window_ms = metadata[:window_ms] || 60_000  # 1 minute default
    
    case Clock.now() do
      {:ok, current_time} ->
        window_start = current_time.physical - window_ms
        
        # Get events in statistical window
        window_events = EventStore.get_events_in_window(
          %{physical: window_start, logical: 0, node_id: ""},
          current_time,
          []
        )
        
        # Extract field values for statistical analysis
        field_values = Enum.map(window_events, fn event ->
          get_nested_value(event, field)
        end)
        |> Enum.filter(& &1 != nil)
        
        # Apply threshold condition
        matching_values = Enum.filter(field_values, fn val ->
          apply_statistical_operator(val, operator, value)
        end)
        
        threshold_met = length(matching_values) >= count
        
        context = %{
          pattern_type: :statistical_threshold,
          field: field,
          operator: operator,
          threshold_value: value,
          required_count: count,
          actual_count: length(matching_values),
          total_events: length(window_events),
          window_ms: window_ms
        }
        
        Logger.debug("Statistical threshold pattern: #{threshold_met} (#{length(matching_values)}/#{count} required)")
        {threshold_met, context}
        
      {:error, error} ->
        Logger.error("Failed to get current time for statistical pattern: #{inspect(error)}")
        {false, %{pattern_type: :statistical_threshold, error: error}}
    end
  end
  
  defp evaluate_pattern(%{type: :statistical_trend, conditions: [{field, direction, window}], metadata: metadata}, event) do
    # Full statistical trend implementation
    alias AutonomousOpponentV2Core.AMCP.Temporal.EventStore
    alias AutonomousOpponentV2Core.VSM.Clock
    
    window_ms = window || 300_000  # 5 minutes default
    min_data_points = metadata[:min_data_points] || 5
    trend_threshold = metadata[:trend_threshold] || 0.1
    
    case Clock.now() do
      {:ok, current_time} ->
        window_start = current_time.physical - window_ms
        
        # Get events for trend analysis
        window_events = EventStore.get_events_in_window(
          %{physical: window_start, logical: 0, node_id: ""},
          current_time,
          []
        )
        
        # Extract time series data
        time_series = Enum.map(window_events, fn event ->
          value = get_nested_value(event, field)
          if value != nil and is_number(value) do
            {event.timestamp.physical, value}
          else
            nil
          end
        end)
        |> Enum.filter(& &1 != nil)
        |> Enum.sort_by(fn {timestamp, _} -> timestamp end)
        
        if length(time_series) >= min_data_points do
          # Calculate trend using linear regression
          trend_result = calculate_trend(time_series)
          trend_detected = detect_trend_direction(trend_result, direction, trend_threshold)
          
          context = %{
            pattern_type: :statistical_trend,
            field: field,
            direction: direction,
            window_ms: window_ms,
            data_points: length(time_series),
            trend_slope: trend_result.slope,
            trend_r_squared: trend_result.r_squared,
            trend_detected: trend_detected
          }
          
          Logger.debug("Statistical trend pattern: #{trend_detected} (slope: #{trend_result.slope}, direction: #{direction})")
          {trend_detected, context}
        else
          context = %{
            pattern_type: :statistical_trend,
            field: field,
            direction: direction,
            window_ms: window_ms,
            data_points: length(time_series),
            insufficient_data: true
          }
          
          Logger.debug("Statistical trend pattern: insufficient data (#{length(time_series)} < #{min_data_points})")
          {false, context}
        end
        
      {:error, error} ->
        Logger.error("Failed to get current time for trend pattern: #{inspect(error)}")
        {false, %{pattern_type: :statistical_trend, error: error}}
    end
  end
  
  # Catch-all clause for unknown pattern types
  defp evaluate_pattern(_pattern, _event) do
    false
  end
  
  # Value Comparison
  
  defp evaluate_value_spec(value, {:eq, expected}), do: value == expected
  defp evaluate_value_spec(value, {:gt, expected}) when is_number(value) and is_number(expected), do: value > expected
  defp evaluate_value_spec(value, {:lt, expected}) when is_number(value) and is_number(expected), do: value < expected
  defp evaluate_value_spec(value, {:gte, expected}) when is_number(value) and is_number(expected), do: value >= expected
  defp evaluate_value_spec(value, {:lte, expected}) when is_number(value) and is_number(expected), do: value <= expected
  defp evaluate_value_spec(value, {:in, list}) when is_list(list), do: value in list
  defp evaluate_value_spec(value, {:regex, regex}) when is_binary(value), do: Regex.match?(regex, value)
  defp evaluate_value_spec(value, {:contains, substring}) when is_binary(value) and is_binary(substring) do
    String.contains?(value, substring)
  end
  defp evaluate_value_spec(value, {:range, min, max}) when is_number(value), do: value >= min and value <= max
  defp evaluate_value_spec(_value, _spec), do: false
  
  # Helper Functions
  
  defp get_nested_value(map, key) when is_atom(key) or is_binary(key) do
    Map.get(map, key) || Map.get(map, to_string(key)) || Map.get(map, String.to_atom(to_string(key)))
  end
  
  defp get_nested_value(map, path) when is_list(path) do
    Enum.reduce(path, map, fn key, acc ->
      case acc do
        %{} -> get_nested_value(acc, key)
        _ -> nil
      end
    end)
  end
  
  defp compare_values(actual, expected) when is_map(expected) do
    # Handle complex value specifications
    case expected do
      %{gt: val} -> is_number(actual) and actual > val
      %{lt: val} -> is_number(actual) and actual < val
      %{gte: val} -> is_number(actual) and actual >= val
      %{lte: val} -> is_number(actual) and actual <= val
      %{in: list} -> actual in list
      %{regex: pattern} -> is_binary(actual) and Regex.match?(Regex.compile!(pattern), actual)
      %{contains: substring} -> is_binary(actual) and String.contains?(actual, substring)
      _ -> actual == expected
    end
  end
  
  defp compare_values(actual, expected) do
    actual == expected
  end
  
  defp parse_time_spec(time_spec) when is_binary(time_spec) do
    # Parse time specifications like "5s", "2m", "1h"
    case Regex.run(~r/(\d+)([smh])/, time_spec) do
      [_, amount, unit] ->
        amount = String.to_integer(amount)
        case unit do
          "s" -> amount * 1000
          "m" -> amount * 60 * 1000
          "h" -> amount * 60 * 60 * 1000
        end
      _ ->
        5000  # Default 5 seconds
    end
  end
  
  defp parse_time_spec(time_spec) when is_integer(time_spec), do: time_spec
  
  @doc """
  Pre-built patterns for common VSM scenarios.
  """
  def vsm_patterns do
    %{
      high_urgency: %{urgency: %{gte: 0.8}},
      algedonic_pain: %{type: :algedonic, valence: %{lt: 0}},
      algedonic_pleasure: %{type: :algedonic, valence: %{gt: 0}},
      s1_overload: %{source: :vsm_s1, variety_pressure: %{gt: 0.9}},
      s2_coordination_failure: %{source: :vsm_s2, coordination_success: %{lt: 0.5}},
      s3_resource_exhaustion: %{source: :vsm_s3, resource_usage: %{gt: 0.95}},
      s4_intelligence_anomaly: %{source: :vsm_s4, anomaly_score: %{gt: 0.8}},
      s5_policy_violation: %{source: :vsm_s5, policy_compliance: %{lt: 0.7}},
      system_overload: %{
        and: [
          %{cpu_util: %{gt: 80}},
          %{memory_util: %{gt: 70}},
          %{urgency: %{gte: 0.6}}
        ]
      },
      consciousness_state_change: %{
        source: :consciousness,
        state: %{in: ["awakening", "focused", "distributed", "dormant"]}
      }
    }
  end
  
  @doc """
  Gets a pre-built VSM pattern by name.
  """
  def get_vsm_pattern(pattern_name) do
    Map.get(vsm_patterns(), pattern_name)
  end
  
  # Temporal Pattern Helper Functions
  
  defp count_matching_events(events, condition) do
    Enum.count(events, fn event ->
      evaluate_simple_condition(event, condition)
    end)
  end
  
  defp evaluate_simple_condition(event, condition) do
    Enum.all?(condition, fn {field, value_spec} ->
      event_value = get_nested_value(event, field)
      compare_values(event_value, value_spec)
    end)
  end
  
  defp find_temporal_sequence(ordered_events, sequence_conditions, max_sequence_time) do
    sequence_length = length(sequence_conditions)
    
    # Try to find a sequence starting from each event
    Enum.reduce_while(ordered_events, nil, fn start_event, acc ->
      case find_sequence_from_event(start_event, ordered_events, sequence_conditions, max_sequence_time) do
        nil -> {:cont, acc}
        sequence -> {:halt, sequence}
      end
    end)
  end
  
  defp find_sequence_from_event(start_event, all_events, [first_condition | rest_conditions], max_time) do
    # Check if start event matches first condition
    if evaluate_simple_condition(start_event, first_condition) do
      # Find remaining events in sequence
      find_remaining_sequence(start_event, all_events, rest_conditions, max_time, [start_event])
    else
      nil
    end
  end
  
  defp find_remaining_sequence(_start_event, _all_events, [], _max_time, found_events) do
    # Sequence complete
    first_event = hd(found_events)
    last_event = List.last(found_events)
    duration = last_event.timestamp.physical - first_event.timestamp.physical
    
    %{
      events: found_events,
      duration: duration,
      start_time: first_event.timestamp.physical
    }
  end
  
  defp find_remaining_sequence(start_event, all_events, [next_condition | rest], max_time, found_events) do
    last_found = List.last(found_events)
    cutoff_time = start_event.timestamp.physical + max_time
    
    # Find next event that matches condition and is after last found event
    next_event = Enum.find(all_events, fn event ->
      event.timestamp.physical > last_found.timestamp.physical and
      event.timestamp.physical <= cutoff_time and
      evaluate_simple_condition(event, next_condition)
    end)
    
    if next_event do
      find_remaining_sequence(start_event, all_events, rest, max_time, found_events ++ [next_event])
    else
      nil
    end
  end
  
  defp apply_statistical_operator(value, operator, threshold) when is_number(value) and is_number(threshold) do
    case operator do
      :gt -> value > threshold
      :gte -> value >= threshold
      :lt -> value < threshold
      :lte -> value <= threshold
      :eq -> value == threshold
      _ -> false
    end
  end
  
  defp apply_statistical_operator(_value, _operator, _threshold), do: false
  
  defp calculate_trend(time_series) when length(time_series) < 2 do
    %{slope: 0, r_squared: 0, insufficient_data: true}
  end
  
  defp calculate_trend(time_series) do
    # Simple linear regression for trend calculation
    n = length(time_series)
    
    {sum_x, sum_y, sum_xy, sum_x2} = Enum.reduce(time_series, {0, 0, 0, 0}, fn {x, y}, {sx, sy, sxy, sx2} ->
      {sx + x, sy + y, sxy + (x * y), sx2 + (x * x)}
    end)
    
    mean_x = sum_x / n
    mean_y = sum_y / n
    
    # Calculate slope (b)
    numerator = sum_xy - (n * mean_x * mean_y)
    denominator = sum_x2 - (n * mean_x * mean_x)
    
    slope = if denominator != 0, do: numerator / denominator, else: 0
    
    # Calculate R-squared (coefficient of determination)
    y_pred_sum = Enum.reduce(time_series, 0, fn {x, y}, acc ->
      y_pred = mean_y + slope * (x - mean_x)
      acc + (y - y_pred) * (y - y_pred)
    end)
    
    y_mean_sum = Enum.reduce(time_series, 0, fn {_x, y}, acc ->
      acc + (y - mean_y) * (y - mean_y)
    end)
    
    r_squared = if y_mean_sum != 0, do: 1 - (y_pred_sum / y_mean_sum), else: 0
    
    %{
      slope: slope,
      r_squared: max(0, r_squared),
      data_points: n
    }
  end
  
  defp detect_trend_direction(%{slope: slope}, direction, threshold) do
    case direction do
      :increasing -> slope > threshold
      :decreasing -> slope < -threshold
      :stable -> abs(slope) <= threshold
      _ -> false
    end
  end
end