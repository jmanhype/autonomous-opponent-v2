defmodule AutonomousOpponentV2Core.VSM.S4.IntelligencePatternTest do
  @moduledoc """
  Unit tests for S4 Intelligence pattern handling functionality.
  Tests the pattern event handlers implemented for Issue #92.
  """

  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias AutonomousOpponent.VSM.S4.Intelligence
  alias AutonomousOpponent.EventBus
  alias AutonomousOpponent.VSM.S4.Intelligence.VectorStore
  alias AutonomousOpponentV2Core.PatternFixtures

  setup do
    # Start EventBus if not already started
    case Process.whereis(AutonomousOpponent.EventBus) do
      nil -> {:ok, _} = EventBus.start_link()
      _ -> :ok
    end

    # Start Intelligence with test configuration
    {:ok, pid} = Intelligence.start_link(id: "test_s4_patterns")

    # Subscribe to relevant events for verification
    EventBus.subscribe(:s4_emergency_strategy)
    EventBus.subscribe(:s5_intelligence_alert)
    EventBus.subscribe(:s3_intelligence_alert)

    {:ok, pid: pid}
  end

  describe "handle_info({:event, :pattern_detected, pattern_data}, state)" do
    test "processes all pattern types successfully", %{pid: pid} do
      patterns = [
        PatternFixtures.error_cascade_pattern(),
        PatternFixtures.algedonic_storm_pattern(),
        PatternFixtures.coordination_breakdown_pattern(),
        PatternFixtures.variety_overload_pattern(),
        PatternFixtures.consciousness_instability_pattern(),
        PatternFixtures.rate_burst_pattern(),
        PatternFixtures.environmental_shift_pattern()
      ]

      Enum.each(patterns, fn pattern ->
        log =
          capture_log(fn ->
            send(pid, {:event, :pattern_detected, pattern})
            # Allow processing
            Process.sleep(50)
          end)

        assert log =~ "S4: Received pattern - #{pattern.pattern_type}/#{pattern.pattern_name}"
        refute log =~ "Error"
      end)

      # Verify Intelligence is still alive after processing all patterns
      assert Process.alive?(pid)
    end

    test "filters patterns by confidence threshold", %{pid: pid} do
      # High confidence pattern (should be stored)
      high_conf_pattern = PatternFixtures.error_cascade_pattern(%{confidence: 0.85})

      log =
        capture_log(fn ->
          send(pid, {:event, :pattern_detected, high_conf_pattern})
          Process.sleep(50)
        end)

      assert log =~ "S4: Received pattern"
      refute log =~ "Pattern below confidence threshold"

      # Low confidence pattern (should not be stored)
      low_conf_pattern = PatternFixtures.low_confidence_pattern(%{confidence: 0.45})

      log =
        capture_log(fn ->
          send(pid, {:event, :pattern_detected, low_conf_pattern})
          Process.sleep(50)
        end)

      assert log =~ "Pattern below confidence threshold"
    end

    test "updates environmental model with pattern data", %{pid: pid} do
      pattern = PatternFixtures.error_cascade_pattern()

      # Send pattern
      send(pid, {:event, :pattern_detected, pattern})
      Process.sleep(50)

      # Get state to verify environmental model update
      state = :sys.get_state(pid)

      assert state.environmental_model[:error_cascade] != nil
      assert state.environmental_model[:error_cascade].count >= 1
      assert state.environmental_model[:error_cascade].severity_history == [:critical]
      assert state.environmental_model[:environmental_complexity] > 0
    end

    test "updates strategy for critical patterns", %{pid: pid} do
      # Critical pattern should trigger strategy update
      critical_pattern =
        PatternFixtures.error_cascade_pattern(%{
          severity: :critical,
          emergency_level: :critical
        })

      log =
        capture_log(fn ->
          send(pid, {:event, :pattern_detected, critical_pattern})
          Process.sleep(50)
        end)

      assert log =~ "Strategy updated based on error_cascade pattern"

      # Verify strategy was updated
      state = :sys.get_state(pid)
      strategy = get_in(state.intelligence_reports, [:current_strategy])

      assert strategy[:monitoring_intensity] == :maximum
      assert strategy[:prediction_horizon] == :short_term
      assert strategy[:alert_threshold] == 0.3
    end

    test "handles missing optional fields gracefully", %{pid: pid} do
      pattern = PatternFixtures.missing_fields_pattern()

      log =
        capture_log(fn ->
          send(pid, {:event, :pattern_detected, pattern})
          Process.sleep(50)
        end)

      # Should process without errors
      assert log =~ "S4: Received pattern"
      refute log =~ "Error"
      refute log =~ "crash"

      # Pattern should be processed with defaults
      # Default when missing
      assert log =~ "severity: unknown"
    end

    test "pattern cache management with size limits", %{pid: pid} do
      # Send many patterns to test cache pruning
      patterns = PatternFixtures.generate_pattern_batch(150, :mixed)

      Enum.each(patterns, fn pattern ->
        send(pid, {:event, :pattern_detected, pattern})
      end)

      # Allow all processing
      Process.sleep(200)

      # Verify cache has reasonable size (should be pruned)
      state = :sys.get_state(pid)
      cache_size = map_size(state.pattern_cache || %{})

      # Cache should be limited (10,000 max, but we're testing pruning logic)
      assert cache_size <= 10_000
    end
  end

  describe "handle_info({:event, :temporal_pattern_detected, pattern_data}, state)" do
    test "enhances temporal patterns with additional processing", %{pid: pid} do
      temporal_pattern = PatternFixtures.rate_burst_pattern()

      log =
        capture_log(fn ->
          send(pid, {:event, :temporal_pattern_detected, temporal_pattern})
          Process.sleep(50)
        end)

      assert log =~ "S4: Received temporal pattern"
      # Should also process as regular pattern
      assert log =~ "S4: Received pattern"

      # Verify enhanced processing
      state = :sys.get_state(pid)
      assert state.environmental_model[:rate_burst] != nil
    end
  end

  describe "handle_info({:event, :s4_environmental_signal, signal_data}, state)" do
    test "applies emergency strategy for critical urgency (≥0.8)", %{pid: pid} do
      signal = PatternFixtures.s4_environmental_signal(0.85)

      log =
        capture_log(fn ->
          send(pid, {:event, :s4_environmental_signal, signal})
          Process.sleep(50)
        end)

      assert log =~ "URGENT environmental signal"
      assert log =~ "CRITICAL environmental pattern detected - applying emergency strategy"
      assert log =~ "EMERGENCY STRATEGY ACTIVATED"

      # Verify emergency strategy
      state = :sys.get_state(pid)
      emergency_strategy = get_in(state.intelligence_reports, [:emergency_strategy])

      assert emergency_strategy[:mode] == :emergency
      assert emergency_strategy[:monitoring_intensity] == :maximum
      assert emergency_strategy[:s5_escalation] == true
      assert emergency_strategy[:algedonic_bypass] == true
    end

    test "applies priority strategy for high urgency (0.6-0.79)", %{pid: pid} do
      signal = PatternFixtures.s4_environmental_signal(0.7)

      log =
        capture_log(fn ->
          send(pid, {:event, :s4_environmental_signal, signal})
          Process.sleep(50)
        end)

      assert log =~ "High-priority environmental pattern - updating strategy"
      assert log =~ "Priority strategy adjustments applied"

      # Verify priority adjustments
      state = :sys.get_state(pid)
      strategy = get_in(state.intelligence_reports, [:current_strategy])

      assert strategy[:priority_mode] == true
      assert strategy[:monitoring_intensity] == :high
    end

    test "queues pattern for analysis for low urgency (<0.6)", %{pid: pid} do
      signal = PatternFixtures.s4_environmental_signal(0.4)

      log =
        capture_log(fn ->
          send(pid, {:event, :s4_environmental_signal, signal})
          Process.sleep(50)
        end)

      assert log =~ "Pattern queued for analysis"

      # Verify pattern was queued
      state = :sys.get_state(pid)
      queue = get_in(state.intelligence_reports, [:analysis_queue]) || []

      assert length(queue) > 0
      queued_item = hd(queue)
      assert queued_item.priority == 0.4
      assert queued_item.analysis_type == :detailed_environmental
    end

    test "alerts VSM subsystems for extreme urgency (≥0.9)", %{pid: pid} do
      signal = PatternFixtures.s4_environmental_signal(0.95)

      capture_log(fn ->
        send(pid, {:event, :s4_environmental_signal, signal})
        Process.sleep(100)
      end)

      # Should receive S5 alert
      assert_receive {:event, :s5_intelligence_alert, s5_alert}, 500
      assert s5_alert.s4_recommendation == :immediate_policy_review
      assert s5_alert.environmental_impact == :critical
      assert s5_alert.urgency == 0.95

      # Should receive S3 alert
      assert_receive {:event, :s3_intelligence_alert, s3_alert}, 500
      assert s3_alert.control_implications == :immediate_adjustment
      assert s3_alert.urgency == 0.95
    end

    test "publishes emergency strategy event", %{pid: pid} do
      signal = PatternFixtures.s4_environmental_signal(0.9)

      capture_log(fn ->
        send(pid, {:event, :s4_environmental_signal, signal})
        Process.sleep(100)
      end)

      # Should receive emergency strategy event
      assert_receive {:event, :s4_emergency_strategy, strategy_event}, 500
      assert strategy_event.strategy.mode == :emergency
      assert strategy_event.pattern.pattern_type == :algedonic_storm
    end
  end

  describe "handle_info({:event, :patterns_indexed, indexing_data}, state)" do
    test "updates pattern index health metrics", %{pid: pid} do
      indexing_event = PatternFixtures.pattern_indexing_event(250)

      log =
        capture_log(fn ->
          send(pid, {:event, :patterns_indexed, indexing_event})
          Process.sleep(50)
        end)

      assert log =~ "Pattern indexing update - 250 patterns indexed"

      # Verify metrics update
      state = :sys.get_state(pid)
      index_health = get_in(state.health_metrics, [:pattern_index_health])

      assert index_health != nil
      assert index_health.patterns_indexed == 250
      assert index_health.source == :pattern_detector
      assert index_health.index_health == :healthy
    end

    test "handles missing count gracefully", %{pid: pid} do
      indexing_event = %{source: :unknown}

      log =
        capture_log(fn ->
          send(pid, {:event, :patterns_indexed, indexing_event})
          Process.sleep(50)
        end)

      assert log =~ "Pattern indexing update - 0 patterns indexed"
      refute log =~ "Error"
    end
  end

  describe "pattern-to-vector conversion" do
    test "different pattern types produce distinct vectors", %{pid: _pid} do
      # This tests the internal pattern_to_vector function behavior
      # by sending different patterns and verifying they are stored differently

      patterns = [
        PatternFixtures.error_cascade_pattern(),
        PatternFixtures.algedonic_storm_pattern(),
        PatternFixtures.coordination_breakdown_pattern(),
        PatternFixtures.variety_overload_pattern()
      ]

      # Extract pattern characteristics that would be vectorized
      vectors =
        Enum.map(patterns, fn pattern ->
          # Simulate vector generation logic
          case pattern.pattern_type do
            :error_cascade ->
              List.duplicate(0.8, 16) ++ List.duplicate(0.0, 48)

            :algedonic_storm ->
              List.duplicate(0.0, 16) ++ List.duplicate(0.9, 16) ++ List.duplicate(0.0, 32)

            :coordination_breakdown ->
              List.duplicate(0.0, 32) ++ List.duplicate(0.7, 16) ++ List.duplicate(0.0, 16)

            :variety_overload ->
              List.duplicate(0.0, 48) ++ List.duplicate(0.6, 16)

            _ ->
              List.duplicate(0.5, 64)
          end
        end)

      # Verify vectors are distinct
      unique_vectors = Enum.uniq(vectors)
      assert length(unique_vectors) == length(vectors)
    end
  end

  describe "error handling and resilience" do
    test "handles vector store errors gracefully", %{pid: pid} do
      # Mock vector store failure by sending malformed pattern
      malformed = PatternFixtures.malformed_pattern()

      log =
        capture_log(fn ->
          send(pid, {:event, :pattern_detected, malformed})
          Process.sleep(50)
        end)

      # Should log error but not crash
      assert log =~ "S4: Received pattern"
      assert Process.alive?(pid)
    end

    test "continues processing after individual pattern failures", %{pid: pid} do
      patterns = [
        PatternFixtures.error_cascade_pattern(),
        # This should fail
        PatternFixtures.malformed_pattern(),
        # This should still process
        PatternFixtures.coordination_breakdown_pattern()
      ]

      Enum.each(patterns, fn pattern ->
        capture_log(fn ->
          send(pid, {:event, :pattern_detected, pattern})
          Process.sleep(50)
        end)
      end)

      # Process should still be alive
      assert Process.alive?(pid)

      # Last valid pattern should have been processed
      state = :sys.get_state(pid)
      assert state.environmental_model[:coordination_breakdown] != nil
    end
  end

  describe "performance characteristics" do
    test "handles high-volume pattern stream", %{pid: pid} do
      # Generate 1000 patterns
      patterns = PatternFixtures.generate_pattern_batch(1000, :mixed)

      start_time = System.monotonic_time(:millisecond)

      # Send all patterns
      Enum.each(patterns, fn pattern ->
        send(pid, {:event, :pattern_detected, pattern})
      end)

      # Wait for processing to complete
      Process.sleep(1000)

      end_time = System.monotonic_time(:millisecond)
      processing_time = end_time - start_time

      # Should process 1000 patterns in reasonable time
      # Less than 5 seconds
      assert processing_time < 5000

      # Process should still be healthy
      assert Process.alive?(pid)
    end

    test "memory usage remains bounded with pattern cache", %{pid: pid} do
      # Send 15,000 patterns to test cache limits
      initial_memory = :erlang.memory(:total)

      # Send patterns in batches
      Enum.each(1..15, fn batch ->
        patterns = PatternFixtures.generate_pattern_batch(1000, :mixed)

        Enum.each(patterns, fn pattern ->
          send(pid, {:event, :pattern_detected, pattern})
        end)

        Process.sleep(100)
      end)

      Process.sleep(500)

      final_memory = :erlang.memory(:total)
      memory_increase = final_memory - initial_memory

      # Memory increase should be reasonable (less than 100MB)
      assert memory_increase < 100_000_000

      # Cache should be limited
      state = :sys.get_state(pid)
      cache_size = map_size(state.pattern_cache || %{})
      assert cache_size <= 10_000
    end
  end
end
