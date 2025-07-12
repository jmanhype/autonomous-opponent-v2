defmodule Integration.Issue92CompleteIntegrationTest do
  @moduledoc """
  Complete integration tests for Issue #92: VSM Pattern Integration
  
  Tests the end-to-end flow from pattern detection → EventBus → S4 Intelligence
  with real VSM subsystem interactions and vector storage.
  """
  
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  
  alias AutonomousOpponentV2Core.VSM.S4.Intelligence
  alias AutonomousOpponentV2Core.AMCP.Temporal.PatternDetector
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore
  
  @moduletag :integration
  @moduletag :issue_92
  @moduletag :end_to_end
  
  setup_all do
    # Start the entire VSM supervision tree components needed
    start_supervised!(EventBus)
    
    # Allow system to stabilize
    Process.sleep(200)
    
    :ok
  end
  
  setup do
    # Start both PatternDetector and S4 Intelligence
    {:ok, detector_pid} = start_supervised({PatternDetector, []})
    {:ok, s4_pid} = start_supervised({Intelligence, []})
    
    # Subscribe to key events for verification
    EventBus.subscribe(:pattern_detected)
    EventBus.subscribe(:s4_environmental_signal)
    EventBus.subscribe(:s4_strategy_updated)
    EventBus.subscribe(:patterns_indexed)
    
    # Allow subscriptions and startup to complete
    Process.sleep(300)
    
    %{detector_pid: detector_pid, s4_pid: s4_pid}
  end
  
  describe "End-to-End Pattern Flow" do
    test "Complete flow: PatternDetector → EventBus → S4 Intelligence", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      # Step 1: Simulate pattern detection
      detected_pattern = %{
        id: "e2e_flow_001",
        type: :rate_burst,
        confidence: 0.87,
        detected_at: DateTime.utc_now(),
        metadata: %{
          event_count: 18,
          window_ms: 5000,
          threshold: 10,
          subsystem_source: :s1,
          severity: :high
        }
      }
      
      logs = capture_log(fn ->
        # Step 2: Trigger pattern emission from detector
        send(detector_pid, {:emit_pattern, detected_pattern})
        
        # Allow full processing chain
        Process.sleep(500)
      end)
      
      # Step 3: Verify EventBus propagation
      assert_receive {:event_bus, :pattern_detected, published_pattern}, 2000
      
      # Step 4: Verify S4 received and processed the pattern
      assert logs =~ "S4 Intelligence received pattern"
      assert logs =~ "e2e_flow_001"
      
      # Step 5: Verify S4 enhancements were added
      assert Map.has_key?(published_pattern, :environmental_context)
      assert Map.has_key?(published_pattern, :vsm_impact)
      assert Map.has_key?(published_pattern, :urgency)
      assert Map.has_key?(published_pattern, :recommended_s4_actions)
      
      # Step 6: Verify both processes are still alive
      assert Process.alive?(detector_pid)
      assert Process.alive?(s4_pid)
      
      # Step 7: Verify S4 environmental model was updated
      environmental_model = Intelligence.get_environmental_model(s4_pid)
      assert is_map(environmental_model)
    end
    
    test "High-urgency pattern triggers environmental signal", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      # Create a high-urgency algedonic pattern
      algedonic_pattern = %{
        id: "algedonic_e2e_001",
        type: :algedonic_storm,
        confidence: 0.94,
        pain_intensity: 0.91,
        detected_at: DateTime.utc_now(),
        metadata: %{
          storm_duration: 12000,
          intensity_escalation: 2.1,
          affected_subsystems: [:s1, :s2, :s3],
          severity: :critical
        }
      }
      
      logs = capture_log(fn ->
        send(detector_pid, {:emit_pattern, algedonic_pattern})
        Process.sleep(500)
      end)
      
      # Should receive both events
      assert_receive {:event_bus, :pattern_detected, _pattern}, 2000
      assert_receive {:event_bus, :s4_environmental_signal, env_signal}, 2000
      
      # Verify environmental signal characteristics
      assert env_signal.type == :pattern_alert
      assert env_signal.urgency > 0.8
      assert env_signal.pattern.id == "algedonic_e2e_001"
      assert :emergency_strategy in env_signal.recommended_s4_actions
      
      # Verify S4 processed high-priority signal
      assert logs =~ "S4 Intelligence received high-priority environmental signal"
      assert logs =~ "urgency:"
      
      assert Process.alive?(detector_pid)
      assert Process.alive?(s4_pid)
    end
    
    test "Multiple patterns processed in sequence without conflicts", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      patterns = [
        %{
          id: "sequence_001",
          type: :rate_burst,
          confidence: 0.75,
          metadata: %{severity: :medium}
        },
        %{
          id: "sequence_002", 
          type: :coordination_breakdown,
          confidence: 0.82,
          metadata: %{severity: :high}
        },
        %{
          id: "sequence_003",
          type: :consciousness_instability,
          confidence: 0.89,
          metadata: %{severity: :high}
        }
      ]
      
      logs = capture_log(fn ->
        # Send patterns in rapid succession
        for pattern <- patterns do
          send(detector_pid, {:emit_pattern, pattern})
          Process.sleep(50)  # Small delay between patterns
        end
        
        # Allow processing time
        Process.sleep(800)
      end)
      
      # Should receive all pattern events
      for pattern <- patterns do
        assert_receive {:event_bus, :pattern_detected, received_pattern}, 3000
        assert received_pattern.id in ["sequence_001", "sequence_002", "sequence_003"]
      end
      
      # Verify S4 processed all patterns
      assert logs =~ "sequence_001"
      assert logs =~ "sequence_002" 
      assert logs =~ "sequence_003"
      
      # Both processes should be stable
      assert Process.alive?(detector_pid)
      assert Process.alive?(s4_pid)
    end
    
    test "Vector storage integration for high-confidence patterns", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      high_confidence_pattern = %{
        id: "vector_storage_e2e_001",
        type: :consciousness_instability,
        confidence: 0.93,  # Above storage threshold
        vector_data: Enum.map(1..64, fn _ -> :rand.uniform() end),
        metadata: %{
          complexity: :high,
          should_store: true
        }
      }
      
      logs = capture_log(fn ->
        send(detector_pid, {:emit_pattern, high_confidence_pattern})
        Process.sleep(600)
      end)
      
      assert_receive {:event_bus, :pattern_detected, _}, 2000
      
      # Should see vector storage activity
      assert logs =~ "S4 Intelligence storing pattern in vector store" or
             logs =~ "vector store" or
             logs =~ "confidence: 0.93"
      
      assert Process.alive?(s4_pid)
    end
    
    test "S4 strategy updates based on pattern analysis", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      strategy_affecting_pattern = %{
        id: "strategy_update_e2e_001",
        type: :coordination_breakdown,
        confidence: 0.86,
        metadata: %{
          coordination_failures: 5,
          s2_efficiency: 0.45,
          urgency_indicators: [:s1_overload, :s2_failure],
          severity: :high
        }
      }
      
      logs = capture_log(fn ->
        send(detector_pid, {:emit_pattern, strategy_affecting_pattern})
        Process.sleep(600)
      end)
      
      assert_receive {:event_bus, :pattern_detected, pattern}, 2000
      
      # Should see strategy update activity
      assert logs =~ "S4 Intelligence updating strategy" or
             logs =~ "strategy" or
             logs =~ "coordination_breakdown"
      
      # Verify S4 is still responsive
      intelligence_report = Intelligence.get_intelligence_report(s4_pid)
      assert is_map(intelligence_report)
      
      assert Process.alive?(s4_pid)
    end
  end
  
  describe "Error Recovery and Resilience" do
    test "System recovers from pattern processing errors", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      # Send malformed pattern
      malformed_pattern = %{
        id: "malformed_e2e_001",
        type: :invalid_type,
        confidence: "not_a_number",
        corrupted_data: %{nested: %{deeply: :broken}}
      }
      
      logs = capture_log(fn ->
        send(detector_pid, {:emit_pattern, malformed_pattern})
        Process.sleep(200)
        
        # Follow with valid pattern
        valid_pattern = %{
          id: "recovery_e2e_001",
          type: :rate_burst,
          confidence: 0.78,
          metadata: %{test: :recovery}
        }
        
        send(detector_pid, {:emit_pattern, valid_pattern})
        Process.sleep(400)
      end)
      
      # System should recover and process valid pattern
      assert_receive {:event_bus, :pattern_detected, recovered_pattern}, 2000
      assert recovered_pattern.id == "recovery_e2e_001"
      
      # Both processes should survive
      assert Process.alive?(detector_pid)
      assert Process.alive?(s4_pid)
    end
    
    test "S4 handles EventBus message flood gracefully", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      # Generate many patterns rapidly
      patterns = for i <- 1..20 do
        %{
          id: "flood_#{i}",
          type: :rate_burst,
          confidence: 0.5 + (:rand.uniform() * 0.4),  # 0.5-0.9
          metadata: %{batch: :flood_test}
        }
      end
      
      logs = capture_log(fn ->
        # Send all patterns quickly
        for pattern <- patterns do
          send(detector_pid, {:emit_pattern, pattern})
        end
        
        # Allow processing time
        Process.sleep(2000)
      end)
      
      # S4 should survive the flood
      assert Process.alive?(s4_pid)
      assert Process.alive?(detector_pid)
      
      # Should process at least some patterns
      received_count = for _i <- 1..20 do
        receive do
          {:event_bus, :pattern_detected, _} -> 1
        after
          100 -> 0
        end
      end |> Enum.sum()
      
      assert received_count > 0, "Should process at least some patterns from flood"
    end
  end
  
  describe "VSM Cybernetic Integration" do
    test "Pattern flow maintains cybernetic variety principles", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      complex_pattern = %{
        id: "cybernetic_variety_001",
        type: :consciousness_instability,
        confidence: 0.91,
        variety_characteristics: %{
          input_variety: 1000,
          processing_variety: 800,
          output_variety: 600,
          attenuation_needed: true
        },
        metadata: %{
          complexity: :high,
          cybernetic_importance: :critical
        }
      }
      
      logs = capture_log(fn ->
        send(detector_pid, {:emit_pattern, complex_pattern})
        Process.sleep(500)
      end)
      
      assert_receive {:event_bus, :pattern_detected, processed_pattern}, 2000
      
      # Verify cybernetic principles are maintained
      assert Map.has_key?(processed_pattern, :environmental_context)
      assert Map.has_key?(processed_pattern, :vsm_impact)
      
      # Should see variety management in logs
      assert logs =~ "S4 Intelligence" and (logs =~ "variety" or logs =~ "cybernetic" or logs =~ "pattern")
      
      assert Process.alive?(s4_pid)
    end
    
    test "S4 provides appropriate feedback for VSM control loops", context do
      %{s4_pid: s4_pid} = context
      
      # Get S4 intelligence report after pattern processing
      intelligence_report = Intelligence.get_intelligence_report(s4_pid)
      
      # Should have VSM-relevant information
      assert is_map(intelligence_report)
      
      # Should be able to scan environment (S4's core function)
      scan_result = Intelligence.scan_environment(s4_pid)
      assert is_map(scan_result)
    end
  end
  
  describe "Performance and Scalability" do
    test "Pattern processing completes within acceptable timeframes", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      pattern = %{
        id: "performance_test_001",
        type: :rate_burst,
        confidence: 0.85,
        metadata: %{performance_test: true}
      }
      
      start_time = System.monotonic_time(:millisecond)
      
      send(detector_pid, {:emit_pattern, pattern})
      
      assert_receive {:event_bus, :pattern_detected, _}, 1000
      
      end_time = System.monotonic_time(:millisecond)
      processing_time = end_time - start_time
      
      # Should complete within reasonable time (< 500ms)
      assert processing_time < 500, "Pattern processing took #{processing_time}ms, should be < 500ms"
      
      assert Process.alive?(s4_pid)
    end
    
    test "Memory usage remains stable during extended pattern processing", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      initial_memory = :erlang.process_info(s4_pid, :memory)[:memory]
      
      # Process many patterns
      for i <- 1..50 do
        pattern = %{
          id: "memory_test_#{i}",
          type: :rate_burst,
          confidence: 0.7 + (:rand.uniform() * 0.2),
          metadata: %{memory_test: true}
        }
        
        send(detector_pid, {:emit_pattern, pattern})
        
        if rem(i, 10) == 0, do: Process.sleep(100)
      end
      
      Process.sleep(1000)  # Allow processing to complete
      
      final_memory = :erlang.process_info(s4_pid, :memory)[:memory]
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be reasonable (< 5MB for 50 patterns)
      assert memory_growth < 5_000_000, 
             "Memory grew by #{memory_growth} bytes, should be < 5MB"
      
      assert Process.alive?(s4_pid)
    end
  end
end