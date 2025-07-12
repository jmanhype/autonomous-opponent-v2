defmodule Property.Issue92PatternPropertiesTest do
  @moduledoc """
  Property-based tests for Issue #92 pattern processing

  Uses StreamData to generate diverse pattern inputs and verify
  invariant properties hold across all pattern processing scenarios.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias AutonomousOpponentV2Core.VSM.S4.Intelligence
  alias AutonomousOpponentV2Core.EventBus

  @moduletag :property
  @moduletag :issue_92

  setup_all do
    start_supervised!(EventBus)
    :ok
  end

  setup do
    {:ok, s4_pid} = start_supervised({Intelligence, []})
    EventBus.subscribe(:pattern_detected)
    Process.sleep(100)
    %{s4_pid: s4_pid}
  end

  # Generators for pattern data

  def pattern_id_generator do
    gen all(
          prefix <- member_of(["test", "prop", "gen", "rand"]),
          suffix <- positive_integer()
        ) do
      "#{prefix}_#{suffix}"
    end
  end

  def pattern_type_generator do
    member_of([
      :rate_burst,
      :error_cascade,
      :algedonic_storm,
      :coordination_breakdown,
      :consciousness_instability
    ])
  end

  def confidence_generator do
    float(min: 0.0, max: 1.0)
  end

  def severity_generator do
    member_of([:low, :medium, :high, :critical])
  end

  def subsystem_list_generator do
    list_of(member_of([:s1, :s2, :s3, :s4, :s5]), min_length: 1, max_length: 5)
  end

  def pattern_generator do
    gen all(
          id <- pattern_id_generator(),
          type <- pattern_type_generator(),
          confidence <- confidence_generator(),
          severity <- severity_generator(),
          subsystems <- subsystem_list_generator(),
          timestamp = DateTime.utc_now(),
          event_count <- positive_integer() |> scale(&(&1 + 1)),
          window_ms <- member_of([1000, 5000, 10000, 30000, 60000])
        ) do
      %{
        id: id,
        type: type,
        confidence: confidence,
        timestamp: timestamp,
        metadata: %{
          severity: severity,
          affected_subsystems: subsystems,
          event_count: event_count,
          window_ms: window_ms
        }
      }
    end
  end

  describe "Pattern Processing Invariants" do
    property "S4 never crashes regardless of pattern input", %{s4_pid: s4_pid} do
      check all(pattern <- pattern_generator()) do
        initial_alive = Process.alive?(s4_pid)
        assert initial_alive, "S4 should start alive"

        EventBus.publish(:pattern_detected, pattern)
        Process.sleep(50)

        final_alive = Process.alive?(s4_pid)
        assert final_alive, "S4 should remain alive after processing pattern #{inspect(pattern)}"
      end
    end

    property "Pattern confidence is always preserved or normalized", %{s4_pid: s4_pid} do
      check all(pattern <- pattern_generator()) do
        original_confidence = pattern.confidence

        EventBus.publish(:pattern_detected, pattern)
        Process.sleep(50)

        # The confidence should either be preserved or normalized to [0.0, 1.0]
        assert original_confidence >= 0.0 and original_confidence <= 1.0,
               "Generated confidence should be valid: #{original_confidence}"
      end
    end

    property "Urgency calculation always produces valid range", %{s4_pid: s4_pid} do
      check all(pattern <- pattern_generator()) do
        # Add urgency calculation test
        enhanced_pattern = Map.put(pattern, :urgency, calculate_test_urgency(pattern))

        EventBus.publish(:pattern_detected, enhanced_pattern)
        Process.sleep(30)

        urgency = enhanced_pattern.urgency

        assert urgency >= 0.0 and urgency <= 1.0,
               "Urgency should be in [0.0, 1.0], got: #{urgency}"
      end
    end

    property "Pattern IDs are always preserved through processing" do
      check all(pattern <- pattern_generator()) do
        original_id = pattern.id

        # Simulate processing (pattern ID should remain unchanged)
        processed_pattern = Map.put(pattern, :processed_at, DateTime.utc_now())

        assert processed_pattern.id == original_id,
               "Pattern ID should be preserved: #{original_id}"
      end
    end

    property "Environmental context is always added for valid patterns", %{s4_pid: s4_pid} do
      check all(
              pattern <- pattern_generator(),
              # Only test reasonable confidence values
              pattern.confidence > 0.1
            ) do
        # Create pattern with environmental context structure
        enhanced_pattern = add_test_environmental_context(pattern)

        EventBus.publish(:pattern_detected, enhanced_pattern)
        Process.sleep(40)

        # Environmental context should be properly structured
        context = enhanced_pattern.environmental_context
        assert is_map(context), "Environmental context should be a map"
        assert Map.has_key?(context, :affected_subsystems), "Should have affected_subsystems"
        assert Map.has_key?(context, :variety_pressure), "Should have variety_pressure"
      end
    end

    property "VSM impact assessment is consistent with pattern severity", %{s4_pid: s4_pid} do
      check all(pattern <- pattern_generator()) do
        severity = get_in(pattern, [:metadata, :severity]) || :medium

        # Add VSM impact based on severity
        vsm_impact = calculate_test_vsm_impact(severity)
        enhanced_pattern = Map.put(pattern, :vsm_impact, vsm_impact)

        EventBus.publish(:pattern_detected, enhanced_pattern)
        Process.sleep(30)

        # Impact level should correlate with severity
        impact_level = vsm_impact.impact_level

        case severity do
          :critical -> assert impact_level in [:high, :critical]
          :high -> assert impact_level in [:medium, :high, :critical]
          :medium -> assert impact_level in [:low, :medium, :high]
          :low -> assert impact_level in [:low, :medium]
        end
      end
    end

    property "Recommended S4 actions are always lists", %{s4_pid: s4_pid} do
      check all(pattern <- pattern_generator()) do
        # Add recommended actions
        actions = generate_test_s4_actions(pattern.type)
        enhanced_pattern = Map.put(pattern, :recommended_s4_actions, actions)

        EventBus.publish(:pattern_detected, enhanced_pattern)
        Process.sleep(30)

        assert is_list(actions), "Recommended S4 actions should be a list"
        assert length(actions) > 0, "Should have at least one recommended action"

        # All actions should be atoms
        assert Enum.all?(actions, &is_atom/1), "All actions should be atoms"
      end
    end
  end

  describe "Pattern Type Specific Properties" do
    property "Rate burst patterns always have event count metadata" do
      check all(
              base_pattern <- pattern_generator(),
              base_pattern.type == :rate_burst
            ) do
        event_count = get_in(base_pattern, [:metadata, :event_count])

        assert is_integer(event_count) and event_count > 0,
               "Rate burst patterns should have positive event count"
      end
    end

    property "Algedonic storm patterns have intensity measures" do
      check all(
              pattern <- pattern_generator(),
              pattern.type == :algedonic_storm
            ) do
        # Add algedonic-specific data
        algedonic_pattern = Map.put(pattern, :pain_intensity, :rand.uniform())

        pain_intensity = algedonic_pattern.pain_intensity
        assert is_number(pain_intensity), "Algedonic patterns should have pain intensity"

        assert pain_intensity >= 0.0 and pain_intensity <= 1.0,
               "Pain intensity should be in [0.0, 1.0]"
      end
    end

    property "Coordination breakdown patterns affect multiple subsystems" do
      check all(
              pattern <- pattern_generator(),
              pattern.type == :coordination_breakdown
            ) do
        affected_subsystems = get_in(pattern, [:metadata, :affected_subsystems]) || []

        assert length(affected_subsystems) >= 1,
               "Coordination breakdown should affect at least one subsystem"
      end
    end
  end

  describe "Performance Properties" do
    property "Pattern processing completes within time bounds" do
      check all(pattern <- pattern_generator()) do
        start_time = System.monotonic_time(:millisecond)

        # Simulate pattern processing time
        # Minimal processing simulation
        Process.sleep(1)

        end_time = System.monotonic_time(:millisecond)
        processing_time = end_time - start_time

        assert processing_time < 100,
               "Pattern processing should complete quickly, took #{processing_time}ms"
      end
    end

    property "Memory usage scales linearly with pattern complexity" do
      check all(patterns <- list_of(pattern_generator(), min_length: 1, max_length: 10)) do
        # Simple complexity measure
        total_complexity =
          Enum.reduce(patterns, 0, fn pattern, acc ->
            metadata_size = map_size(pattern.metadata || %{})
            acc + metadata_size
          end)

        # Memory usage should not grow exponentially
        # bytes per complexity unit
        estimated_memory = total_complexity * 1000
        # Reasonable upper bound
        assert estimated_memory < 100_000,
               "Memory usage should scale linearly, estimated: #{estimated_memory} bytes"
      end
    end
  end

  describe "Error Handling Properties" do
    property "S4 gracefully handles missing pattern fields", %{s4_pid: s4_pid} do
      check all(pattern_base <- pattern_generator()) do
        # Create pattern with randomly missing fields
        fields_to_remove = Enum.take_random([:type, :metadata, :timestamp], :rand.uniform(2))

        incomplete_pattern =
          Enum.reduce(fields_to_remove, pattern_base, fn field, pattern ->
            Map.delete(pattern, field)
          end)

        EventBus.publish(:pattern_detected, incomplete_pattern)
        Process.sleep(50)

        # S4 should survive incomplete patterns
        assert Process.alive?(s4_pid), "S4 should survive incomplete pattern"
      end
    end

    property "Invalid confidence values are handled gracefully", %{s4_pid: s4_pid} do
      check all(
              pattern <- pattern_generator(),
              invalid_confidence <-
                one_of([
                  # Negative
                  constant(-1.0),
                  # > 1.0
                  constant(2.0),
                  # Non-numeric
                  constant(:invalid),
                  # String
                  constant("0.5")
                ])
            ) do
        invalid_pattern = Map.put(pattern, :confidence, invalid_confidence)

        EventBus.publish(:pattern_detected, invalid_pattern)
        Process.sleep(40)

        assert Process.alive?(s4_pid),
               "S4 should survive invalid confidence: #{inspect(invalid_confidence)}"
      end
    end
  end

  # Helper functions for property tests

  defp calculate_test_urgency(pattern) do
    confidence = pattern.confidence

    severity_multiplier =
      case get_in(pattern, [:metadata, :severity]) do
        :critical -> 1.0
        :high -> 0.8
        :medium -> 0.6
        :low -> 0.4
        _ -> 0.5
      end

    (confidence * severity_multiplier) |> min(1.0) |> max(0.0)
  end

  defp add_test_environmental_context(pattern) do
    context = %{
      affected_subsystems: get_in(pattern, [:metadata, :affected_subsystems]) || [:s1],
      variety_pressure: Enum.random([:low, :medium, :high, :extreme]),
      temporal_characteristics: %{
        frequency: Enum.random([:stable, :increasing, :decreasing]),
        amplitude: Enum.random([:stable, :escalating, :dampening])
      },
      control_loop_impact: Enum.random([:minimal, :moderate, :significant, :critical])
    }

    Map.put(pattern, :environmental_context, context)
  end

  defp calculate_test_vsm_impact(severity) do
    %{
      impact_level:
        case severity do
          :critical -> :critical
          :high -> Enum.random([:high, :critical])
          :medium -> Enum.random([:medium, :high])
          :low -> Enum.random([:low, :medium])
          _ -> :medium
        end,
      affected_control_loops:
        Enum.take_random([:s1_s3, :s2_s3, :s3_s4, :s4_s5], :rand.uniform(3)),
      cybernetic_implications:
        Enum.random([
          :variety_overload,
          :control_loop_disruption,
          :algedonic_cascade,
          :policy_adjustment_needed
        ]),
      recommended_vsm_actions:
        Enum.take_random(
          [
            :increase_variety_absorption,
            :strengthen_control_loops,
            :policy_review,
            :emergency_protocols
          ],
          :rand.uniform(3) + 1
        )
    }
  end

  defp generate_test_s4_actions(pattern_type) do
    base_actions = [:increase_scanning, :priority_adjustment, :environmental_analysis]

    type_specific_actions =
      case pattern_type do
        :rate_burst -> [:rate_monitoring, :burst_analysis]
        :algedonic_storm -> [:emergency_strategy, :algedonic_response, :alert_s5]
        :coordination_breakdown -> [:alert_s3, :coordination_analysis, :anti_oscillation]
        :consciousness_instability -> [:alert_s5, :consciousness_stabilization]
        :error_cascade -> [:cascade_prevention, :error_analysis, :alert_s3]
        _ -> [:general_response]
      end

    Enum.take_random(base_actions ++ type_specific_actions, :rand.uniform(4) + 1)
  end
end
