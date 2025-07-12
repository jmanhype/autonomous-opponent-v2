#!/usr/bin/env elixir

# Start the applications
{:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)
{:ok, _} = Application.ensure_all_started(:autonomous_opponent_web)

# Check which processes are running
IO.puts("\n🔍 Checking running processes...\n")

processes = [
  {AutonomousOpponentV2Core.EventBus, "EventBus"},
  {AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge, "PatternHNSWBridge"},
  {:hnsw_index, "HNSW Index"},
  {AutonomousOpponentV2Core.VSM.S4.PatternIndexer, "Pattern Indexer"},
  {AutonomousOpponentV2Core.EventBus.OrderedDeliverySupervisor, "OrderedDeliverySupervisor"}
]

for {name, display} <- processes do
  case Process.whereis(name) do
    nil -> IO.puts("❌ #{display}: NOT RUNNING")
    pid -> IO.puts("✅ #{display}: Running at #{inspect(pid)}")
  end
end

# Test EventBus subscription
IO.puts("\n📡 Testing EventBus subscription...\n")

try do
  AutonomousOpponentV2Core.EventBus.subscribe(:test_event)
  IO.puts("✅ EventBus subscription successful!")
catch
  :exit, {:noproc, _} ->
    IO.puts("❌ EventBus not available")
  error ->
    IO.puts("❌ EventBus error: #{inspect(error)}")
end

# Test pattern stats
IO.puts("\n📊 Testing pattern stats...\n")

case Process.whereis(AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge) do
  nil ->
    IO.puts("❌ PatternHNSWBridge not available")
  _pid ->
    stats = AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge.get_stats()
    IO.puts("✅ Pattern stats: #{inspect(stats, pretty: true)}")
end

# Test HNSW index
IO.puts("\n🗄️ Testing HNSW index...\n")

case Process.whereis(:hnsw_index) do
  nil ->
    IO.puts("❌ HNSW index not available")
  _pid ->
    # Try a simple search
    vector = for _ <- 1..100, do: :rand.uniform()
    case AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex.search(:hnsw_index, vector, 5) do
      {:ok, results} ->
        IO.puts("✅ HNSW search successful! Results: #{inspect(results)}")
      {:error, reason} ->
        IO.puts("⚠️  HNSW search error: #{inspect(reason)}")
    end
end

IO.puts("\n✨ Process check complete!\n")