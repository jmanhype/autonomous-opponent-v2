#!/usr/bin/env elixir

# Test script to verify HNSW pattern storage activation

alias AutonomousOpponentV2Core.EventBus
alias AutonomousOpponentV2Core.AMCP.Goldrush.{EventProcessor, PatternMatcher}
alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
alias AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore
alias AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge
alias AutonomousOpponentV2Core.Core.Metrics

IO.puts("HNSW Pattern Storage Activation Test")
IO.puts("=" |> String.duplicate(50))

# Wait for system to initialize
Process.sleep(2000)

# Step 1: Check if all components are running
IO.puts("\n1. Checking component status...")

components = [
  {EventProcessor, "EventProcessor"},
  {PatternHNSWBridge, "PatternHNSWBridge"},
  {VectorStore, "VectorStore"},
  {Metrics, "Metrics"}
]

all_running = Enum.all?(components, fn {module, name} ->
  case Process.whereis(module) do
    nil ->
      IO.puts("  ❌ #{name} not running")
      false
    pid ->
      IO.puts("  ✓ #{name} running: #{inspect(pid)}")
      true
  end
end)

unless all_running do
  IO.puts("\nERROR: Not all components are running. Exiting.")
  System.halt(1)
end

# Step 2: Register a test pattern matcher
IO.puts("\n2. Registering test pattern matcher...")

# Create a high urgency pattern
{:ok, pattern} = PatternMatcher.compile_pattern(%{
  type: :test_pattern,
  urgency: %{gte: 0.8},
  source: :test
})

# Register with callback that publishes to a test event
EventProcessor.register_pattern(:test_high_urgency, %{
  type: :test_pattern,
  urgency: %{gte: 0.8},
  source: :test
}, :test_pattern_matched)

IO.puts("  ✓ Pattern registered")

# Step 3: Generate test events
IO.puts("\n3. Generating test events...")

test_events = for i <- 1..10 do
  event = %{
    id: "test_event_#{i}",
    type: :test_pattern,
    urgency: 0.8 + :rand.uniform() * 0.2,  # 0.8 to 1.0
    source: :test,
    timestamp: DateTime.utc_now(),
    data: %{
      value: :rand.uniform(100),
      category: Enum.random([:alpha, :beta, :gamma])
    }
  }
  
  # Process the event
  EventProcessor.process_events([event])
  
  # Small delay to ensure processing
  Process.sleep(100)
  
  IO.puts("  Generated event #{i}: urgency=#{Float.round(event.urgency, 2)}")
  event
end

# Wait for processing
Process.sleep(1000)

# Step 4: Check PatternHNSWBridge stats
IO.puts("\n4. Checking Pattern HNSW Bridge statistics...")

case PatternHNSWBridge.get_stats() do
  stats when is_map(stats) ->
    IO.puts("  Patterns received: #{stats.patterns_received}")
    IO.puts("  Patterns indexed: #{stats.patterns_indexed}")
    IO.puts("  Indexing errors: #{stats.indexing_errors}")
    IO.puts("  Buffer size: #{stats[:buffer_size] || 0}")
    
    if Map.has_key?(stats, :hnsw_stats) && is_map(stats.hnsw_stats) do
      IO.puts("\n  HNSW Index Stats:")
      IO.puts("    Vectors: #{stats.hnsw_stats[:vector_count] || 0}")
      IO.puts("    Layers: #{stats.hnsw_stats[:layer_count] || 0}")
    end
  error ->
    IO.puts("  ERROR getting stats: #{inspect(error)}")
end

# Step 5: Test similarity search
IO.puts("\n5. Testing similarity search...")

# Create a query pattern similar to our test patterns
query_pattern = %{
  type: :test_pattern,
  urgency: 0.9,
  source: :test,
  data: %{value: 50, category: :beta}
}

# Search through VectorStore
case VectorStore.find_similar_patterns(VectorStore, query_pattern, 5) do
  {:ok, results} when is_list(results) ->
    IO.puts("  Found #{length(results)} similar patterns:")
    Enum.each(results, fn result ->
      IO.puts("    - Pattern #{result[:pattern_id]}: distance=#{Float.round(result[:distance] || 0.0, 3)}")
    end)
  error ->
    IO.puts("  ERROR in similarity search: #{inspect(error)}")
end

# Step 6: Check metrics
IO.puts("\n6. Checking metrics...")

metrics_to_check = [
  "vsm.s4.patterns_indexed",
  "vsm.s4.indexing_errors",
  "vsm.operations.success"
]

Enum.each(metrics_to_check, fn metric_name ->
  value = Metrics.get_metric(Metrics, metric_name)
  IO.puts("  #{metric_name}: #{inspect(value)}")
end)

# Summary
IO.puts("\n" <> String.duplicate("=", 50))
IO.puts("HNSW Pattern Storage Test Complete")

# Generate some S4 intelligence events to trigger pattern extraction
IO.puts("\n7. Triggering S4 Intelligence pattern extraction...")

# Publish environmental scan event
EventBus.publish(:external_environment, %{
  source: :test,
  metrics: %{
    cpu: 0.85,
    memory: 0.72,
    throughput: 1200,
    variance: 3.5
  },
  anomalies: [
    %{type: :spike, severity: :high},
    %{type: :drift, severity: :medium}
  ]
})

Process.sleep(2000)

# Final check
IO.puts("\n8. Final statistics:")
final_stats = PatternHNSWBridge.get_stats()
IO.puts("  Total patterns indexed: #{final_stats.patterns_indexed}")

if final_stats.patterns_indexed > 0 do
  IO.puts("\n✅ SUCCESS: HNSW pattern storage is active and working!")
else
  IO.puts("\n⚠️  WARNING: No patterns were indexed. Check the logs for errors.")
end