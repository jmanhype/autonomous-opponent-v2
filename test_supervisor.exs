IO.puts("Checking supervisor children...")

# Get the main supervisor
case Process.whereis(AutonomousOpponentV2Core.Supervisor) do
  nil -> 
    IO.puts("Core supervisor not found!")
  pid ->
    IO.puts("Core supervisor PID: #{inspect(pid)}")
    
    # Get children
    children = Supervisor.which_children(pid)
    IO.puts("\nSupervisor children:")
    
    children
    |> Enum.each(fn {id, child_pid, type, modules} ->
      IO.puts("  #{inspect(id)}: #{inspect(child_pid)} (#{inspect(modules)})")
      
      # Check if this is HLC
      if modules == [AutonomousOpponentV2Core.Core.HybridLogicalClock] do
        IO.puts("    ^^^ THIS IS HLC!")
        
        if is_pid(child_pid) do
          # Try to call it
          try do
            result = GenServer.call(child_pid, :now, 1000)
            IO.puts("    HLC call result: #{inspect(result)}")
          catch
            kind, reason ->
              IO.puts("    Error calling HLC: #{kind} - #{inspect(reason)}")
          end
        end
      end
    end)
end