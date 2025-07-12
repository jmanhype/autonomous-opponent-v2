defmodule AutonomousOpponentV2Core.Integration.PatternFlowIntegrationTest do
  @moduledoc """
  Integration tests for complete pattern flow from PatternDetector to S4 Intelligence.
  Tests the end-to-end scenarios for Issue #92 implementation.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias AutonomousOpponent.VSM.S4.Intelligence
  alias AutonomousOpponent.EventBus
  alias AutonomousOpponentV2Core.AMCP.Temporal.PatternDetector
  alias AutonomousOpponentV2Core.AMCP.Temporal.EventStore
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.PatternFixtures

  setup do
    # Start EventBus if not already started
    case Process.whereis(AutonomousOpponent.EventBus) do
      nil -> {:ok, _} = EventBus.start_link()
      _ -> :ok
    end

    # Start required components
    {:ok, s4_pid} = Intelligence.start_link(id: "test_s4_integration")
    {:ok, _event_store} = EventStore.start_link()
    {:ok, pattern_detector} = PatternDetector.start_link()

    # Subscribe to relevant events for verification
    EventBus.subscribe(:s4_emergency_strategy)
    EventBus.subscribe(:s5_intelligence_alert)
    EventBus.subscribe(:s3_intelligence_alert)
    EventBus.subscribe(:vsm_pattern_flow)
    EventBus.subscribe(:vsm_s4_patterns)

    on_exit(fn ->
      # Clean up
      try do
        GenServer.stop(s4_pid, :normal, 1000)
        GenServer.stop(EventStore, :normal, 1000)
        GenServer.stop(pattern_detector, :normal, 1000)
      catch
        _, _ -> :ok
      end
    end)

    {:ok, s4_pid: s4_pid, pattern_detector: pattern_detector}
  end

  describe "end-to-end pattern flow" do
    test "pattern detected by PatternDetector → received and processed by S4 → strategy updated",
         %{s4_pid: s4_pid} do
      # Create a critical error cascade pattern
      pattern =
        PatternFixtures.error_cascade_pattern(%{
          pattern_name: "integration_test_cascade",
          severity: :critical,
          confidence: 0.9
        })

      log =
        capture_log(fn ->
          # Simulate pattern detection
          PatternDetector.emit_pattern_detection(pattern)

          # Allow time for full processing chain
          Process.sleep(200)
        end)

      # Verify pattern flow through logs
      assert log =~ "Pattern detected and sent to S4 Intelligence: error_cascade"
      assert log =~ "S4: Received pattern - error_cascade/integration_test_cascade"
      assert log =~ "S4: Strategy updated based on error_cascade pattern"

      # Verify S4 state was updated
      state = :sys.get_state(s4_pid)

      # Check environmental model
      assert state.environmental_model[:error_cascade] != nil
      assert state.environmental_model[:error_cascade].count >= 1

      # Check strategy update
      strategy = get_in(state.intelligence_reports, [:current_strategy])
      assert strategy[:monitoring_intensity] == :maximum
      assert strategy[:prediction_horizon] == :short_term
    end

    test "high urgency patterns trigger emergency strategy mode", %{s4_pid: s4_pid} do
      # Create an algedonic storm pattern with extreme urgency
      pattern =
        PatternFixtures.algedonic_storm_pattern(%{
          pattern_name: "emergency_test_storm",
          emergency_level: :extreme,
          urgency: 0.95
        })

      log =
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
          Process.sleep(200)
        end)

      # Verify emergency flow
      assert log =~ "URGENT S4 environmental signal: algedonic_storm"
      assert log =~ "CRITICAL environmental pattern detected - applying emergency strategy"
      assert log =~ "EMERGENCY STRATEGY ACTIVATED"

      # Verify emergency strategy event was published
      assert_receive {:event, :s4_emergency_strategy, strategy_event}, 500
      assert strategy_event.strategy.mode == :emergency
      assert strategy_event.strategy.activated_by == :algedonic_storm

      # Verify S4 emergency state
      state = :sys.get_state(s4_pid)
      emergency_strategy = get_in(state.intelligence_reports, [:emergency_strategy])
      assert emergency_strategy[:mode] == :emergency
      assert emergency_strategy[:algedonic_bypass] == true
    end

    test "pattern storage in HNSW with similarity search", %{s4_pid: s4_pid} do
      # Send multiple similar patterns
      patterns = [
        PatternFixtures.error_cascade_pattern(%{
          pattern_name: "cascade_1",
          confidence: 0.85
        }),
        PatternFixtures.error_cascade_pattern(%{
          pattern_name: "cascade_2",
          confidence: 0.88
        }),
        PatternFixtures.error_cascade_pattern(%{
          pattern_name: "cascade_3",
          confidence: 0.82
        })
      ]

      # Send patterns
      Enum.each(patterns, fn pattern ->
        capture_log(fn ->
          PatternDetector.emit_pattern_detection(pattern)
          Process.sleep(100)
        end)
      end)

      # Verify patterns were stored in cache
      state = :sys.get_state(s4_pid)
      cache_keys = Map.keys(state.pattern_cache || %{})

      # Should have cached all high-confidence patterns
      assert length(cache_keys) >= 3
      assert Enum.any?(cache_keys, &String.contains?(&1, "error_cascade"))
    end

    test "multiple concurrent patterns processed correctly", %{s4_pid: s4_pid} do
      # Create diverse patterns
      patterns = [
        PatternFixtures.error_cascade_pattern(%{pattern_name: "concurrent_1"}),
        PatternFixtures.coordination_breakdown_pattern(%{pattern_name: "concurrent_2"}),
        PatternFixtures.rate_burst_pattern(%{pattern_name: "concurrent_3"}),
        PatternFixtures.variety_overload_pattern(%{pattern_name: "concurrent_4"})
      ]

      # Send all patterns concurrently
      tasks =
        Enum.map(patterns, fn pattern ->
          Task.async(fn ->
            capture_log(fn ->
              PatternDetector.emit_pattern_detection(pattern)
            end)
          end)
        end)

      # Wait for all tasks
      Enum.each(tasks, &Task.await(&1, 5000))

      # Allow processing time
      Process.sleep(300)

      # Verify all patterns were processed
      state = :sys.get_state(s4_pid)

      # Check environmental model has entries for different pattern types
      assert Map.has_key?(state.environmental_model, :error_cascade)
      assert Map.has_key?(state.environmental_model, :coordination_breakdown)
      assert Map.has_key?(state.environmental_model, :rate_burst)
      assert Map.has_key?(state.environmental_model, :variety_overload)
    end

    test "EventBus routing under load conditions", %{s4_pid: s4_pid} do
      # Generate high volume of patterns
      pattern_count = 100
      patterns = PatternFixtures.generate_pattern_batch(pattern_count, :mixed)

      start_time = System.monotonic_time(:millisecond)

      # Send all patterns rapidly
      log =
        capture_log(fn ->
          Enum.each(patterns, fn pattern ->
            PatternDetector.emit_pattern_detection(pattern)
          end)

          # Wait for processing
          Process.sleep(1000)
        end)

      end_time = System.monotonic_time(:millisecond)
      processing_time = end_time - start_time

      # Should handle load without errors
      refute log =~ "Error"
      refute log =~ "crash"

      # Processing should complete in reasonable time
      # Less than 3 seconds for 100 patterns
      assert processing_time < 3000

      # S4 should still be healthy
      assert Process.alive?(s4_pid)

      # Verify patterns were processed
      state = :sys.get_state(s4_pid)
      assert map_size(state.environmental_model) > 0
    end

    test "low confidence patterns are filtered out", %{s4_pid: s4_pid} do
      # Send mix of high and low confidence patterns
      patterns = [
        PatternFixtures.error_cascade_pattern(%{
          pattern_name: "high_conf",
          confidence: 0.85
        }),
        PatternFixtures.low_confidence_pattern(%{
          pattern_name: "low_conf",
          confidence: 0.45
        }),
        PatternFixtures.coordination_breakdown_pattern(%{
          pattern_name: "medium_high_conf",
          confidence: 0.72
        })
      ]

      logs =
        capture_log(fn ->
          Enum.each(patterns, fn pattern ->
            PatternDetector.emit_pattern_detection(pattern)
            Process.sleep(100)
          end)
        end)

      # Low confidence pattern should be noted but not stored
      assert logs =~ "Pattern below confidence threshold"

      # Verify only high confidence patterns in cache
      state = :sys.get_state(s4_pid)
      cache_entries = Map.values(state.pattern_cache || %{})

      stored_patterns =
        Enum.map(cache_entries, fn entry ->
          entry.pattern.pattern_name
        end)

      assert "high_conf" in stored_patterns
      assert "medium_high_conf" in stored_patterns
      refute "low_conf" in stored_patterns
    end

    test "VSM subsystem alerts for critical patterns" do
      # Create extreme urgency pattern
      pattern =
        PatternFixtures.algedonic_storm_pattern(%{
          pattern_name: "vsm_alert_test",
          urgency: 0.95,
          emergency_level: :extreme
        })

      capture_log(fn ->
        PatternDetector.emit_pattern_detection(pattern)
        Process.sleep(200)
      end)

      # Should receive S5 policy alert
      assert_receive {:event, :s5_intelligence_alert, s5_alert}, 500
      assert s5_alert.pattern_type == :algedonic_storm
      assert s5_alert.s4_recommendation == :immediate_policy_review
      assert s5_alert.environmental_impact == :critical

      # Should receive S3 control alert
      assert_receive {:event, :s3_intelligence_alert, s3_alert}, 500
      assert s3_alert.pattern_type == :algedonic_storm
      assert s3_alert.control_implications == :immediate_adjustment
      assert is_list(s3_alert.recommended_actions)
    end

    test "pattern indexing notifications update S4 metrics", %{s4_pid: s4_pid} do
      # Send some patterns first
      patterns = PatternFixtures.generate_pattern_batch(5, :mixed)

      Enum.each(patterns, fn pattern ->
        PatternDetector.emit_pattern_detection(pattern)
      end)

      Process.sleep(200)

      # Send indexing notification
      indexing_event = PatternFixtures.pattern_indexing_event(250)
      EventBus.publish(:patterns_indexed, indexing_event)

      Process.sleep(100)

      # Verify S4 updated its metrics
      state = :sys.get_state(s4_pid)
      index_health = get_in(state.health_metrics, [:pattern_index_health])

      assert index_health != nil
      assert index_health.patterns_indexed == 250
      assert index_health.index_health == :healthy
    end

    test "temporal patterns receive enhanced processing", %{s4_pid: s4_pid} do
      # Create temporal pattern
      temporal_pattern =
        PatternFixtures.rate_burst_pattern(%{
          pattern_name: "temporal_test",
          temporal_analysis: true
        })

      log =
        capture_log(fn ->
          # Publish as temporal pattern
          EventBus.publish(:temporal_pattern_detected, temporal_pattern)
          Process.sleep(200)
        end)

      # Should be processed with temporal enhancement
      assert log =~ "S4: Received temporal pattern"

      # Verify it was stored
      state = :sys.get_state(s4_pid)
      assert Map.has_key?(state.environmental_model, :rate_burst)
    end
  end

  describe "error resilience in pattern flow" do
    test "system continues after pattern processing errors", %{s4_pid: s4_pid} do
      # Send malformed pattern
      malformed = PatternFixtures.malformed_pattern()

      # Then send valid pattern
      valid =
        PatternFixtures.error_cascade_pattern(%{
          pattern_name: "valid_after_error"
        })

      capture_log(fn ->
        PatternDetector.emit_pattern_detection(malformed)
        Process.sleep(100)
        PatternDetector.emit_pattern_detection(valid)
        Process.sleep(200)
      end)

      # System should still be running
      assert Process.alive?(s4_pid)

      # Valid pattern should have been processed
      state = :sys.get_state(s4_pid)
      assert Map.has_key?(state.environmental_model, :error_cascade)
    end

    test "handles EventBus overload gracefully", %{s4_pid: s4_pid} do
      # Send burst of patterns
      patterns = PatternFixtures.generate_pattern_batch(500, :mixed)

      # Send all at once to stress EventBus
      capture_log(fn ->
        Enum.each(patterns, fn pattern ->
          spawn(fn ->
            PatternDetector.emit_pattern_detection(pattern)
          end)
        end)

        # Wait for dust to settle
        Process.sleep(2000)
      end)

      # System should survive
      assert Process.alive?(s4_pid)

      # Should have processed at least some patterns
      state = :sys.get_state(s4_pid)
      assert map_size(state.environmental_model) > 0
    end
  end

  describe "VSM pattern flow events" do
    test "publishes to VSM pattern channels", %{s4_pid: _s4_pid} do
      pattern = PatternFixtures.coordination_breakdown_pattern()

      capture_log(fn ->
        PatternDetector.emit_pattern_detection(pattern)
        Process.sleep(500)
      end)

      # Should receive VSM pattern flow events
      # These are published by S4 after processing
      assert_receive {:event, :vsm_pattern_flow, vsm_pattern}, 1000
      assert vsm_pattern.type == "s4_pattern_event"

      assert_receive {:event, :vsm_s4_patterns, s4_pattern}, 1000
      assert s4_pattern.type == "s4_pattern_event"
    end
  end
end
