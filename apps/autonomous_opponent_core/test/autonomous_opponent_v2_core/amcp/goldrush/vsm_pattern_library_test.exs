defmodule AutonomousOpponentV2Core.AMCP.Goldrush.VSMPatternLibraryTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.AMCP.Goldrush.{VSMPatternLibrary, PatternRegistry, PatternMatcher}
  
  describe "VSM Pattern Library" do
    test "contains all required pattern domains" do
      patterns = VSMPatternLibrary.all_patterns()
      
      assert Map.has_key?(patterns, :cybernetic)
      assert Map.has_key?(patterns, :integration)
      assert Map.has_key?(patterns, :technical)
      assert Map.has_key?(patterns, :distributed)
    end
    
    test "cybernetic patterns follow Beer's principles" do
      cybernetic_patterns = VSMPatternLibrary.patterns_by_domain(:cybernetic)
      
      # Verify critical VSM patterns exist
      assert Map.has_key?(cybernetic_patterns, :variety_overflow)
      assert Map.has_key?(cybernetic_patterns, :control_loop_oscillation)
      assert Map.has_key?(cybernetic_patterns, :metasystemic_cascade)
      
      # Check variety overflow pattern structure
      variety_overflow = cybernetic_patterns.variety_overflow
      assert variety_overflow.severity == :critical
      assert variety_overflow.algedonic_response.pain_level == 0.9
      assert variety_overflow.variety_engineering.emergency_bypass == true
    end
    
    test "integration patterns map V1 components to VSM impacts" do
      integration_patterns = VSMPatternLibrary.patterns_by_domain(:integration)
      
      # Verify EventBus integration pattern
      eventbus_pattern = integration_patterns.eventbus_message_overflow
      assert eventbus_pattern.v1_component == :event_bus
      assert eventbus_pattern.vsm_impact.s1 == :variety_buffer_overflow
      assert eventbus_pattern.vsm_impact.s2 == :coordination_breakdown
    end
    
    test "technical patterns address Elixir/OTP specific issues" do
      technical_patterns = VSMPatternLibrary.patterns_by_domain(:technical)
      
      # Verify GenServer mailbox overflow pattern
      mailbox_pattern = technical_patterns.genserver_mailbox_overflow
      assert mailbox_pattern.detection.threshold == "message_queue_len > 10_000"
      assert :s1_operations in mailbox_pattern.technical_details.affected_processes
    end
    
    test "distributed patterns handle multi-node scenarios" do
      distributed_patterns = VSMPatternLibrary.patterns_by_domain(:distributed)
      
      # Verify CRDT divergence pattern
      crdt_pattern = distributed_patterns.crdt_divergence
      assert crdt_pattern.distributed_impact.consistency == :eventual
      assert crdt_pattern.mitigation.merkle_tree_reconciliation == true
    end
    
    test "patterns can be filtered by severity" do
      critical_patterns = VSMPatternLibrary.patterns_by_severity(:critical)
      
      assert map_size(critical_patterns) >= 3
      assert Enum.all?(critical_patterns, fn {_name, pattern} ->
        pattern.severity == :critical
      end)
    end
    
    test "patterns convert to PatternMatcher format" do
      pattern = VSMPatternLibrary.patterns_by_domain(:cybernetic).variety_overflow
      
      matcher_format = VSMPatternLibrary.to_pattern_matcher_format(:variety_overflow, pattern)
      
      assert matcher_format.name == :variety_overflow
      assert matcher_format.type == :variety_overflow
      assert is_map(matcher_format.metadata)
      assert is_list(matcher_format.conditions)
    end
    
    test "early warning patterns are accessible" do
      early_warnings = VSMPatternLibrary.early_warning_patterns()
      
      assert map_size(early_warnings) > 0
      assert early_warnings.variety_overflow == "variety_ratio > 1.3"
    end
  end
  
  describe "Pattern Registry Integration" do
    setup do
      {:ok, _pid} = PatternRegistry.start_link(auto_activate_critical: false)
      :ok
    end
    
    test "can load and activate cybernetic patterns" do
      {:ok, loaded} = PatternRegistry.load_domain_patterns(:cybernetic)
      
      assert :variety_overflow in loaded
      assert :control_loop_oscillation in loaded
      
      # Activate a pattern
      :ok = PatternRegistry.activate_pattern(:variety_overflow)
      
      active = PatternRegistry.active_patterns()
      assert Enum.any?(active, &(&1.name == :variety_overflow))
    end
    
    test "critical patterns trigger algedonic responses" do
      # Load critical patterns
      {:ok, _} = PatternRegistry.load_critical_patterns()
      
      # Create event that matches variety overflow
      event = %{
        type: :s1_operations,
        variety_ratio: 1.6,
        s1_variety_buffer: 1200,
        processing_latency: 1500,
        message_queue_length: 15_000
      }
      
      {:ok, matches} = PatternRegistry.evaluate_event(event)
      
      # Should match variety overflow pattern
      assert Enum.any?(matches, fn match ->
        match.pattern_name == :variety_overflow &&
        match.algedonic_response.pain_level == 0.9
      end)
    end
    
    test "pattern performance is tracked" do
      {:ok, _} = PatternRegistry.load_domain_patterns(:technical)
      :ok = PatternRegistry.activate_pattern(:genserver_mailbox_overflow)
      
      # Evaluate some events
      for i <- 1..10 do
        event = %{
          type: :process_status,
          message_queue_len: if(rem(i, 3) == 0, do: 11_000, else: 100)
        }
        PatternRegistry.evaluate_event(event)
      end
      
      stats = PatternRegistry.pattern_stats(:genserver_mailbox_overflow)
      assert stats.matches > 0
      assert stats.no_matches > 0
    end
  end
  
  describe "VSM Failure Mode Detection" do
    test "detects variety overflow conditions" do
      pattern = VSMPatternLibrary.patterns_by_domain(:cybernetic).variety_overflow
      matcher_pattern = VSMPatternLibrary.to_pattern_matcher_format(:variety_overflow, pattern)
      
      # This would normally be done by PatternMatcher
      # For now, we'll test the pattern structure
      assert matcher_pattern.metadata.severity == :critical
      assert matcher_pattern.metadata.algedonic_response.bypass_hierarchy == true
    end
    
    test "detects circuit breaker pain loops" do
      pattern = VSMPatternLibrary.patterns_by_domain(:integration).circuit_breaker_pain_loop
      
      assert pattern.detection.threshold == "pain_triggered_opens > 3 in 60s"
      assert pattern.vsm_impact.algedonic == :signal_storm
    end
    
    test "detects distributed algedonic storms" do
      pattern = VSMPatternLibrary.patterns_by_domain(:distributed).distributed_algedonic_storm
      
      assert pattern.detection.threshold == "pain_signal_rate > 100/s"
      assert pattern.distributed_impact.cascade_risk == :extreme
    end
  end
end