IO.puts("Testing HLC startup...")

# Start HLC manually
case AutonomousOpponentV2Core.Core.HybridLogicalClock.start_link([]) do
  {:ok, pid} ->
    IO.puts("HLC started successfully with PID: #{inspect(pid)}")
    
    # Test HLC functionality
    case AutonomousOpponentV2Core.Core.HybridLogicalClock.now() do
      {:ok, timestamp} ->
        IO.puts("HLC timestamp: #{inspect(timestamp)}")
      {:error, error} ->
        IO.puts("Error getting timestamp: #{inspect(error)}")
    end
    
  {:error, error} ->
    IO.puts("Failed to start HLC: #{inspect(error)}")
end