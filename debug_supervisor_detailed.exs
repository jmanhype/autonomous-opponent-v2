#!/usr/bin/env elixir

IO.puts("Detailed Supervisor Debug")
IO.puts("========================\n")

# Connect to the running node
target_node = :"test@127.0.0.1"
IO.puts("Connecting to node: #{target_node}")

connected = Node.connect(target_node)

if connected do
    IO.puts("✓ Connected successfully")
    
    # Wait for connection to stabilize
    Process.sleep(1000)
    
    # Check all supervisors in the system
    IO.puts("\nAll Supervisors:")
    :rpc.call(target_node, :supervisor, :which_children, [AutonomousOpponentV2Core.Supervisor])
    |> Enum.each(fn {id, pid, _type, _modules} ->
      status = if is_pid(pid) and :rpc.call(target_node, Process, :alive?, [pid]), do: "✓", else: "✗"
      IO.puts("  #{status} #{inspect(id)}: #{inspect(pid)}")
    end)
    
    # Check specifically for Metrics.Cluster.Supervisor
    IO.puts("\nMetrics.Cluster.Supervisor lookup:")
    metrics_sup = :rpc.call(target_node, Process, :whereis, [AutonomousOpponentV2Core.Metrics.Cluster.Supervisor])
    IO.puts("  Process.whereis result: #{inspect(metrics_sup)}")
    
    # Try to find it by searching all processes
    IO.puts("\nSearching all processes for Metrics.Cluster.Supervisor:")
    all_procs = :rpc.call(target_node, Process, :list, [])
    found = Enum.find(all_procs, fn pid ->
      try do
        {:dictionary, dict} = :rpc.call(target_node, Process, :info, [pid, :dictionary])
        case Keyword.get(dict, :"$initial_call") do
          {AutonomousOpponentV2Core.Metrics.Cluster.Supervisor, :init, 1} -> true
          _ -> false
        end
      rescue
        _ -> false
      end
    end)
    
    if found do
      IO.puts("  Found supervisor at PID: #{inspect(found)}")
      info = :rpc.call(target_node, Process, :info, [found])
      IO.puts("  Process info: #{inspect(info)}")
    else
      IO.puts("  Supervisor process not found")
    end
    
    # Check if any of the expected children are running
    IO.puts("\nChecking expected children:")
    children = [
      AutonomousOpponentV2Core.Metrics.Cluster.TimeSeriesStore,
      AutonomousOpponentV2Core.Metrics.Cluster.CRDTStore,
      AutonomousOpponentV2Core.Metrics.Cluster.QueryEngine,
      AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator,
      AutonomousOpponentV2Core.Metrics.Cluster.Aggregator,
      AutonomousOpponentV2Core.Metrics.Cluster.EventBridge
    ]
    
    Enum.each(children, fn module ->
      pid = :rpc.call(target_node, Process, :whereis, [module])
      status = if is_pid(pid), do: "✓", else: "✗"
      IO.puts("  #{status} #{inspect(module)}: #{inspect(pid)}")
    end)
    
else
    IO.puts("✗ Failed to connect to node")
end