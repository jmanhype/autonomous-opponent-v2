#!/usr/bin/env elixir

IO.puts("🔍 Checking Running Processes\n")

# Check specific processes
processes = [
  {AutonomousOpponentV2Core.Metrics.Cluster.Supervisor, "Metrics Cluster Supervisor"},
  {AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator, "PatternAggregator"},
  {AutonomousOpponentV2Core.Metrics.Cluster.CRDTStore, "CRDT Store"},
  {AutonomousOpponentV2Core.Metrics.Cluster.TimeSeriesStore, "Time Series Store"},
  {AutonomousOpponentV2Core.Metrics.Cluster.QueryEngine, "Query Engine"},
  {AutonomousOpponentV2Core.Metrics.Cluster.Aggregator, "Aggregator"},
  {AutonomousOpponentV2Core.Metrics.Cluster.EventBridge, "Event Bridge"},
  {AutonomousOpponentV2Core.VSM.S4.PatternHNSWBridge, "PatternHNSWBridge"},
  {:hnsw_index, "HNSW Index"}
]

Enum.each(processes, fn {name, label} ->
  case Process.whereis(name) do
    nil -> IO.puts("❌ #{label}")
    pid -> IO.puts("✅ #{label} - #{inspect(pid)}")
  end
end)

# Check if supervisor has children
IO.puts("\n📦 Metrics Cluster Supervisor Children:")
case Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Supervisor) do
  nil -> 
    IO.puts("  ❌ Supervisor not running")
  pid ->
    try do
      children = Supervisor.which_children(pid)
      if children == [] do
        IO.puts("  ⚠️  No children!")
      else
        Enum.each(children, fn {id, child_pid, type, _modules} ->
          status = case child_pid do
            :undefined -> "❌ Not started"
            pid when is_pid(pid) -> "✅ Running (#{inspect(pid)})"
            _ -> "❓ Unknown"
          end
          IO.puts("  #{status} - #{id}")
        end)
      end
    catch
      _, _ -> IO.puts("  ❌ Error checking children")
    end
end

IO.puts("\n🌐 Node info:")
IO.puts("  Node: #{node()}")
IO.puts("  Alive: #{Node.alive?()}")
IO.puts("  Cookie: #{Node.get_cookie()}")