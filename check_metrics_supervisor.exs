#!/usr/bin/env elixir

# This script connects to the running node and checks the supervisor tree

target_node = :"test@127.0.0.1"
IO.puts("Connecting to #{target_node}...")

if Node.connect(target_node) do
  IO.puts("Connected!\n")
  
  # Get the top-level supervisor children
  result = :rpc.call(target_node, Supervisor, :which_children, [AutonomousOpponentV2Core.Supervisor])
  
  case result do
    {:badrpc, reason} ->
      IO.puts("RPC failed: #{inspect(reason)}")
      
    children when is_list(children) ->
      IO.puts("Top-level children of AutonomousOpponentV2Core.Supervisor:")
      
      # Find the Metrics.Cluster.Supervisor entry
      metrics_cluster_entry = Enum.find(children, fn
        {AutonomousOpponentV2Core.Metrics.Cluster.Supervisor, _, _, _} -> true
        _ -> false
      end)
      
      if metrics_cluster_entry do
        {id, pid, type, modules} = metrics_cluster_entry
        IO.puts("\nFound Metrics.Cluster.Supervisor entry:")
        IO.puts("  ID: #{inspect(id)}")
        IO.puts("  PID: #{inspect(pid)}")
        IO.puts("  Type: #{inspect(type)}")
        IO.puts("  Modules: #{inspect(modules)}")
        
        if is_pid(pid) do
          # Check if supervisor has children
          children_result = :rpc.call(target_node, Supervisor, :which_children, [pid])
          case children_result do
            {:badrpc, _} -> IO.puts("  Could not get children")
            children -> IO.puts("  Number of children: #{length(children)}")
          end
        end
      else
        IO.puts("\nMetrics.Cluster.Supervisor not found in supervisor tree!")
        IO.puts("\nAll top-level children:")
        Enum.each(children, fn {id, pid, _type, _modules} ->
          status = if is_pid(pid), do: "✓", else: "✗"
          IO.puts("  #{status} #{inspect(id)}")
        end)
      end
  end
else
  IO.puts("Failed to connect to node")
end