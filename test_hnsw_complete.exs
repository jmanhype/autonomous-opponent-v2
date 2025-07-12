#!/usr/bin/env elixir

# Comprehensive HNSW WebSocket Test Script

IO.puts("\n🚀 Starting Comprehensive HNSW Test...\n")

# Give the system time to fully start
Process.sleep(2000)

# 1. Check all processes
IO.puts("📋 Checking HNSW processes:")
processes = [
  {AutonomousOpponentV2Core.VSM.S4.Supervisor, "S4 Supervisor"},
  {AutonomousOpponentV2Core.VSM.S4.Intelligence, "S4 Intelligence"},
  {AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge, "PatternHNSWBridge"},
  {:hnsw_index, "HNSW Index"},
  {AutonomousOpponentV2Core.VSM.S4.PatternIndexer, "Pattern Indexer"},
  {AutonomousOpponentV2Core.EventBus, "EventBus"}
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

if not all_running do
  IO.puts("\n❌ Not all required processes are running!")
  System.halt(1)
end

# 2. Test EventBus subscriptions
IO.puts("\n📡 Testing EventBus subscriptions...")
try do
  AutonomousOpponentV2Core.EventBus.subscribe(:test_event)
  IO.puts("✅ EventBus subscription successful")
catch
  :exit, {:noproc, _} ->
    IO.puts("❌ EventBus not available")
    System.halt(1)
end

# 3. Test HNSW search functionality
IO.puts("\n🔍 Testing HNSW search...")
vector = for _ <- 1..100, do: :rand.uniform()
case AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex.search(:hnsw_index, vector, 5) do
  {:ok, results} ->
    IO.puts("✅ HNSW search successful!")
    IO.puts("   Found #{length(results)} results")
  {:error, reason} ->
    IO.puts("❌ HNSW search failed: #{inspect(reason)}")
end

# 4. Test pattern indexing
IO.puts("\n📝 Testing pattern indexing...")

# Create test patterns
test_patterns = for i <- 1..5 do
  %{
    id: "test_pattern_#{i}_#{:rand.uniform(10000)}",
    type: :behavioral,
    data: %{
      value: :rand.uniform(),
      timestamp: DateTime.utc_now()
    },
    context: %{
      source: "test_script",
      confidence: 0.8 + :rand.uniform() * 0.2
    }
  }
end

# Publish patterns via EventBus
IO.puts("📤 Publishing #{length(test_patterns)} test patterns...")
AutonomousOpponentV2Core.EventBus.publish(:patterns_detected, test_patterns)

# Give time for processing
Process.sleep(1000)

# 5. Check PatternHNSWBridge stats
IO.puts("\n📊 Checking PatternHNSWBridge stats...")
stats = AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_stats()
IO.puts("Bridge Stats:")
IO.inspect(stats, pretty: true, limit: :infinity)

# 6. Get monitoring info
IO.puts("\n🔍 Getting monitoring info...")
monitoring = AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_monitoring_info()
IO.puts("Monitoring Info:")
IO.inspect(monitoring, pretty: true, limit: :infinity)

# 7. Test pattern retrieval
IO.puts("\n🔎 Testing pattern retrieval...")
if stats[:indexed] > 0 do
  # Generate another vector for search
  search_vector = for _ <- 1..100, do: :rand.uniform()
  
  case GenServer.call(
    AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge,
    {:query_patterns, search_vector, 3}
  ) do
    {:ok, patterns} ->
      IO.puts("✅ Pattern retrieval successful!")
      IO.puts("   Retrieved #{length(patterns)} patterns")
      for {pattern, score} <- patterns do
        IO.puts("   - Pattern #{pattern.id}: score #{Float.round(score, 3)}")
      end
    {:error, reason} ->
      IO.puts("❌ Pattern retrieval failed: #{inspect(reason)}")
  end
else
  IO.puts("⚠️  No patterns indexed yet to search")
end

# 8. Test WebSocket connection
IO.puts("\n🌐 Testing WebSocket connection...")
IO.puts("Starting WebSocket test (this will run for 10 seconds)...")

# Spawn WebSocket test in background
Task.async(fn ->
  System.cmd("node", ["test_websocket_monitoring.js"])
end)

# Let WebSocket test run
Process.sleep(10000)

# 9. Final summary
IO.puts("\n📋 Final Summary:")
final_stats = AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_stats()
IO.puts("  - Total patterns indexed: #{final_stats[:indexed]}")
IO.puts("  - Total patterns deduplicated: #{final_stats[:deduplicated]}")
IO.puts("  - Current backpressure: #{final_stats[:backpressure_active]}")
IO.puts("  - HNSW Index size: #{final_stats[:hnsw_size]}")

IO.puts("\n✨ HNSW test complete!\n")