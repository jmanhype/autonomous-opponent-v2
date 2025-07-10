IO.puts("Checking HLC...")
pid = Process.whereis(AutonomousOpponentV2Core.Core.HybridLogicalClock)
IO.puts("HLC PID: #{inspect(pid)}")

if pid do
  IO.puts("Testing HLC.now()...")
  try do
    result = AutonomousOpponentV2Core.Core.HybridLogicalClock.now()
    IO.puts("Result: #{inspect(result)}")
  rescue
    e -> IO.puts("Error: #{inspect(e)}")
  catch
    :exit, reason -> IO.puts("Exit: #{inspect(reason)}")
  end
else
  IO.puts("HLC not running!")
end