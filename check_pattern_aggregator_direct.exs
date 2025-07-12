#!/usr/bin/env elixir

# Connect to the test node
IO.puts("Connecting to test@127.0.0.1...")
case Node.connect(:"test@127.0.0.1") do
  true ->
    IO.puts("Successfully connected to test@127.0.0.1")
    
    # Wait a moment for connection to stabilize
    Process.sleep(1000)
    
    # Try to call PatternAggregator directly
    IO.puts("\nAttempting to call PatternAggregator.get_top_patterns/1...")
    
    try do
      result = :rpc.call(
        :"test@127.0.0.1",
        AutonomousOpponentCore.Metrics.Cluster.PatternAggregator,
        :get_top_patterns,
        [10]
      )
      
      case result do
        {:badrpc, reason} ->
          IO.puts("RPC call failed: #{inspect(reason)}")
        patterns ->
          IO.puts("Success! Got patterns: #{inspect(patterns)}")
      end
    catch
      error ->
        IO.puts("Error calling PatternAggregator: #{inspect(error)}")
    end
    
    # Also try to check if the process is registered
    IO.puts("\nChecking if PatternAggregator process is registered...")
    registered = :rpc.call(:"test@127.0.0.1", Process, :whereis, [AutonomousOpponentCore.Metrics.Cluster.PatternAggregator])
    IO.puts("Process whereis result: #{inspect(registered)}")
    
    # Check all registered processes
    IO.puts("\nAll registered processes on remote node:")
    all_registered = :rpc.call(:"test@127.0.0.1", Process, :registered, [])
    case all_registered do
      {:badrpc, reason} ->
        IO.puts("Failed to get registered processes: #{inspect(reason)}")
      procs ->
        procs
        |> Enum.filter(fn name -> 
          name_str = Atom.to_string(name)
          String.contains?(name_str, "Pattern") or String.contains?(name_str, "pattern")
        end)
        |> case do
          [] -> IO.puts("No pattern-related processes found")
          filtered -> IO.puts("Pattern-related processes: #{inspect(filtered)}")
        end
    end
    
  false ->
    IO.puts("Failed to connect to test@127.0.0.1")
    IO.puts("Make sure the server is running with: elixir --name test@127.0.0.1 -S mix phx.server")
end