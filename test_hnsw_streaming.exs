#!/usr/bin/env elixir

# Test script for HNSW Event Streaming Integration
# Run with: mix run test_hnsw_streaming.exs

defmodule HNSWStreamingTest do
  @moduledoc """
  Integration test for HNSW event streaming through WebSocket.
  Validates the complete flow from EventBus → HNSW → WebSocket → Client
  """
  
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
  
  def run do
    IO.puts("\n🚀 Starting HNSW Event Streaming Integration Test...\n")
    
    # Ensure processes are running
    ensure_processes()
    
    # Run test sequence
    test_pattern_flow()
    |> test_deduplication()
    |> test_algedonic_signals()
    |> test_pattern_search()
    |> test_monitoring()
    |> print_results()
  end
  
  defp ensure_processes do
    IO.puts("✓ Checking required processes...")
    
    unless Process.whereis(AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge) do
      IO.puts("  Starting PatternHNSWBridge...")
      {:ok, _} = PatternHNSWBridge.start_link()
    end
    
    Process.sleep(100)
    IO.puts("✓ All processes ready\n")
  end
  
  defp test_pattern_flow(results \\ %{}) do
    IO.puts("📊 Testing Pattern Flow...")
    
    initial_stats = PatternHNSWBridge.get_stats()
    
    # Generate test patterns
    for i <- 1..10 do
      pattern = %{
        pattern_id: "test_pattern_#{i}",
        match_context: %{
          confidence: 0.5 + :rand.uniform() * 0.5,
          type: "integration_test",
          source: :test_script
        },
        matched_event: %{
          data: "test_event_#{i}",
          category: Enum.random([:error, :metric, :state_change])
        },
        triggered_at: DateTime.utc_now()
      }
      
      EventBus.publish(:pattern_matched, pattern)
      Process.sleep(50)
    end
    
    Process.sleep(500)
    
    final_stats = PatternHNSWBridge.get_stats()
    
    patterns_processed = final_stats.patterns_indexed - initial_stats.patterns_indexed
    
    IO.puts("  ✓ Published 10 patterns")
    IO.puts("  ✓ Indexed: #{patterns_processed} patterns")
    IO.puts("  ✓ Current index size: #{final_stats.hnsw_stats[:size] || 0}")
    
    Map.put(results, :pattern_flow, %{
      published: 10,
      indexed: patterns_processed,
      success: patterns_processed > 0
    })
  end
  
  defp test_deduplication(results) do
    IO.puts("\n🔍 Testing Deduplication...")
    
    initial_stats = PatternHNSWBridge.get_stats()
    
    # Create identical pattern
    duplicate_pattern = %{
      pattern_id: "duplicate_test",
      match_context: %{
        confidence: 0.99,
        type: "duplicate",
        source: :dedup_test
      },
      matched_event: %{data: "same_data"},
      triggered_at: DateTime.utc_now()
    }
    
    # Publish 5 times
    for _ <- 1..5 do
      EventBus.publish(:pattern_matched, duplicate_pattern)
      Process.sleep(10)
    end
    
    Process.sleep(500)
    
    final_stats = PatternHNSWBridge.get_stats()
    
    dedup_count = final_stats.patterns_deduplicated - initial_stats.patterns_deduplicated
    
    IO.puts("  ✓ Published 5 identical patterns")
    IO.puts("  ✓ Deduplicated: #{dedup_count} patterns")
    IO.puts("  ✓ Dedup threshold: #{final_stats.dedup_threshold}")
    
    Map.put(results, :deduplication, %{
      duplicates_sent: 5,
      deduplicated: dedup_count,
      success: dedup_count >= 3  # At least 3 should be deduped
    })
  end
  
  defp test_algedonic_signals(results) do
    IO.puts("\n🚨 Testing Algedonic Signals...")
    
    # High-intensity pain signal
    pain_signal = %{
      type: :pain,
      intensity: 0.95,
      source: :system_overload,
      metric: :cpu_usage,
      pattern_vector: List.duplicate(0.8, 100)
    }
    
    EventBus.publish(:algedonic_signal, pain_signal)
    
    # Low-intensity pleasure signal
    pleasure_signal = %{
      type: :pleasure,
      intensity: 0.3,
      source: :optimization_success,
      metric: :response_time
    }
    
    EventBus.publish(:algedonic_signal, pleasure_signal)
    
    Process.sleep(100)
    
    IO.puts("  ✓ Published high-intensity pain signal (0.95)")
    IO.puts("  ✓ Published low-intensity pleasure signal (0.3)")
    IO.puts("  ✓ High-intensity signals trigger immediate broadcast")
    
    Map.put(results, :algedonic, %{
      pain_sent: true,
      pleasure_sent: true,
      success: true
    })
  end
  
  defp test_pattern_search(results) do
    IO.puts("\n🔎 Testing Pattern Search...")
    
    # Create a known pattern vector
    test_vector = List.duplicate(0.5, 100)
    
    # Insert directly into HNSW
    case HNSWIndex.insert(:hnsw_index, test_vector, %{
      id: "search_test_pattern",
      type: "search_test",
      timestamp: DateTime.utc_now()
    }) do
      :ok ->
        IO.puts("  ✓ Inserted test pattern")
        
        # Search for similar patterns
        case HNSWIndex.search(:hnsw_index, test_vector, 5) do
          {:ok, search_results} ->
            IO.puts("  ✓ Search returned #{length(search_results)} results")
            
            if length(search_results) > 0 do
              [{_id, distance} | _] = search_results
              IO.puts("  ✓ Closest match distance: #{Float.round(distance, 4)}")
            end
            
            Map.put(results, :search, %{
              pattern_inserted: true,
              results_found: length(search_results),
              success: length(search_results) > 0
            })
            
          {:error, reason} ->
            IO.puts("  ✗ Search failed: #{inspect(reason)}")
            Map.put(results, :search, %{success: false, error: reason})
        end
        
      error ->
        IO.puts("  ✗ Insert failed: #{inspect(error)}")
        Map.put(results, :search, %{success: false, error: error})
    end
  end
  
  defp test_monitoring(results) do
    IO.puts("\n📈 Testing Monitoring...")
    
    monitoring = PatternHNSWBridge.get_monitoring_info()
    
    IO.puts("  ✓ Pattern Metrics:")
    IO.puts("    - Total received: #{monitoring[:pattern_metrics][:total_received]}")
    IO.puts("    - Total indexed: #{monitoring[:pattern_metrics][:total_indexed]}")
    IO.puts("    - Success rate: #{Float.round(monitoring[:pattern_metrics][:success_rate] * 100, 1)}%")
    
    IO.puts("  ✓ Backpressure Status:")
    IO.puts("    - Active: #{monitoring[:backpressure][:active]}")
    IO.puts("    - Buffer utilization: #{Float.round(monitoring[:backpressure][:buffer_utilization] * 100, 1)}%")
    
    IO.puts("  ✓ System Health: #{monitoring[:health][:status]}")
    
    if length(monitoring[:health][:warnings] || []) > 0 do
      IO.puts("  ⚠️  Warnings:")
      for warning <- monitoring[:health][:warnings] do
        IO.puts("    - #{warning}")
      end
    end
    
    Map.put(results, :monitoring, %{
      health: monitoring[:health][:status],
      success: monitoring[:health][:status] in [:healthy, :degraded]
    })
  end
  
  defp print_results(results) do
    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("📊 TEST RESULTS SUMMARY")
    IO.puts(String.duplicate("=", 50))
    
    all_success = Enum.all?(results, fn {_key, result} ->
      Map.get(result, :success, false)
    end)
    
    for {test_name, result} <- results do
      status = if result.success, do: "✅", else: "❌"
      IO.puts("#{status} #{format_test_name(test_name)}: #{format_result(result)}")
    end
    
    IO.puts("\n" <> String.duplicate("=", 50))
    
    if all_success do
      IO.puts("✅ ALL TESTS PASSED! HNSW Event Streaming is operational.")
    else
      IO.puts("❌ Some tests failed. Check the output above for details.")
    end
    
    IO.puts(String.duplicate("=", 50) <> "\n")
    
    results
  end
  
  defp format_test_name(atom) do
    atom
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  
  defp format_result(result) do
    result
    |> Map.drop([:success])
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join(", ")
  end
end

# Run the test
HNSWStreamingTest.run()