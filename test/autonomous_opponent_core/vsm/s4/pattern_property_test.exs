defmodule AutonomousOpponentV2Core.VSM.S4.PatternPropertyTest do
  @moduledoc """
  Property-based tests for pattern processing in S4 Intelligence.
  Tests system properties with randomized pattern data.
  """

  use ExUnit.Case
  import ExUnit.CaptureLog

  alias AutonomousOpponent.VSM.S4.Intelligence
  alias AutonomousOpponent.EventBus
  alias AutonomousOpponentV2Core.AMCP.Temporal.PatternDetector
  alias AutonomousOpponentV2Core.VSM.Clock

  setup do
    # Start EventBus if not already started
    case Process.whereis(AutonomousOpponent.EventBus) do
      nil -> {:ok, _} = EventBus.start_link()
      _ -> :ok
    end

    {:ok, s4_pid} = Intelligence.start_link(id: "test_s4_property")

    {:ok, s4_pid: s4_pid}
  end

  # Random data generators
  @pattern_types [
    :error_cascade,
    :algedonic_storm,
    :coordination_breakdown,
    :consciousness_instability,
    :rate_burst,
    :variety_overload,
    :environmental_shift,
    :unknown_pattern
  ]

  @severities [:critical, :high, :medium, :low]
  @emergency_levels [nil, :low, :medium, :high, :critical, :extreme]
  @subsystems [:s1, :s2, :s3, :s4, :s5]

  defp random_pattern_type, do: Enum.random(@pattern_types)
  defp random_severity, do: Enum.random(@severities)
  defp random_confidence, do: :rand.uniform()
  defp random_urgency, do: :rand.uniform()
  defp random_emergency_level, do: Enum.random(@emergency_levels)

  defp random_subsystems do
    count = :rand.uniform(5) - 1
    Enum.take_random(@subsystems, count)
  end

  defp random_timestamp do
    {:ok, base} = Clock.now()
    offset = :rand.uniform(1_000_000)

    %{
      physical: base.physical + offset,
      logical: rem(offset, 1000),
      node_id: base.node_id
    }
  end

  defp generate_random_pattern do
    %{
      pattern_type: random_pattern_type(),
      pattern_name: "random_pattern_#{:rand.uniform(10000)}",
      severity: random_severity(),
      confidence: random_confidence(),
      emergency_level: random_emergency_level(),
      affected_subsystems: random_subsystems(),
      timestamp: random_timestamp(),
      source: :temporal_pattern_detector,
      actual_rate: :rand.uniform(1000),
      threshold: :rand.uniform(500) + 1,
      duration_ms: :rand.uniform(3_600_000),
      urgency: random_urgency()
    }
  end

  describe "pattern processing properties" do
    test "any valid pattern should be processable by S4 without crashes", %{s4_pid: s4_pid} do
      # Test with 100 random patterns
      for _ <- 1..100 do
        pattern = generate_random_pattern()

        # Add required environmental context
        enhanced_pattern =
          Map.merge(pattern, %{
            environmental_context: %{
              affected_subsystems: pattern.affected_subsystems,
              variety_pressure: :rand.uniform(),
              temporal_characteristics: %{
                duration: pattern.duration_ms,
                frequency: pattern.actual_rate,
                trend: :stable
              },
              system_stress_indicators: []
            },
            vsm_impact: %{
              impact_level: :moderate,
              variety_pressure: :rand.uniform(),
              cybernetic_implications: [:environmental_variation],
              affected_control_loops: [:monitoring_loop]
            },
            s4_processing_priority: :normal
          })

        # Process pattern
        result =
          capture_log(fn ->
            send(s4_pid, {:event, :pattern_detected, enhanced_pattern})
            Process.sleep(50)
          end)

        # Should not crash
        assert Process.alive?(s4_pid)

        # Should log reception (unless confidence too low)
        if enhanced_pattern.confidence >= 0.7 do
          assert result =~ "S4: Received pattern"
        end

        # Should not have errors
        refute result =~ "Error storing pattern in vector store"
        refute result =~ "crash"
      end
    end

    test "pattern confidence values 0.0-1.0 handled correctly", %{s4_pid: s4_pid} do
      # Test with 50 random confidence values
      for _ <- 1..50 do
        confidence = random_confidence()
        pattern = create_test_pattern_with_confidence(confidence)

        log =
          capture_log(fn ->
            send(s4_pid, {:event, :pattern_detected, pattern})
            Process.sleep(50)
          end)

        # Should process without errors
        assert Process.alive?(s4_pid)

        # Verify confidence threshold behavior
        if confidence >= 0.7 do
          refute log =~ "Pattern below confidence threshold"
        else
          assert log =~ "Pattern below confidence threshold" or
                   log =~ "not storing"
        end
      end
    end

    test "urgency calculations always return 0.0-1.0 range" do
      # Test with 100 random patterns through actual event publishing
      for _ <- 1..100 do
        pattern = generate_random_pattern()
        # Make it urgent enough to generate environmental signal
        urgent_pattern =
          Map.merge(pattern, %{
            pattern_type:
              Enum.random([:error_cascade, :algedonic_storm, :coordination_breakdown]),
            emergency_level: :critical
          })

        # Process through emit function to test urgency calculation
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(urgent_pattern)
        end)

        # Check if environmental signal was sent (for urgent patterns)
        receive do
          {:event, :s4_environmental_signal, signal} ->
            assert signal.urgency >= 0.0
            assert signal.urgency <= 1.0
            assert is_float(signal.urgency)
        after
          # Not all patterns generate signals
          100 -> :ok
        end
      end
    end

    test "environmental model updates preserve data integrity", %{s4_pid: s4_pid} do
      # Test with 20 batches of random patterns
      for _ <- 1..20 do
        pattern_count = :rand.uniform(10)
        patterns = for _ <- 1..pattern_count, do: generate_random_pattern()

        # Send all patterns
        Enum.each(patterns, fn pattern ->
          enhanced_pattern = enhance_pattern_for_s4(pattern)
          send(s4_pid, {:event, :pattern_detected, enhanced_pattern})
        end)

        Process.sleep(100 * length(patterns))

        # Get state
        state = :sys.get_state(s4_pid)

        # Verify environmental model integrity
        assert is_map(state.environmental_model)

        # Each pattern type should have valid structure if present
        Enum.each(state.environmental_model, fn {key, value} ->
          if is_atom(key) and key != :environmental_complexity do
            assert is_map(value)
            assert Map.has_key?(value, :count)
            assert value.count >= 1
            assert is_list(value.severity_history)
            assert is_list(value.vsm_impacts)
          end
        end)

        # Environmental complexity should be in valid range
        if Map.has_key?(state.environmental_model, :environmental_complexity) do
          complexity = state.environmental_model.environmental_complexity
          assert complexity >= 0.0
          assert complexity <= 1.0
        end
      end
    end
  end

  describe "pattern severity properties" do
    test "severity determination is consistent" do
      # Test with 50 random patterns through event publishing
      for _ <- 1..50 do
        pattern_type = random_pattern_type()
        # 0.5 to 3.0
        rate_multiplier = 0.5 + :rand.uniform() * 2.5

        pattern =
          enhance_pattern_for_s4(%{
            pattern_type: pattern_type,
            pattern_name: "severity_test",
            actual_rate: round(100 * rate_multiplier),
            threshold: 100,
            confidence: 0.8,
            timestamp: random_timestamp(),
            source: :temporal_pattern_detector
          })

        # Subscribe to events
        EventBus.subscribe(:pattern_detected)

        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)

        assert_receive {:event, :pattern_detected, s4_pattern}, 500
        severity = s4_pattern.severity

        # Verify severity is valid
        assert severity in [:critical, :high, :medium, :low, :minimal]

        # Verify consistency rules
        case pattern_type do
          :error_cascade -> assert severity == :critical
          :algedonic_storm -> assert severity == :critical
          :coordination_breakdown -> assert severity == :high
          :consciousness_instability -> assert severity == :high
          :rate_burst when rate_multiplier > 2.0 -> assert severity == :high
          _ -> assert severity in [:medium, :low, :minimal, :high]
        end

        EventBus.unsubscribe(:pattern_detected)
      end
    end
  end

  describe "pattern priority properties" do
    test "emergency level always overrides base priority" do
      # Test with 50 random combinations through event publishing
      for _ <- 1..50 do
        pattern_type = random_pattern_type()
        emergency_level = random_emergency_level()

        pattern =
          enhance_pattern_for_s4(%{
            pattern_type: pattern_type,
            pattern_name: "priority_test",
            emergency_level: emergency_level,
            confidence: 0.8,
            timestamp: random_timestamp(),
            source: :temporal_pattern_detector
          })

        EventBus.subscribe(:pattern_detected)

        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)

        assert_receive {:event, :pattern_detected, s4_pattern}, 500
        priority = s4_pattern.s4_processing_priority

        # Verify priority is valid
        assert priority in [:immediate, :high, :normal, :low]

        # Verify emergency override
        case emergency_level do
          :extreme ->
            assert priority == :immediate

          :critical ->
            assert priority == :immediate

          :high ->
            assert priority == :high

          _ ->
            # Should follow base priority rules
            case pattern_type do
              p when p in [:error_cascade, :algedonic_storm] ->
                assert priority == :immediate

              p when p in [:coordination_breakdown, :consciousness_instability] ->
                assert priority == :high

              :rate_burst ->
                assert priority == :normal

              _ ->
                assert priority == :low
            end
        end

        EventBus.unsubscribe(:pattern_detected)
      end
    end
  end

  describe "pattern cache properties" do
    test "cache size remains bounded under any pattern load", %{s4_pid: s4_pid} do
      # Test with 5 different pattern loads
      for _ <- 1..5 do
        # 100 to 1000
        pattern_count = 100 + :rand.uniform(900)
        patterns = for _ <- 1..pattern_count, do: generate_random_pattern()

        # Send all patterns
        Enum.each(patterns, fn pattern ->
          enhanced_pattern = enhance_pattern_for_s4(pattern)
          send(s4_pid, {:event, :pattern_detected, enhanced_pattern})
        end)

        # Allow processing
        Process.sleep(min(pattern_count * 10, 2000))

        # Verify cache bounds
        state = :sys.get_state(s4_pid)
        cache_size = map_size(state.pattern_cache || %{})

        # Cache should never exceed limit
        assert cache_size <= 10_000

        # Process should still be healthy
        assert Process.alive?(s4_pid)
      end
    end
  end

  describe "variety pressure properties" do
    test "variety pressure calculations stay in valid range" do
      # Test with 100 random patterns through published events
      for _ <- 1..100 do
        pattern = enhance_pattern_for_s4(generate_random_pattern())

        EventBus.subscribe(:pattern_detected)

        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)

        assert_receive {:event, :pattern_detected, s4_pattern}, 500

        # Check variety pressure in VSM impact
        pressure = s4_pattern.vsm_impact.variety_pressure

        # Should be non-negative
        assert pressure >= 0.0

        # Should have reasonable upper bound
        assert pressure <= 2.0

        EventBus.unsubscribe(:pattern_detected)
      end
    end
  end

  describe "temporal trend properties" do
    test "temporal trends are mutually exclusive" do
      # Test with 50 random patterns through published events
      for _ <- 1..50 do
        base_pattern = generate_random_pattern()
        # 0.5 to 2.0
        intensity_escalation = 0.5 + :rand.uniform() * 1.5

        enhanced_pattern =
          enhance_pattern_for_s4(
            Map.put(base_pattern, :intensity_escalation, intensity_escalation)
          )

        EventBus.subscribe(:pattern_detected)

        capture_log(fn ->
          PatternDetector.emit_pattern_detection(enhanced_pattern)
        end)

        assert_receive {:event, :pattern_detected, s4_pattern}, 500
        trend = s4_pattern.environmental_context.temporal_characteristics.trend

        # Trend should be one of the valid values
        assert trend in [:escalating, :increasing, :critical_spike, :stable]

        # Only one trend should apply
        trends = [:escalating, :increasing, :critical_spike, :stable]
        assert Enum.count(trends, &(&1 == trend)) == 1

        EventBus.unsubscribe(:pattern_detected)
      end
    end
  end

  # Helper functions
  defp create_test_pattern_with_confidence(confidence) do
    {:ok, timestamp} = Clock.now()

    %{
      pattern_type: :test_pattern,
      pattern_name: "confidence_test_#{confidence}",
      confidence: confidence,
      severity: :medium,
      environmental_context: %{
        affected_subsystems: [],
        variety_pressure: 0.5,
        temporal_characteristics: %{
          duration: 1000,
          frequency: 10,
          trend: :stable
        },
        system_stress_indicators: []
      },
      vsm_impact: %{
        impact_level: :moderate,
        variety_pressure: 0.5,
        cybernetic_implications: [],
        affected_control_loops: []
      },
      timestamp: timestamp,
      source: :temporal_pattern_detector,
      s4_processing_priority: :normal
    }
  end

  defp enhance_pattern_for_s4(pattern) do
    Map.merge(pattern, %{
      environmental_context: %{
        affected_subsystems: pattern.affected_subsystems || [],
        variety_pressure: :rand.uniform(),
        temporal_characteristics: %{
          duration: pattern.duration_ms || 1000,
          frequency: pattern.actual_rate || 10,
          trend: :stable
        },
        system_stress_indicators: []
      },
      vsm_impact: %{
        impact_level: :moderate,
        variety_pressure: :rand.uniform(),
        cybernetic_implications: [:environmental_variation],
        affected_control_loops: [:monitoring_loop]
      },
      s4_processing_priority: :normal
    })
  end
end
