defmodule AutonomousOpponentV2Core.AMCP.Goldrush.BasicVSMPatternTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.AMCP.Goldrush.VSMPatternLibrary
  
  describe "VSM Pattern Library Basic Tests" do
    test "all pattern domains exist" do
      patterns = VSMPatternLibrary.all_patterns()
      
      assert Map.has_key?(patterns, :cybernetic)
      assert Map.has_key?(patterns, :integration)
      assert Map.has_key?(patterns, :technical)
      assert Map.has_key?(patterns, :distributed)
    end
    
    test "critical patterns have proper structure" do
      critical_patterns = VSMPatternLibrary.patterns_by_severity(:critical)
      
      assert map_size(critical_patterns) >= 3
      
      Enum.each(critical_patterns, fn {name, pattern} ->
        assert pattern.severity == :critical
        assert is_atom(pattern.type)
        assert is_binary(pattern.description)
        assert is_map(pattern.detection)
        assert pattern.detection.threshold != nil
      end)
    end
    
    test "variety overflow pattern follows Beer's principles" do
      pattern = VSMPatternLibrary.patterns_by_domain(:cybernetic).variety_overflow
      
      assert pattern.type == :variety_overflow
      assert pattern.severity == :critical
      assert pattern.domain == :cybernetic
      
      # Check algedonic response
      assert pattern.algedonic_response.pain_level == 0.9
      assert pattern.algedonic_response.urgency == 1.0
      assert pattern.algedonic_response.bypass_hierarchy == true
      
      # Check variety engineering
      assert pattern.variety_engineering.immediate == :aggressive_attenuation
      assert pattern.variety_engineering.emergency_bypass == true
    end
    
    test "pattern can be converted to matcher format" do
      pattern = VSMPatternLibrary.patterns_by_domain(:technical).genserver_mailbox_overflow
      matcher_format = VSMPatternLibrary.to_pattern_matcher_format(:test_pattern, pattern)
      
      assert matcher_format.name == :test_pattern
      assert matcher_format.type == :genserver_mailbox_overflow
      assert is_map(matcher_format.metadata)
      assert is_list(matcher_format.conditions)
    end
    
    test "early warning patterns are accessible" do
      warnings = VSMPatternLibrary.early_warning_patterns()
      
      assert map_size(warnings) > 10
      assert warnings.variety_overflow == "variety_ratio > 1.3"
      assert warnings.control_loop_oscillation == "control_variance > 0.2"
    end
  end
end