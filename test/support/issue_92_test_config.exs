defmodule Issue92TestConfig do
  @moduledoc """
  Test configuration and shared utilities for Issue #92 tests

  Provides common setup, test data generation, and assertion helpers
  for all Issue #92 test suites.
  """

  # Test timeouts
  @default_timeout 5_000
  @integration_timeout 10_000
  @performance_timeout 30_000
  @property_test_iterations 100

  # Pattern confidence thresholds
  @pattern_confidence_threshold 0.7
  @high_confidence_threshold 0.85
  @low_confidence_threshold 0.3

  # Urgency thresholds
  @high_urgency_threshold 0.8
  @medium_urgency_threshold 0.5
  @low_urgency_threshold 0.2

  def timeouts do
    %{
      default: @default_timeout,
      integration: @integration_timeout,
      performance: @performance_timeout
    }
  end

  def thresholds do
    %{
      pattern_confidence: @pattern_confidence_threshold,
      high_confidence: @high_confidence_threshold,
      low_confidence: @low_confidence_threshold,
      high_urgency: @high_urgency_threshold,
      medium_urgency: @medium_urgency_threshold,
      low_urgency: @low_urgency_threshold
    }
  end

  def property_test_config do
    %{
      iterations: @property_test_iterations,
      max_runs: 1000,
      max_shrinking_steps: 2000
    }
  end

  @doc """
  Standard test pattern for Issue #92 tests
  """
  def standard_test_pattern(overrides \\ %{}) do
    base_pattern = %{
      id: "test_pattern_#{System.unique_integer()}",
      type: :rate_burst,
      confidence: 0.85,
      timestamp: DateTime.utc_now(),
      metadata: %{
        test: true,
        source: :issue_92_test,
        event_count: 12,
        window_ms: 5000,
        threshold: 10
      }
    }

    Map.merge(base_pattern, overrides)
  end

  @doc """
  High-urgency algedonic pattern for testing emergency responses
  """
  def algedonic_storm_pattern(overrides \\ %{}) do
    base_pattern = %{
      id: "algedonic_storm_#{System.unique_integer()}",
      type: :algedonic_storm,
      confidence: 0.94,
      pain_intensity: 0.91,
      timestamp: DateTime.utc_now(),
      metadata: %{
        test: true,
        severity: :critical,
        storm_duration: 12000,
        intensity_escalation: 2.1,
        affected_subsystems: [:s1, :s2, :s3]
      }
    }

    Map.merge(base_pattern, overrides)
  end

  @doc """
  Coordination breakdown pattern for S2/S3 testing
  """
  def coordination_breakdown_pattern(overrides \\ %{}) do
    base_pattern = %{
      id: "coordination_breakdown_#{System.unique_integer()}",
      type: :coordination_breakdown,
      confidence: 0.87,
      timestamp: DateTime.utc_now(),
      metadata: %{
        test: true,
        severity: :high,
        coordination_failures: 5,
        s2_efficiency: 0.45,
        affected_subsystems: [:s1, :s2],
        urgency_indicators: [:s1_overload, :s2_failure]
      }
    }

    Map.merge(base_pattern, overrides)
  end

  @doc """
  Consciousness instability pattern for S5 policy testing
  """
  def consciousness_instability_pattern(overrides \\ %{}) do
    base_pattern = %{
      id: "consciousness_instability_#{System.unique_integer()}",
      type: :consciousness_instability,
      confidence: 0.89,
      timestamp: DateTime.utc_now(),
      metadata: %{
        test: true,
        severity: :high,
        state_changes: 7,
        entropy_level: 0.85,
        affected_consciousness_layers: [:reactive, :adaptive],
        window_ms: 120_000
      }
    }

    Map.merge(base_pattern, overrides)
  end

  @doc """
  Generate a batch of test patterns with different characteristics
  """
  def pattern_batch(count, type \\ :mixed) do
    case type do
      :mixed ->
        pattern_types = [
          :rate_burst,
          :coordination_breakdown,
          :consciousness_instability,
          :algedonic_storm
        ]

        for i <- 1..count do
          pattern_type = Enum.at(pattern_types, rem(i, length(pattern_types)))
          # 0.5-0.9
          confidence = 0.5 + :rand.uniform() * 0.4

          %{
            id: "batch_pattern_#{i}_#{System.unique_integer()}",
            type: pattern_type,
            confidence: confidence,
            timestamp: DateTime.utc_now(),
            metadata: %{
              test: true,
              batch_index: i,
              batch_type: type
            }
          }
        end

      specific_type
      when specific_type in [
             :rate_burst,
             :coordination_breakdown,
             :consciousness_instability,
             :algedonic_storm
           ] ->
        for i <- 1..count do
          standard_test_pattern(%{
            id: "#{specific_type}_batch_#{i}_#{System.unique_integer()}",
            type: specific_type,
            metadata: %{
              test: true,
              batch_index: i,
              batch_type: specific_type
            }
          })
        end
    end
  end

  @doc """
  Expected S4-enhanced pattern structure for assertions
  """
  def expected_s4_pattern_fields do
    [
      :id,
      :type,
      :confidence,
      :timestamp,
      :environmental_context,
      :vsm_impact,
      :urgency,
      :recommended_s4_actions
    ]
  end

  @doc """
  Expected environmental context fields
  """
  def expected_environmental_context_fields do
    [
      :affected_subsystems,
      :variety_pressure,
      :temporal_characteristics,
      :control_loop_impact
    ]
  end

  @doc """
  Expected VSM impact fields
  """
  def expected_vsm_impact_fields do
    [
      :impact_level,
      :affected_control_loops,
      :cybernetic_implications,
      :recommended_vsm_actions
    ]
  end

  @doc """
  Common assertion helpers for Issue #92 tests
  """
  def assert_s4_pattern_structure(pattern) do
    for field <- expected_s4_pattern_fields() do
      assert Map.has_key?(pattern, field), "Pattern should have field: #{field}"
    end

    # Validate environmental context
    if Map.has_key?(pattern, :environmental_context) do
      context = pattern.environmental_context

      for field <- expected_environmental_context_fields() do
        assert Map.has_key?(context, field), "Environmental context should have field: #{field}"
      end

      assert is_list(context.affected_subsystems), "affected_subsystems should be a list"

      assert context.variety_pressure in [:low, :medium, :high, :extreme],
             "variety_pressure should be valid"
    end

    # Validate VSM impact
    if Map.has_key?(pattern, :vsm_impact) do
      vsm_impact = pattern.vsm_impact

      for field <- expected_vsm_impact_fields() do
        assert Map.has_key?(vsm_impact, field), "VSM impact should have field: #{field}"
      end

      assert vsm_impact.impact_level in [:low, :medium, :high, :critical],
             "impact_level should be valid"

      assert is_list(vsm_impact.affected_control_loops), "affected_control_loops should be a list"
    end

    # Validate urgency
    if Map.has_key?(pattern, :urgency) do
      urgency = pattern.urgency
      assert is_number(urgency), "Urgency should be a number"
      assert urgency >= 0.0 and urgency <= 1.0, "Urgency should be in [0.0, 1.0], got: #{urgency}"
    end

    # Validate recommended actions
    if Map.has_key?(pattern, :recommended_s4_actions) do
      actions = pattern.recommended_s4_actions
      assert is_list(actions), "Recommended S4 actions should be a list"
      assert Enum.all?(actions, &is_atom/1), "All recommended actions should be atoms"
    end
  end

  @doc """
  Assert that S4 environmental signal has correct structure
  """
  def assert_s4_environmental_signal_structure(signal) do
    required_fields = [:type, :urgency, :pattern, :recommended_s4_actions, :environmental_context]

    for field <- required_fields do
      assert Map.has_key?(signal, field), "Environmental signal should have field: #{field}"
    end

    assert signal.type == :pattern_alert, "Environmental signal type should be :pattern_alert"
    assert is_number(signal.urgency), "Urgency should be a number"
    assert signal.urgency >= 0.0 and signal.urgency <= 1.0, "Urgency should be in [0.0, 1.0]"
    assert is_map(signal.pattern), "Signal should contain pattern data"
    assert is_list(signal.recommended_s4_actions), "Should have recommended actions list"
    assert is_map(signal.environmental_context), "Should have environmental context"
  end

  @doc """
  Performance test helpers
  """
  def measure_processing_time(fun) do
    start_time = System.monotonic_time(:millisecond)
    result = fun.()
    end_time = System.monotonic_time(:millisecond)

    {result, end_time - start_time}
  end

  def assert_processing_time_under(time_ms, fun) do
    {result, actual_time} = measure_processing_time(fun)

    assert actual_time < time_ms,
           "Processing should complete within #{time_ms}ms, took #{actual_time}ms"

    result
  end

  @doc """
  Memory usage helpers
  """
  def get_process_memory(pid) do
    case Process.info(pid, :memory) do
      {:memory, memory} -> memory
      nil -> 0
    end
  end

  def assert_memory_growth_under(pid, max_growth_bytes, fun) do
    initial_memory = get_process_memory(pid)
    result = fun.()
    final_memory = get_process_memory(pid)

    growth = final_memory - initial_memory

    assert growth < max_growth_bytes,
           "Memory growth should be under #{max_growth_bytes} bytes, actual: #{growth}"

    result
  end

  @doc """
  Test data cleanup helpers
  """
  def cleanup_test_patterns do
    # Clear any test pattern subscriptions or cached data
    # This would be called in test teardown
    :ok
  end

  @doc """
  EventBus test helpers
  """
  def subscribe_to_test_events do
    EventBus.subscribe(:pattern_detected)
    EventBus.subscribe(:s4_environmental_signal)
    EventBus.subscribe(:s4_strategy_updated)
    EventBus.subscribe(:patterns_indexed)
  end

  def wait_for_pattern_event(timeout \\ 1000) do
    receive do
      {:event_bus, :pattern_detected, pattern} -> {:ok, pattern}
      {:event_bus, :s4_environmental_signal, signal} -> {:ok, signal}
    after
      timeout -> {:timeout, nil}
    end
  end

  def collect_pattern_events(count, timeout \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    collect_events([], count, deadline)
  end

  defp collect_events(events, 0, _deadline), do: Enum.reverse(events)

  defp collect_events(events, remaining, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      Enum.reverse(events)
    else
      receive do
        {:event_bus, :pattern_detected, pattern} ->
          collect_events([pattern | events], remaining - 1, deadline)

        {:event_bus, :s4_environmental_signal, signal} ->
          collect_events([signal | events], remaining - 1, deadline)
      after
        100 ->
          collect_events(events, remaining, deadline)
      end
    end
  end

  @doc """
  Test environment setup helpers
  """
  def setup_issue_92_test_environment do
    # Start required processes for Issue #92 testing
    children = [
      AutonomousOpponentV2Core.EventBus,
      {AutonomousOpponentV2Core.VSM.S4.Intelligence, []},
      {AutonomousOpponentV2Core.AMCP.Temporal.PatternDetector, []}
    ]

    {:ok, supervisor_pid} = Supervisor.start_link(children, strategy: :one_for_one)

    # Allow startup
    Process.sleep(200)

    supervisor_pid
  end

  def teardown_issue_92_test_environment(supervisor_pid) do
    if Process.alive?(supervisor_pid) do
      Supervisor.stop(supervisor_pid)
    end

    cleanup_test_patterns()
  end
end
