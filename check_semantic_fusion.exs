# Check SemanticFusion process
sf_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticFusion)

if sf_pid && Process.alive?(sf_pid) do
  IO.puts("SemanticFusion is alive at #{inspect(sf_pid)}")
  
  # Try to get patterns safely
  try do
    case GenServer.call(sf_pid, {:get_patterns, 300}, 1000) do
      {:ok, patterns} ->
        IO.puts("Got #{length(patterns)} patterns")
      {:error, reason} ->
        IO.puts("Error getting patterns: #{inspect(reason)}")
    end
  catch
    :exit, reason ->
      IO.puts("SemanticFusion crashed: #{inspect(reason)}")
  end
else
  IO.puts("SemanticFusion is not running!")
end

# Check if it's in the supervisor
children = Supervisor.which_children(AutonomousOpponentV2Core.Supervisor)
sf_child = Enum.find(children, fn {id, _, _, _} -> 
  id == AutonomousOpponentV2Core.AMCP.Events.SemanticFusion 
end)

IO.puts("\nSemanticFusion in supervisor: #{inspect(sf_child)}")