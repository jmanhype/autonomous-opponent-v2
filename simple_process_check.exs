IO.puts("🔍 Checking Metrics Cluster Status")

# Connect to running node
case :net_kernel.connect_node(:"test@127.0.0.1") do
  true ->
    IO.puts("✅ Connected to test@127.0.0.1")
    
    # Check if Metrics Cluster Supervisor is running
    result = :rpc.call(:"test@127.0.0.1", Process, :whereis, [AutonomousOpponentV2Core.Metrics.Cluster.Supervisor])
    
    case result do
      nil -> 
        IO.puts("❌ Metrics Cluster Supervisor not running")
      pid when is_pid(pid) ->
        IO.puts("✅ Metrics Cluster Supervisor running: #{inspect(pid)}")
        
        # Check children
        children = :rpc.call(:"test@127.0.0.1", Supervisor, :which_children, [pid])
        IO.puts("\nChildren:")
        Enum.each(children, fn {id, child_pid, _type, _modules} ->
          status = if child_pid == :undefined, do: "❌", else: "✅"
          IO.puts("  #{status} #{id}")
        end)
    end
    
    # Check PatternAggregator specifically
    pa_result = :rpc.call(:"test@127.0.0.1", Process, :whereis, [AutonomousOpponentV2Core.Metrics.Cluster.PatternAggregator])
    if pa_result do
      IO.puts("\n✅ PatternAggregator is running: #{inspect(pa_result)}")
    else
      IO.puts("\n❌ PatternAggregator is NOT running")
    end
    
  false ->
    IO.puts("❌ Could not connect to test@127.0.0.1")
    IO.puts("   Make sure the server is running with: elixir --name test@127.0.0.1 -S mix phx.server")
end