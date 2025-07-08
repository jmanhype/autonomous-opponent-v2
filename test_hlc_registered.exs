IO.puts("Checking if HLC is registered...")

# Wait a bit for the system to start
Process.sleep(5000)

# Check if HLC is registered
case Process.whereis(AutonomousOpponentV2Core.Core.HybridLogicalClock) do
  nil ->
    IO.puts("HLC is NOT registered!")
    
    # Check all registered processes
    registered = Process.registered()
    hlc_related = Enum.filter(registered, fn name ->
      String.contains?(to_string(name), "HLC") or
      String.contains?(to_string(name), "Hybrid") or
      String.contains?(to_string(name), "Clock")
    end)
    
    IO.puts("HLC-related registered processes: #{inspect(hlc_related)}")
    
  pid ->
    IO.puts("HLC is registered with PID: #{inspect(pid)}")
    
    # Try to call it
    case GenServer.call(pid, :now) do
      {:ok, timestamp} ->
        IO.puts("HLC call successful! Timestamp: #{inspect(timestamp)}")
      error ->
        IO.puts("HLC call failed: #{inspect(error)}")
    end
end