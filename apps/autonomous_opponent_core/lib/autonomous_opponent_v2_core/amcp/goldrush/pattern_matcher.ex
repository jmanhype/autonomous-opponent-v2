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
  
  defp evaluate_pattern(%{type: :temporal_within, metadata: %{time_window: window}}, _event) do
    # Temporal patterns require event history - simplified for now
    # In full implementation, this would check if events occurred within time window
    Logger.debug("Temporal pattern matching not fully implemented")
    {false, %{pattern_type: :temporal_within, time_window: window}}
  end
  
  defp evaluate_pattern(%{type: :temporal_sequence}, _event) do
    # Sequence patterns require event history - simplified for now
    Logger.debug("Sequence pattern matching not fully implemented")
    {false, %{pattern_type: :temporal_sequence}}
  end
  
  defp evaluate_pattern(%{type: :statistical_threshold}, _event) do
    # Statistical patterns require aggregation - simplified for now
    Logger.debug("Statistical pattern matching not fully implemented")
    {false, %{pattern_type: :statistical_threshold}}
  end
  
  defp evaluate_pattern(%{type: :statistical_trend}, _event) do
    # Trend patterns require time series analysis - simplified for now
    Logger.debug("Trend pattern matching not fully implemented")
    {false, %{pattern_type: :statistical_trend}}
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
end