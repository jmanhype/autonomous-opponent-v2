defmodule Performance.Issue92PerformanceTest do
  @moduledoc """
  Performance tests for Issue #92: S4 Intelligence Pattern Integration
  
  Tests throughput, latency, memory usage, and scalability of the pattern processing system.
  """
  
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  
  alias AutonomousOpponentV2Core.VSM.S4.Intelligence
  alias AutonomousOpponentV2Core.AMCP.Temporal.PatternDetector
  alias AutonomousOpponentV2Core.EventBus
  
  @moduletag :performance
  @moduletag :issue_92
  @moduletag timeout: 60_000  # 60 second timeout for performance tests
  
  setup_all do
    start_supervised!(EventBus)
    :ok
  end
  
  setup do
    {:ok, detector_pid} = start_supervised({PatternDetector, []})
    {:ok, s4_pid} = start_supervised({Intelligence, []})
    
    EventBus.subscribe(:pattern_detected)
    EventBus.subscribe(:s4_environmental_signal)
    
    Process.sleep(200)  # Allow system stabilization
    
    %{detector_pid: detector_pid, s4_pid: s4_pid}
  end
  
  describe "Throughput Performance" do
    test "S4 processes 100 patterns within 5 seconds", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      patterns = generate_test_patterns(100)
      
      start_time = System.monotonic_time(:millisecond)
      
      # Send all patterns
      for pattern <- patterns do
        send(detector_pid, {:emit_pattern, pattern})
      end
      
      # Wait for all processing to complete
      processed_count = receive_patterns_with_timeout(100, 5000)
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      assert processed_count >= 95, "Should process at least 95% of patterns, got #{processed_count}/100"
      assert total_time < 5000, "Should complete within 5 seconds, took #{total_time}ms"
      
      throughput = (processed_count / total_time) * 1000  # patterns per second
      assert throughput > 10, "Should achieve >10 patterns/sec, got #{Float.round(throughput, 2)}"
      
      assert Process.alive?(s4_pid), "S4 should survive high throughput"
    end
    
    test "S4 maintains responsiveness under sustained load", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      # Send patterns continuously for 10 seconds
      patterns_per_second = 20
      duration_seconds = 10
      total_patterns = patterns_per_second * duration_seconds
      
      start_time = System.monotonic_time(:millisecond)
      
      # Spawn process to send patterns at steady rate
      sender_pid = spawn(fn ->
        send_patterns_at_rate(detector_pid, patterns_per_second, duration_seconds)
      end)
      
      # Monitor processing latency every second
      latencies = monitor_processing_latency(duration_seconds)
      
      Process.sleep(duration_seconds * 1000 + 500)  # Allow completion
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      # Verify system remained responsive
      max_latency = Enum.max(latencies, fn -> 0 end)
      avg_latency = if length(latencies) > 0 do
        Enum.sum(latencies) / length(latencies)
      else
        0
      end
      
      assert max_latency < 1000, "Max latency should be <1s, got #{max_latency}ms"
      assert avg_latency < 200, "Average latency should be <200ms, got #{Float.round(avg_latency, 2)}ms"
      assert Process.alive?(s4_pid), "S4 should survive sustained load"
      
      # Clean up
      if Process.alive?(sender_pid), do: Process.exit(sender_pid, :kill)
    end
    
    test "High-priority patterns are processed with lower latency", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      # Create mix of normal and high-priority patterns
      normal_patterns = generate_test_patterns(50, %{priority: :normal, urgency: 0.5})
      priority_patterns = generate_test_patterns(10, %{priority: :high, urgency: 0.9})
      
      # Interleave patterns
      all_patterns = Enum.shuffle(normal_patterns ++ priority_patterns)
      
      start_time = System.monotonic_time(:millisecond)
      
      # Send all patterns
      for pattern <- all_patterns do
        send(detector_pid, {:emit_pattern, pattern})
      end
      
      # Measure processing times for each priority level
      {priority_times, normal_times} = collect_processing_times_by_priority(60, start_time)
      
      # High-priority patterns should be processed faster on average
      if length(priority_times) > 0 and length(normal_times) > 0 do
        avg_priority_time = Enum.sum(priority_times) / length(priority_times)
        avg_normal_time = Enum.sum(normal_times) / length(normal_times)
        
        assert avg_priority_time < avg_normal_time,
               "Priority patterns should be faster: #{avg_priority_time}ms vs #{avg_normal_time}ms"
      end
      
      assert Process.alive?(s4_pid)
    end
  end
  
  describe "Memory Performance" do
    test "Memory usage remains stable during extended processing", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      initial_memory = :erlang.process_info(s4_pid, :memory)[:memory]
      memory_samples = [initial_memory]
      
      # Process patterns in batches and monitor memory
      batches = 20
      patterns_per_batch = 25
      
      for batch <- 1..batches do
        patterns = generate_test_patterns(patterns_per_batch)
        
        for pattern <- patterns do
          send(detector_pid, {:emit_pattern, pattern})
        end
        
        # Allow processing
        Process.sleep(200)
        
        # Sample memory every 5 batches
        if rem(batch, 5) == 0 do
          current_memory = :erlang.process_info(s4_pid, :memory)[:memory]
          memory_samples = [current_memory | memory_samples]
        end
      end
      
      # Allow final processing
      Process.sleep(1000)
      final_memory = :erlang.process_info(s4_pid, :memory)[:memory]
      memory_samples = [final_memory | memory_samples]
      
      # Analyze memory growth
      total_growth = final_memory - initial_memory
      max_memory = Enum.max(memory_samples)
      
      # Memory should not grow excessively
      assert total_growth < 10_000_000, "Memory growth should be <10MB, got #{total_growth} bytes"
      assert max_memory < initial_memory * 3, "Memory should not triple during processing"
      
      # Memory should stabilize (not continuously growing)
      recent_samples = Enum.take(memory_samples, 3)
      memory_stability = Enum.max(recent_samples) - Enum.min(recent_samples)
      assert memory_stability < 1_000_000, "Memory should stabilize, variance: #{memory_stability} bytes"
      
      assert Process.alive?(s4_pid)
    end
    
    test "Pattern cache maintains reasonable size limits", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      # Generate many unique patterns to test cache behavior
      unique_patterns = generate_unique_test_patterns(1000)
      
      for {pattern, index} <- Enum.with_index(unique_patterns) do
        send(detector_pid, {:emit_pattern, pattern})
        
        # Check memory every 100 patterns
        if rem(index, 100) == 0 do
          current_memory = :erlang.process_info(s4_pid, :memory)[:memory]
          
          # Memory should not grow linearly with pattern count
          # (indicating cache size limits are working)
          expected_max_memory = 50_000_000  # 50MB reasonable upper bound
          assert current_memory < expected_max_memory,
                 "Memory at pattern #{index}: #{current_memory} bytes should be < #{expected_max_memory}"
        end
        
        # Small delay to allow processing
        if rem(index, 50) == 0, do: Process.sleep(100)
      end
      
      assert Process.alive?(s4_pid)
    end
  end
  
  describe "Scalability Performance" do
    test "System scales with increasing pattern complexity", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      complexity_levels = [
        {10, :simple},     # 10 simple patterns
        {10, :medium},     # 10 medium complexity
        {10, :complex},    # 10 complex patterns
        {10, :very_complex} # 10 very complex patterns
      ]
      
      processing_times = []
      
      for {count, complexity} <- complexity_levels do
        patterns = generate_patterns_with_complexity(count, complexity)
        
        start_time = System.monotonic_time(:millisecond)
        
        for pattern <- patterns do
          send(detector_pid, {:emit_pattern, pattern})
        end
        
        # Wait for processing
        receive_patterns_with_timeout(count, 5000)
        
        end_time = System.monotonic_time(:millisecond)
        batch_time = end_time - start_time
        avg_time_per_pattern = batch_time / count
        
        processing_times = [{complexity, avg_time_per_pattern} | processing_times]
        
        Process.sleep(200)  # Allow system to stabilize
      end
      
      processing_times = Enum.reverse(processing_times)
      
      # Processing time should scale reasonably with complexity
      simple_time = Keyword.get(processing_times, :simple, 0)
      complex_time = Keyword.get(processing_times, :very_complex, 0)
      
      # Complex patterns can take longer, but not exponentially
      if simple_time > 0 do
        complexity_ratio = complex_time / simple_time
        assert complexity_ratio < 10, 
               "Complexity scaling should be reasonable, got #{Float.round(complexity_ratio, 2)}x"
      end
      
      assert Process.alive?(s4_pid)
    end
    
    test "Concurrent pattern sources are handled efficiently", context do
      %{s4_pid: s4_pid} = context
      
      # Start multiple pattern detector processes
      detector_count = 5
      patterns_per_detector = 20
      
      detector_pids = for i <- 1..detector_count do
        {:ok, pid} = start_supervised({PatternDetector, []}, id: :"detector_#{i}")
        pid
      end
      
      start_time = System.monotonic_time(:millisecond)
      
      # Send patterns from all detectors concurrently
      tasks = for {detector_pid, index} <- Enum.with_index(detector_pids) do
        Task.async(fn ->
          patterns = generate_test_patterns(patterns_per_detector, %{source: "detector_#{index}"})
          
          for pattern <- patterns do
            send(detector_pid, {:emit_pattern, pattern})
          end
          
          patterns_per_detector
        end)
      end
      
      # Wait for all tasks to complete
      total_sent = tasks |> Enum.map(&Task.await(&1, 10_000)) |> Enum.sum()
      
      # Collect processed patterns
      processed_count = receive_patterns_with_timeout(total_sent, 10_000)
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      assert processed_count >= total_sent * 0.9, 
             "Should process ≥90% of patterns from concurrent sources: #{processed_count}/#{total_sent}"
      
      throughput = (processed_count / total_time) * 1000
      assert throughput > 5, "Concurrent throughput should be >5 patterns/sec, got #{Float.round(throughput, 2)}"
      
      assert Process.alive?(s4_pid)
    end
  end
  
  describe "Error Recovery Performance" do
    test "System recovers quickly from processing errors", context do
      %{detector_pid: detector_pid, s4_pid: s4_pid} = context
      
      # Send valid patterns, then errors, then valid again
      valid_patterns_1 = generate_test_patterns(20)
      error_patterns = generate_error_patterns(10)
      valid_patterns_2 = generate_test_patterns(20)
      
      all_patterns = valid_patterns_1 ++ error_patterns ++ valid_patterns_2
      
      start_time = System.monotonic_time(:millisecond)
      
      # Send all patterns
      for pattern <- all_patterns do
        send(detector_pid, {:emit_pattern, pattern})
      end
      
      # Should process valid patterns despite errors
      processed_count = receive_patterns_with_timeout(40, 5000)  # Expect ~40 valid patterns
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      assert processed_count >= 35, "Should process most valid patterns despite errors: #{processed_count}/40"
      assert total_time < 5000, "Recovery should be fast: #{total_time}ms"
      assert Process.alive?(s4_pid), "S4 should survive error conditions"
    end
  end
  
  # Helper functions
  
  defp generate_test_patterns(count, base_attrs \\\\ %{}) do
    for i <- 1..count do
      base_pattern = %{
        id: "perf_test_#{i}_#{System.unique_integer()}",
        type: Enum.random([:rate_burst, :coordination_breakdown, :consciousness_instability]),
        confidence: 0.5 + (:rand.uniform() * 0.4),  # 0.5-0.9
        timestamp: DateTime.utc_now(),
        metadata: %{
          test: :performance,
          batch_id: System.unique_integer()
        }
      }
      
      Map.merge(base_pattern, base_attrs)
    end
  end
  
  defp generate_unique_test_patterns(count) do
    for i <- 1..count do
      %{
        id: "unique_#{i}_#{System.unique_integer()}",
        type: Enum.random([:rate_burst, :error_cascade, :algedonic_storm, :coordination_breakdown, :consciousness_instability]),
        confidence: :rand.uniform(),
        unique_data: %{
          sequence: i,
          random_data: :crypto.strong_rand_bytes(100) |> Base.encode64(),
          timestamp: DateTime.utc_now()
        }
      }
    end
  end
  
  defp generate_patterns_with_complexity(count, complexity) do
    base_complexity = case complexity do
      :simple -> %{metadata: %{events: 1}}
      :medium -> %{metadata: %{events: 10, subsystems: [:s1, :s2]}}
      :complex -> %{metadata: %{events: 50, subsystems: [:s1, :s2, :s3], correlations: [:temporal, :causal]}}
      :very_complex -> %{
        metadata: %{
          events: 200,
          subsystems: [:s1, :s2, :s3, :s4, :s5],
          correlations: [:temporal, :causal, :emergent],
          nested_data: %{
            level1: %{level2: %{level3: "deep_nesting"}},
            arrays: Enum.to_list(1..100)
          }
        }
      }
    end
    
    generate_test_patterns(count, base_complexity)
  end
  
  defp generate_error_patterns(count) do
    for i <- 1..count do
      case rem(i, 3) do
        0 -> %{id: "error_#{i}", type: :invalid_type, confidence: "invalid"}
        1 -> %{malformed: :data, missing_required_fields: true}
        2 -> %{id: "error_#{i}", confidence: -1.0, type: nil}
      end
    end
  end
  
  defp receive_patterns_with_timeout(expected_count, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    receive_patterns_count(0, expected_count, deadline)
  end
  
  defp receive_patterns_count(current_count, target_count, deadline) do
    if current_count >= target_count or System.monotonic_time(:millisecond) > deadline do
      current_count
    else
      receive do
        {:event_bus, :pattern_detected, _} ->
          receive_patterns_count(current_count + 1, target_count, deadline)
        {:event_bus, :s4_environmental_signal, _} ->
          receive_patterns_count(current_count, target_count, deadline)  # Don't count env signals
      after
        100 ->
          receive_patterns_count(current_count, target_count, deadline)
      end
    end
  end
  
  defp send_patterns_at_rate(detector_pid, patterns_per_second, duration_seconds) do
    interval_ms = 1000 / patterns_per_second
    total_patterns = patterns_per_second * duration_seconds
    
    for i <- 1..total_patterns do
      pattern = %{
        id: "rate_test_#{i}",
        type: :rate_burst,
        confidence: 0.7,
        metadata: %{rate_test: true}
      }
      
      send(detector_pid, {:emit_pattern, pattern})
      Process.sleep(trunc(interval_ms))
    end
  end
  
  defp monitor_processing_latency(duration_seconds) do
    start_time = System.monotonic_time(:millisecond)
    monitor_latency_loop(start_time, start_time + (duration_seconds * 1000), [])
  end
  
  defp monitor_latency_loop(start_time, end_time, latencies) do
    if System.monotonic_time(:millisecond) >= end_time do
      latencies
    else
      request_start = System.monotonic_time(:millisecond)
      
      # Simulate a processing request (could be health check or similar)
      Process.sleep(1)
      
      request_end = System.monotonic_time(:millisecond)
      latency = request_end - request_start
      
      Process.sleep(1000)  # Wait 1 second before next measurement
      monitor_latency_loop(start_time, end_time, [latency | latencies])
    end
  end
  
  defp collect_processing_times_by_priority(expected_count, start_time) do
    collect_priority_times([], [], expected_count, start_time)
  end
  
  defp collect_priority_times(priority_times, normal_times, remaining, start_time) do
    if remaining <= 0 do
      {priority_times, normal_times}
    else
      receive do
        {:event_bus, :pattern_detected, pattern} ->
          processing_time = System.monotonic_time(:millisecond) - start_time
          
          case Map.get(pattern, :urgency, 0.5) do
            urgency when urgency > 0.8 ->
              collect_priority_times([processing_time | priority_times], normal_times, remaining - 1, start_time)
            _ ->
              collect_priority_times(priority_times, [processing_time | normal_times], remaining - 1, start_time)
          end
      after
        5000 ->
          {priority_times, normal_times}
      end
    end
  end
end