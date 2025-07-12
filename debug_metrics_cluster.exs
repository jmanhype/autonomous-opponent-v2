#!/usr/bin/env elixir

IO.puts("Debug: Metrics Cluster Startup Check")
IO.puts("=====================================")

# Check node status
IO.puts("\nNode Status:")
IO.puts("  Node.alive?: #{Node.alive?()}")
IO.puts("  Node.self: #{Node.self()}")

# Check configuration
metrics_enabled = Application.get_env(:autonomous_opponent_core, :metrics_cluster_enabled, true)
IO.puts("\nConfiguration:")
IO.puts("  metrics_cluster_enabled: #{metrics_enabled}")

# Check what would be started
should_start = Node.alive?() and metrics_enabled
IO.puts("\nDecision:")
IO.puts("  Should start Metrics.Cluster.Supervisor: #{should_start}")

# If running on a named node, check if supervisor is running
if Node.alive?() do
  IO.puts("\nChecking running processes...")
  
  # Wait a bit for processes to start
  Process.sleep(2000)
  
  # Check if Metrics.Cluster.Supervisor is running
  metrics_sup = Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.Supervisor)
  IO.puts("  Metrics.Cluster.Supervisor: #{inspect(metrics_sup)}")
  
  if metrics_sup do
    children = Supervisor.which_children(metrics_sup)
    IO.puts("  Children: #{length(children)}")
    Enum.each(children, fn {id, pid, type, _modules} ->
      status = if is_pid(pid) and Process.alive?(pid), do: "✓", else: "✗"
      IO.puts("    #{status} #{id}: #{inspect(pid)}")
    end)
  end
  
  # Check if PatternAggregator is running
  aggregator = Process.whereis(AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator)
  IO.puts("\n  PatternAggregator: #{inspect(aggregator)}")
end