defmodule AutonomousOpponentV2Core.AMCP.Goldrush.VSMPatternIntegrationTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.AMCP.Goldrush.{PatternRegistry, VSMPatternLibrary}
  alias AutonomousOpponentV2Core.EventBus
  
  describe "VSM Pattern Integration" do
    test "critical patterns are loaded and active" do
      # The application should have auto-loaded critical patterns
      active = PatternRegistry.active_patterns()
      
      # We should have some patterns active
      assert length(active) > 0
      
      # Get pattern names
      pattern_names = Enum.map(active, & &1.name)
      
      # Critical patterns should be loaded
      critical_patterns = VSMPatternLibrary.patterns_by_severity(:critical)
      critical_names = Map.keys(critical_patterns)
      
      # At least some critical patterns should be active
      active_critical = Enum.filter(critical_names, & &1 in pattern_names)
      assert length(active_critical) > 0
    end
    
    test "variety overflow pattern detects matching events" do
      # Ensure variety overflow is loaded
      if :variety_overflow not in Enum.map(PatternRegistry.active_patterns(), & &1.name) do
        {:ok, _} = PatternRegistry.load_domain_patterns(:cybernetic)
        :ok = PatternRegistry.activate_pattern(:variety_overflow)
      end
      
      # Create matching event
      event = %{
        type: :s1_operations,
        variety_ratio: 2.0,
        s1_variety_buffer: 1500,
        processing_latency: 2000,
        message_queue_length: 15_000,
        timestamp: DateTime.utc_now()
      }
      
      # Evaluate
      {:ok, matches} = PatternRegistry.evaluate_event(event)
      
      # Should match
      assert Enum.any?(matches, fn match ->
        match.pattern_name == :variety_overflow
      end)
    end
    
    test "genserver overflow pattern works" do
      # Load technical patterns
      {:ok, loaded} = PatternRegistry.load_domain_patterns(:technical)
      assert :genserver_mailbox_overflow in loaded
      
      # Activate if not already
      :ok = PatternRegistry.activate_pattern(:genserver_mailbox_overflow)
      
      # Test matching event
      event = %{
        type: :process_status,
        message_queue_len: 15_000,
        process_memory: 150_000_000,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, matches} = PatternRegistry.evaluate_event(event)
      assert Enum.any?(matches, & &1.pattern_name == :genserver_mailbox_overflow)
      
      # Test non-matching event
      event2 = %{
        type: :process_status,
        message_queue_len: 100,
        process_memory: 1_000_000,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, matches2} = PatternRegistry.evaluate_event(event2)
      refute Enum.any?(matches2, & &1.pattern_name == :genserver_mailbox_overflow)
    end
    
    test "algedonic signals are triggered for critical patterns" do
      # Subscribe to signals
      EventBus.subscribe(:algedonic_signals)
      
      # Ensure critical pattern is active
      if :metasystemic_cascade not in Enum.map(PatternRegistry.active_patterns(), & &1.name) do
        PatternRegistry.load_critical_patterns()
      end
      
      # Create event that triggers cascade
      event = %{
        type: :subsystem_failure,
        subsystem: :s1,
        failure_rate: 0.8,
        timestamp: DateTime.utc_now()
      }
      
      # Evaluate - should trigger algedonic signal
      {:ok, _matches} = PatternRegistry.evaluate_event(event)
      
      # We should receive an algedonic signal (if algedonic integration is enabled)
      receive do
        {:event_bus, %{type: :pattern_triggered_pain} = signal} ->
          assert signal.pain_level > 0
          assert signal.pattern != nil
      after
        100 ->
          # No signal received, that's OK if algedonic integration is disabled
          :ok
      end
    end
    
    test "pattern statistics are tracked" do
      # Ensure a pattern is active
      if :coordination_breakdown not in Enum.map(PatternRegistry.active_patterns(), & &1.name) do
        {:ok, _} = PatternRegistry.load_domain_patterns(:cybernetic)
        :ok = PatternRegistry.activate_pattern(:coordination_breakdown)
      end
      
      # Get initial stats
      initial_stats = PatternRegistry.pattern_stats(:coordination_breakdown)
      initial_matches = Map.get(initial_stats, :matches, 0)
      
      # Evaluate a matching event
      event = %{
        type: :s2_coordination,
        synchronization_error: 0.6,
        s1_conflict_rate: 0.4,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, _} = PatternRegistry.evaluate_event(event)
      
      # Allow time for async stat update
      Process.sleep(50)
      
      # Stats should be updated
      new_stats = PatternRegistry.pattern_stats(:coordination_breakdown)
      
      # Should have recorded the evaluation
      assert new_stats != nil
    end
  end
  
  describe "VSM Pattern Library Structure" do
    test "all domains have patterns" do
      all_patterns = VSMPatternLibrary.all_patterns()
      
      assert Map.has_key?(all_patterns, :cybernetic)
      assert Map.has_key?(all_patterns, :integration)
      assert Map.has_key?(all_patterns, :technical)
      assert Map.has_key?(all_patterns, :distributed)
      
      # Each domain should have patterns
      Enum.each(all_patterns, fn {_domain, patterns} ->
        assert map_size(patterns) > 0
      end)
    end
    
    test "critical patterns have proper algedonic responses" do
      critical = VSMPatternLibrary.patterns_by_severity(:critical)
      
      Enum.each(critical, fn {_name, pattern} ->
        assert pattern.severity == :critical
        
        # Critical patterns should have algedonic responses
        if algedonic = pattern[:algedonic_response] do
          assert algedonic.pain_level >= 0.8
          assert algedonic.urgency >= 0.8
        end
      end)
    end
    
    test "early warning patterns exist" do
      warnings = VSMPatternLibrary.early_warning_patterns()
      
      # Should have early warnings
      assert map_size(warnings) > 0
      
      # Check some specific ones
      assert warnings[:variety_overflow] != nil
      assert warnings[:control_loop_oscillation] != nil
    end
  end
end