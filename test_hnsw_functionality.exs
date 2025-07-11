#!/usr/bin/env elixir

# Start the applications
{:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)
{:ok, _} = Application.ensure_all_started(:autonomous_opponent_web)

IO.puts("\n🚀 Testing HNSW Functionality...\n")

# Give system time to start
Process.sleep(1000)

# Check processes
IO.puts("📋 Checking HNSW processes:")
processes = [
  {AutonomousOpponentV2Core.EventBus, "EventBus"},
  {AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge, "PatternHNSWBridge"},
  {:hnsw_index, "HNSW Index"},
  {AutonomousOpponentV2Core.VSM.S4.VectorStore.PatternIndexer, "Pattern Indexer"}
]

all_running = Enum.all?(processes, fn {name, display} ->
  case Process.whereis(name) do
    nil -> 
      IO.puts("❌ #{display}: NOT RUNNING")
      false
    pid -> 
      IO.puts("✅ #{display}: Running at #{inspect(pid)}")
      true
  end
end)

if all_running do
  IO.puts("\n🧪 Testing pattern search...")
  
  # Generate a random vector
  vector = for _ <- 1..100, do: :rand.uniform()
  
  case AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex.search(:hnsw_index, vector, 5) do
    {:ok, results} ->
      IO.puts("✅ HNSW search successful!")
      IO.puts("   Results: #{inspect(results)}")
    {:error, reason} ->
      IO.puts("❌ HNSW search failed: #{inspect(reason)}")
  end
  
  IO.puts("\n📊 Pattern stats:")
  stats = AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_stats()
  IO.puts("   #{inspect(stats, pretty: true)}")
  
  IO.puts("\n🔍 Testing pattern indexing...")
  test_pattern = %{
    id: "test_pattern_#{:rand.uniform(10000)}",
    type: :test,
    data: %{value: :rand.uniform()},
    context: %{source: "test_script"}
  }
  
  # Publish a test pattern event
  AutonomousOpponentV2Core.EventBus.publish(:patterns_detected, [test_pattern])
  Process.sleep(100)
  
  # Check updated stats
  new_stats = AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_stats()
  IO.puts("\n📊 Updated stats after indexing:")
  IO.puts("   #{inspect(new_stats, pretty: true)}")
else
  IO.puts("\n❌ Not all required processes are running. Cannot continue tests.")
end

IO.puts("\n✨ Test complete!\n")