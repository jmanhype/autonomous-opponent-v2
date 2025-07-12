defmodule AutonomousOpponentV2Core.AMCP.Temporal.PatternDetectorS4Test do
  @moduledoc """
  Unit tests for PatternDetector S4 publishing functionality.
  Tests the S4-specific event publishing implemented for Issue #92.
  """
  
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias AutonomousOpponentV2Core.AMCP.Temporal.PatternDetector
  alias AutonomousOpponent.EventBus
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.PatternFixtures

  setup do
    # Start EventBus if not already started
    case Process.whereis(AutonomousOpponent.EventBus) do
      nil -> {:ok, _} = EventBus.start_link()
      _ -> :ok
    end

    # Subscribe to S4-specific events
    EventBus.subscribe(:pattern_detected)
    EventBus.subscribe(:temporal_pattern_detected)
    EventBus.subscribe(:s4_environmental_signal)
    EventBus.subscribe(:algedonic_signal)
    
    :ok
  end

  describe "emit_pattern_detection/1 S4 event publishing" do
    test "publishes pattern_detected event for all pattern types" do
      patterns = [
        create_test_pattern(:error_cascade),
        create_test_pattern(:algedonic_storm),
        create_test_pattern(:coordination_breakdown),
        create_test_pattern(:consciousness_instability),
        create_test_pattern(:rate_burst),
        create_test_pattern(:variety_overload)
      ]
      
      Enum.each(patterns, fn pattern ->
        log = capture_log(fn ->
          send(self(), {:emit_test, pattern})
          PatternDetector.emit_pattern_detection(pattern)
          Process.sleep(50)
        end)
        
        assert log =~ "Pattern detected and sent to S4 Intelligence: #{pattern.pattern_type}"
        
        # Verify pattern_detected event
        assert_receive {:event, :pattern_detected, s4_pattern}, 500
        assert s4_pattern.pattern_type == pattern.pattern_type
        assert s4_pattern.pattern_name == pattern.pattern_name
        assert s4_pattern.source == :temporal_pattern_detector
        assert s4_pattern.environmental_context != nil
        assert s4_pattern.vsm_impact != nil
      end)
    end

    test "includes proper S4 pattern structure" do
      pattern = create_test_pattern(:error_cascade, %{confidence: 0.85})
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(pattern)
      end)
      
      assert_receive {:event, :pattern_detected, s4_pattern}, 500
      
      # Verify all required S4 fields
      assert s4_pattern.pattern_type == :error_cascade
      assert s4_pattern.pattern_name == "test_error_cascade"
      assert s4_pattern.severity == :critical
      assert s4_pattern.confidence == 0.85
      assert s4_pattern.source == :temporal_pattern_detector
      assert s4_pattern.s4_processing_priority == :immediate
      
      # Verify environmental context
      assert is_map(s4_pattern.environmental_context)
      assert s4_pattern.environmental_context.variety_pressure > 0
      assert is_list(s4_pattern.environmental_context.affected_subsystems)
      assert is_map(s4_pattern.environmental_context.temporal_characteristics)
      
      # Verify VSM impact
      assert is_map(s4_pattern.vsm_impact)
      assert s4_pattern.vsm_impact.impact_level == :severe
      assert s4_pattern.vsm_impact.variety_pressure > 0
      assert is_list(s4_pattern.vsm_impact.cybernetic_implications)
      assert is_list(s4_pattern.vsm_impact.affected_control_loops)
    end

    test "publishes urgent S4 environmental signal for critical patterns" do
      critical_pattern = create_test_pattern(:error_cascade, %{
        emergency_level: :critical,
        severity: :critical
      })
      
      log = capture_log(fn ->
        PatternDetector.emit_pattern_detection(critical_pattern)
      end)
      
      assert log =~ "URGENT S4 environmental signal: error_cascade"
      
      # Should receive both pattern_detected and s4_environmental_signal
      assert_receive {:event, :pattern_detected, _}, 500
      assert_receive {:event, :s4_environmental_signal, signal}, 500
      
      assert signal.type == :pattern_alert
      assert signal.urgency >= 0.8
      assert is_list(signal.recommended_s4_actions)
      assert signal.environmental_impact != nil
      assert signal.pattern.pattern_type == :error_cascade
    end

    test "publishes algedonic signal for extreme emergency patterns" do
      extreme_pattern = create_test_pattern(:algedonic_storm, %{
        emergency_level: :extreme
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(extreme_pattern)
      end)
      
      # Should receive algedonic signal
      assert_receive {:event, :algedonic_signal, algedonic}, 500
      
      assert algedonic.type == :pain
      assert algedonic.source == :temporal_pattern_detector
      assert algedonic.valence == -0.9
      assert algedonic.urgency == 1.0
      assert algedonic.data.pattern_type == :algedonic_storm
    end

    test "does not publish urgent signal for low severity patterns" do
      low_pattern = create_test_pattern(:rate_burst, %{
        severity: :low,
        emergency_level: nil,
        actual_rate: 150,
        threshold: 100
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(low_pattern)
      end)
      
      # Should receive pattern_detected but not s4_environmental_signal
      assert_receive {:event, :pattern_detected, _}, 500
      refute_receive {:event, :s4_environmental_signal, _}, 200
    end
  end

  describe "severity determination through event publishing" do
    test "published patterns have correct severity" do
      # Test severity determination through published events
      patterns_and_severities = [
        {:error_cascade, :critical},
        {:algedonic_storm, :critical},
        {:coordination_breakdown, :high},
        {:consciousness_instability, :high}
      ]
      
      Enum.each(patterns_and_severities, fn {type, expected_severity} ->
        pattern = create_test_pattern(type)
        
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)
        
        assert_receive {:event, :pattern_detected, s4_pattern}, 500
        assert s4_pattern.severity == expected_severity
      end)
    end

    test "rate_burst severity based on threshold exceedance" do
      # Rate burst with high exceedance
      high_rate = create_test_pattern(:rate_burst, %{
        actual_rate: 250,
        threshold: 100
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(high_rate)
      end)
      
      assert_receive {:event, :pattern_detected, s4_pattern}, 500
      assert s4_pattern.severity == :high
      
      # Rate burst with moderate exceedance
      moderate_rate = create_test_pattern(:rate_burst, %{
        actual_rate: 150,
        threshold: 100
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(moderate_rate)
      end)
      
      assert_receive {:event, :pattern_detected, s4_pattern}, 500
      assert s4_pattern.severity == :medium
    end
  end

  describe "environmental context in published events" do
    test "published patterns include complete environmental context" do
      pattern = create_test_pattern(:error_cascade, %{
        affected_subsystems: [:s1, :s2, :s3],
        duration_ms: 300_000,
        actual_rate: 150,
        emergency_level: :critical
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(pattern)
      end)
      
      assert_receive {:event, :pattern_detected, s4_pattern}, 500
      context = s4_pattern.environmental_context
      
      assert context.affected_subsystems == [:s1, :s2, :s3]
      assert context.variety_pressure > 0
      assert context.temporal_characteristics.duration == 300_000
      assert context.temporal_characteristics.frequency == 150
      assert context.temporal_characteristics.trend != nil
      assert is_list(context.system_stress_indicators)
    end

    test "handles missing fields with defaults" do
      minimal_pattern = create_test_pattern(:unknown_pattern)
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(minimal_pattern)
      end)
      
      assert_receive {:event, :pattern_detected, s4_pattern}, 500
      context = s4_pattern.environmental_context
      
      assert context.affected_subsystems == []
      assert context.variety_pressure >= 0
      assert context.temporal_characteristics.duration >= 0
      assert context.temporal_characteristics.frequency >= 0
      assert context.temporal_characteristics.trend == :stable
      assert is_list(context.system_stress_indicators)
    end
  end

  describe "VSM impact in published events" do
    test "published patterns have correct impact levels" do
      impact_tests = [
        {:error_cascade, :severe},
        {:algedonic_storm, :severe},
        {:coordination_breakdown, :moderate},
        {:consciousness_instability, :moderate},
        {:rate_burst, :mild},
        {:unknown_pattern, :minimal}
      ]
      
      Enum.each(impact_tests, fn {type, expected_level} ->
        pattern = create_test_pattern(type)
        
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)
        
        assert_receive {:event, :pattern_detected, s4_pattern}, 500
        impact = s4_pattern.vsm_impact
        
        assert impact.impact_level == expected_level
        assert impact.variety_pressure >= 0
        assert is_list(impact.cybernetic_implications)
        assert is_list(impact.affected_control_loops)
      end)
    end

    test "includes subsystem-specific control loops" do
      pattern = create_test_pattern(:coordination_breakdown, %{
        affected_subsystems: [:s1, :s2]
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(pattern)
      end)
      
      assert_receive {:event, :pattern_detected, s4_pattern}, 500
      impact = s4_pattern.vsm_impact
      
      assert :coordination_loop in impact.affected_control_loops
      assert :s1_control_loop in impact.affected_control_loops
      assert :s2_control_loop in impact.affected_control_loops
    end
  end

  describe "S4 priority in published events" do
    test "published patterns have correct base priorities" do
      priority_tests = [
        {:error_cascade, :immediate},
        {:algedonic_storm, :immediate},
        {:coordination_breakdown, :high},
        {:consciousness_instability, :high},
        {:rate_burst, :normal},
        {:unknown_pattern, :low}
      ]
      
      Enum.each(priority_tests, fn {type, expected} ->
        pattern = create_test_pattern(type)
        
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)
        
        assert_receive {:event, :pattern_detected, s4_pattern}, 500
        assert s4_pattern.s4_processing_priority == expected
      end)
    end

    test "emergency level overrides base priority" do
      # Normal pattern with extreme emergency
      pattern = create_test_pattern(:rate_burst, %{
        emergency_level: :extreme
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(pattern)
      end)
      
      assert_receive {:event, :pattern_detected, s4_pattern}, 500
      assert s4_pattern.s4_processing_priority == :immediate
    end
  end

  describe "urgent S4 attention through environmental signals" do
    test "urgent patterns generate environmental signals" do
      urgent_patterns = [
        create_test_pattern(:error_cascade, %{emergency_level: :critical}),
        create_test_pattern(:algedonic_storm),
        create_test_pattern(:coordination_breakdown, %{severity: :critical}),
        create_test_pattern(:rate_burst, %{actual_rate: 400, threshold: 100})
      ]
      
      Enum.each(urgent_patterns, fn pattern ->
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)
        
        # Should receive environmental signal for urgent patterns
        assert_receive {:event, :s4_environmental_signal, _}, 500
      end)
    end

    test "non-urgent patterns don't generate environmental signals" do
      non_urgent_patterns = [
        create_test_pattern(:rate_burst, %{severity: :low}),
        create_test_pattern(:unknown_pattern),
        create_test_pattern(:variety_overload, %{actual_rate: 120, threshold: 100})
      ]
      
      Enum.each(non_urgent_patterns, fn pattern ->
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)
        
        # Should NOT receive environmental signal
        refute_receive {:event, :s4_environmental_signal, _}, 200
      end)
    end
  end

  describe "pattern urgency in environmental signals" do
    test "environmental signals contain urgency in 0.0-1.0 range" do
      patterns = [
        create_test_pattern(:error_cascade, %{emergency_level: :critical}),
        create_test_pattern(:algedonic_storm),
        create_test_pattern(:coordination_breakdown, %{severity: :critical})
      ]
      
      Enum.each(patterns, fn pattern ->
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)
        
        assert_receive {:event, :s4_environmental_signal, signal}, 500
        assert signal.urgency >= 0.0
        assert signal.urgency <= 1.0
      end)
    end

    test "urgency edge cases in signals" do
      # High urgency pattern
      extreme_pattern = create_test_pattern(:error_cascade, %{
        severity: :critical,
        emergency_level: :extreme
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(extreme_pattern)
      end)
      
      assert_receive {:event, :s4_environmental_signal, signal}, 500
      # Should be very high but capped at 1.0
      assert signal.urgency >= 0.9
      assert signal.urgency <= 1.0
    end
  end

  describe "S4 actions in environmental signals" do
    test "environmental signals contain appropriate actions" do
      action_tests = [
        {:error_cascade, [:increase_monitoring, :prepare_isolation, :alert_s3_control, :scenario_modeling]},
        {:algedonic_storm, [:emergency_intervention, :isolate_pain_sources, :activate_s5_policy, :immediate_analysis]},
        {:coordination_breakdown, [:restore_s2_sync, :reallocate_s1_resources, :enhance_monitoring, :coordination_analysis]}
      ]
      
      Enum.each(action_tests, fn {type, expected_actions} ->
        pattern = create_test_pattern(type, %{emergency_level: :critical})
        
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)
        
        assert_receive {:event, :s4_environmental_signal, signal}, 500
        assert signal.recommended_s4_actions == expected_actions
      end)
    end
  end

  describe "environmental impact assessment in signals" do
    test "environmental signals contain correct impact assessment" do
      impact_tests = [
        {:error_cascade, :cascading_failure_risk},
        {:algedonic_storm, :system_stress_critical},
        {:coordination_breakdown, :coordination_degradation}
      ]
      
      Enum.each(impact_tests, fn {type, expected_impact} ->
        pattern = create_test_pattern(type, %{emergency_level: :critical})
        
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)
        
        assert_receive {:event, :s4_environmental_signal, signal}, 500
        assert signal.environmental_impact == expected_impact
      end)
    end
  end

  describe "pattern metadata in published events" do
    test "variety pressure is calculated for rate patterns" do
      # High rate exceedance
      high_rate_pattern = create_test_pattern(:rate_burst, %{
        actual_rate: 300,
        threshold: 100
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(high_rate_pattern)
      end)
      
      assert_receive {:event, :pattern_detected, s4_pattern}, 500
      # High rate should have high variety pressure
      assert s4_pattern.vsm_impact.variety_pressure > 0.8
      
      # Moderate rate
      moderate_pattern = create_test_pattern(:rate_burst, %{
        actual_rate: 120,
        threshold: 100
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(moderate_pattern)
      end)
      
      assert_receive {:event, :pattern_detected, s4_pattern}, 500
      # Moderate rate should have lower variety pressure
      assert s4_pattern.vsm_impact.variety_pressure < 1.0
    end

    test "temporal trends are identified in environmental context" do
      # Test different patterns that should have different trends
      patterns = [
        create_test_pattern(:error_cascade, %{intensity_escalation: 1.5}),
        create_test_pattern(:rate_burst, %{actual_rate: 200, threshold: 100}),
        create_test_pattern(:algedonic_storm, %{emergency_level: :critical})
      ]
      
      Enum.each(patterns, fn pattern ->
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
        end)
        
        assert_receive {:event, :pattern_detected, s4_pattern}, 500
        trend = s4_pattern.environmental_context.temporal_characteristics.trend
        assert trend in [:escalating, :increasing, :critical_spike, :stable]
      end)
    end

    test "stress indicators are included in environmental context" do
      stressed_pattern = create_test_pattern(:error_cascade, %{
        emergency_level: :critical,
        actual_rate: 250,
        threshold: 100
      })
      
      capture_log(fn ->
        PatternDetector.emit_pattern_detection(stressed_pattern)
      end)
      
      assert_receive {:event, :pattern_detected, s4_pattern}, 500
      indicators = s4_pattern.environmental_context.system_stress_indicators
      
      assert is_list(indicators)
      # Should have stress indicators due to critical emergency and high rate
      assert length(indicators) > 0
    end
  end

  # Helper function to create test patterns
  defp create_test_pattern(type, attrs \\ %{}) do
    {:ok, timestamp} = Clock.now()
    
    base = %{
      pattern_type: type,
      pattern_name: "test_#{type}",
      timestamp: timestamp,
      confidence: 0.8
    }
    
    Map.merge(base, attrs)
  end
end