IO.puts("Testing HLC direct access...")

# Try to find HLC process
hlc_pid = Process.whereis(AutonomousOpponentV2Core.Core.HybridLogicalClock)
IO.puts("HLC PID from whereis: #{inspect(hlc_pid)}")

# List all registered processes
registered = Process.registered()
IO.puts("\nAll registered processes:")
registered
|> Enum.filter(fn name -> 
  name |> to_string() |> String.contains?("HLC") or
  name |> to_string() |> String.contains?("HybridLogicalClock") or
  name |> to_string() |> String.contains?("Clock")
end)
|> Enum.each(&IO.puts("  #{inspect(&1)}"))

# Try GenServer.whereis
IO.puts("\nTrying GenServer.whereis:")
case GenServer.whereis(AutonomousOpponentV2Core.Core.HybridLogicalClock) do
  nil -> IO.puts("  Not found via GenServer.whereis")
  pid -> IO.puts("  Found PID: #{inspect(pid)}")
end

# Try to call it directly if we found it
if hlc_pid do
  try do
    result = GenServer.call(hlc_pid, :now, 5000)
    IO.puts("\nHLC call result: #{inspect(result)}")
  catch
    kind, reason ->
      IO.puts("\nError calling HLC: #{kind} - #{inspect(reason)}")
  end
end