#!/usr/bin/env elixir

# Connect to the running node
IO.puts("Connecting to test@127.0.0.1...")
case Node.connect(:"test@127.0.0.1") do
  true ->
    IO.puts("✓ Connected successfully")
    
    # Check if Metrics.Cluster.Supervisor is running
    metrics_supervisor = :rpc.call(:"test@127.0.0.1", Process, :whereis, [AutonomousOpponentCore.Metrics.Cluster.Supervisor])
    
    case metrics_supervisor do
      nil ->
        IO.puts("✗ Metrics.Cluster.Supervisor is NOT running")
      pid when is_pid(pid) ->
        IO.puts("✓ Metrics.Cluster.Supervisor is running at #{inspect(pid)}")
        
        # Check its children
        children = :rpc.call(:"test@127.0.0.1", Supervisor, :which_children, [pid])
        IO.puts("\nChildren of Metrics.Cluster.Supervisor:")
        Enum.each(children, fn {id, child_pid, type, modules} ->
          status = if is_pid(child_pid) and :rpc.call(:"test@127.0.0.1", Process, :alive?, [child_pid]), do: "✓ Running", else: "✗ Not running"
          IO.puts("  #{inspect(id)}: #{status} (#{inspect(child_pid)})")
        end)
        
        # Specifically check PatternAggregator
        pattern_aggregator = :rpc.call(:"test@127.0.0.1", Process, :whereis, [AutonomousOpponentCore.Metrics.Cluster.PatternAggregator])
        case pattern_aggregator do
          nil -> IO.puts("\n✗ PatternAggregator is NOT registered")
          pid -> IO.puts("\n✓ PatternAggregator is registered at #{inspect(pid)}")
        end
    end
    
    # Check if Node.alive? returns true on the remote node
    node_alive = :rpc.call(:"test@127.0.0.1", Node, :alive?, [])
    IO.puts("\nNode.alive? on remote: #{inspect(node_alive)}")
    
    # Check node name
    node_name = :rpc.call(:"test@127.0.0.1", Node, :self, [])
    IO.puts("Node name: #{inspect(node_name)}")
    
  false ->
    IO.puts("✗ Failed to connect to test@127.0.0.1")
    IO.puts("Make sure the server is running with: elixir --name test@127.0.0.1 -S mix phx.server")
end