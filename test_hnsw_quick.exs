alias AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge

# Check if PatternHNSWBridge is running and get stats
case PatternHNSWBridge.get_stats() do
  stats when is_map(stats) ->
    IO.puts("✓ Pattern HNSW Bridge is active!")
    IO.puts("  Patterns received: #{stats.patterns_received}")
    IO.puts("  Patterns indexed: #{stats.patterns_indexed}")
    IO.puts("  Indexing errors: #{stats.indexing_errors}")
    IO.puts("  Buffer size: #{stats[:buffer_size] || 0}")
    
    if Map.has_key?(stats, :hnsw_stats) && is_map(stats.hnsw_stats) do
      IO.puts("\n  HNSW Index Stats:")
      IO.puts("    Vectors: #{stats.hnsw_stats[:vector_count] || 0}")
      IO.puts("    Layers: #{stats.hnsw_stats[:layer_count] || 0}")
    end
    
    if stats.patterns_indexed > 0 do
      IO.puts("\n✅ SUCCESS: HNSW pattern storage is active and working!")
    else
      IO.puts("\n⚠️  No patterns indexed yet. Trigger some events to test.")
    end
  error ->
    IO.puts("❌ ERROR getting stats: #{inspect(error)}")
end

# Trigger a test event to generate patterns
alias AutonomousOpponentV2Core.EventBus

IO.puts("\nTriggering test environmental scan...")
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

Process.sleep(1000)

# Check stats again
IO.puts("\nFinal check after triggering events:")
final_stats = PatternHNSWBridge.get_stats()
IO.puts("  Total patterns indexed: #{final_stats.patterns_indexed}")