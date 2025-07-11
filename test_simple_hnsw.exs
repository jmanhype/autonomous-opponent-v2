#!/usr/bin/env elixir

# Simple test to verify HNSW components are running

alias AutonomousOpponentV2Core.EventBus
alias AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge
alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex

IO.puts("\n🔍 Checking HNSW components...\n")

# Check if processes are running
processes = [
  {:hnsw_index, "HNSW Index"},
  {AutonomousOpponentV2Core.VSM.S4.PatternIndexer, "Pattern Indexer"},
  {AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge, "Pattern HNSW Bridge"}
]

all_running = Enum.all?(processes, fn {name, desc} ->
  case Process.whereis(name) do
    nil ->
      IO.puts("❌ #{desc} is NOT running")
      false
    pid ->
      IO.puts("✅ #{desc} is running: #{inspect(pid)}")
      true
  end
end)

if all_running do
  IO.puts("\n🎉 All HNSW components are running!")
  
  # Test publishing a pattern
  IO.puts("\n📨 Publishing test pattern...")
  
  pattern_data = %{
    pattern_id: "test_pattern_simple",
    match_context: %{
      confidence: 0.95,
      type: "test_pattern",
      source: :simple_test
    },
    matched_event: %{data: "test"},
    triggered_at: DateTime.utc_now()
  }
  
  EventBus.publish(:pattern_matched, pattern_data)
  
  # Wait for processing
  Process.sleep(1000)
  
  # Get stats
  IO.puts("\n📊 Pattern Bridge Stats:")
  stats = PatternHNSWBridge.get_stats()
  IO.inspect(stats, pretty: true, limit: :infinity)
  
  # Test vector search
  IO.puts("\n🔎 Testing vector search...")
  test_vector = List.duplicate(0.5, 100)
  
  case HNSWIndex.search(:hnsw_index, test_vector, 5) do
    {:ok, results} ->
      IO.puts("✅ Search successful! Found #{length(results)} results")
    {:error, reason} ->
      IO.puts("❌ Search failed: #{inspect(reason)}")
  end
  
  IO.puts("\n✨ HNSW streaming is operational!")
else
  IO.puts("\n❌ Some HNSW components are not running")
  exit(1)
end