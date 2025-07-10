defmodule AutonomousOpponentV2Core.AMCP.Goldrush.PatternRegistryTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.AMCP.Goldrush.{PatternRegistry, VSMPatternLibrary}
  
  setup do
    # Ensure clean state for each test
    if Process.whereis(PatternRegistry) do
      GenServer.stop(PatternRegistry)
      Process.sleep(100)
    end
    :ok
  end
  
  describe "Pattern Registry Startup" do
    test "starts without auto-loading patterns" do
      assert {:ok, pid} = PatternRegistry.start_link(auto_activate_critical: false)
      assert Process.alive?(pid)
      
      # Should have no active patterns
      active = PatternRegistry.active_patterns()
      assert active == []
    end
    
    test "starts with auto-loading critical patterns" do
      assert {:ok, pid} = PatternRegistry.start_link(auto_activate_critical: true)
      assert Process.alive?(pid)
      
      # Give it time to auto-load
      Process.sleep(500)
      
      # Should have loaded critical patterns
      active = PatternRegistry.active_patterns()
      assert length(active) >= 3
      
      # Verify critical patterns are loaded
      pattern_names = Enum.map(active, & &1.name)
      assert :variety_overflow in pattern_names
      assert :control_loop_oscillation in pattern_names
      assert :metasystemic_cascade in pattern_names
    end
  end
  
  describe "Pattern Loading" do
    setup do
      # Ensure PatternRegistry is available
      unless Process.whereis(PatternRegistry) do
        {:ok, _} = PatternRegistry.start_link(auto_activate_critical: false)
      end
      :ok
    end
    
    test "loads cybernetic domain patterns" do
      {:ok, loaded} = PatternRegistry.load_domain_patterns(:cybernetic)
      
      assert :variety_overflow in loaded
      assert :control_loop_oscillation in loaded
      assert :coordination_breakdown in loaded
      assert length(loaded) >= 6
    end
    
    test "loads and activates specific pattern" do
      {:ok, _} = PatternRegistry.load_domain_patterns(:technical)
      
      # Activate specific pattern
      :ok = PatternRegistry.activate_pattern(:genserver_mailbox_overflow)
      
      active = PatternRegistry.active_patterns()
      assert Enum.any?(active, & &1.name == :genserver_mailbox_overflow)
    end
    
    test "handles pattern not found" do
      assert {:error, :pattern_not_found} = PatternRegistry.activate_pattern(:non_existent_pattern)
    end
  end
  
  describe "Event Evaluation" do
    setup do
      {:ok, _} = PatternRegistry.start_link(auto_activate_critical: false)
      {:ok, _} = PatternRegistry.load_domain_patterns(:technical)
      :ok = PatternRegistry.activate_pattern(:genserver_mailbox_overflow)
      :ok
    end
    
    test "evaluates matching event" do
      event = %{
        type: :process_status,
        message_queue_len: 15_000,
        process_memory: 150_000_000,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, matches} = PatternRegistry.evaluate_event(event)
      
      # Should match genserver mailbox overflow
      assert length(matches) > 0
      match = hd(matches)
      assert match.pattern_name == :genserver_mailbox_overflow
    end
    
    test "evaluates non-matching event" do
      event = %{
        type: :process_status,
        message_queue_len: 100,  # Well below threshold
        process_memory: 1_000_000,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, matches} = PatternRegistry.evaluate_event(event)
      assert matches == []
    end
  end
  
  describe "Pattern Statistics" do
    setup do
      {:ok, _} = PatternRegistry.start_link(auto_activate_critical: false)
      {:ok, _} = PatternRegistry.load_domain_patterns(:cybernetic)
      :ok = PatternRegistry.activate_pattern(:variety_overflow)
      :ok
    end
    
    test "tracks pattern evaluation statistics" do
      # Evaluate some events
      matching_event = %{
        type: :s1_operations,
        variety_ratio: 2.0,
        s1_variety_buffer: 1500,
        processing_latency: 2000,
        message_queue_length: 15_000
      }
      
      non_matching_event = %{
        type: :s1_operations,
        variety_ratio: 0.5,
        s1_variety_buffer: 100,
        processing_latency: 50,
        message_queue_length: 100
      }
      
      # Evaluate multiple times
      PatternRegistry.evaluate_event(matching_event)
      PatternRegistry.evaluate_event(non_matching_event)
      PatternRegistry.evaluate_event(non_matching_event)
      
      # Check stats
      Process.sleep(100)  # Allow async stat updates
      stats = PatternRegistry.pattern_stats(:variety_overflow)
      
      assert stats[:matches] >= 1
      assert stats[:no_matches] >= 2
      assert stats[:first_seen] != nil
    end
  end
  
  describe "Algedonic Integration" do
    setup do
      {:ok, _} = PatternRegistry.start_link(
        auto_activate_critical: false,
        algedonic_integration: true
      )
      
      # Subscribe to algedonic signals
      AutonomousOpponentV2Core.EventBus.subscribe(:algedonic_signals)
      AutonomousOpponentV2Core.EventBus.subscribe(:algedonic_emergency)
      
      :ok
    end
    
    test "triggers algedonic signals for critical patterns" do
      # Load and activate critical pattern
      {:ok, _} = PatternRegistry.load_critical_patterns()
      
      # Create event that triggers variety overflow
      event = %{
        type: :s1_operations,
        variety_ratio: 2.0,
        s1_variety_buffer: 1500,
        processing_latency: 2000,
        message_queue_length: 20_000
      }
      
      # Evaluate event
      {:ok, matches} = PatternRegistry.evaluate_event(event)
      assert length(matches) > 0
      
      # Should receive algedonic signal
      assert_receive {:event_bus, %{type: :pattern_triggered_pain} = signal}, 1000
      assert signal.pain_level >= 0.8
      assert signal.pattern != nil
    end
  end
  
  describe "Error Handling" do
    setup do
      # Ensure PatternRegistry is available
      unless Process.whereis(PatternRegistry) do
        {:ok, _} = PatternRegistry.start_link(auto_activate_critical: false)
      end
      :ok
    end
    
    test "handles pattern compilation errors gracefully" do
      # Create a malformed pattern
      bad_pattern = %{
        type: :bad_pattern,
        # Missing required fields
      }
      
      # This should not crash the registry
      assert {:error, _} = PatternRegistry.compile_pattern(bad_pattern)
    end
    
    test "continues evaluation after pattern error" do
      # Load some valid patterns
      {:ok, _} = PatternRegistry.load_domain_patterns(:technical)
      :ok = PatternRegistry.activate_pattern(:ets_table_overflow)
      
      # Evaluate with malformed event
      malformed_event = "not a map"
      
      # Should not crash
      assert {:ok, []} = PatternRegistry.evaluate_event(malformed_event)
    end
  end
end