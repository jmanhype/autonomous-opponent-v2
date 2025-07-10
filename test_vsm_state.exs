IO.puts("=== Testing VSM State Retrieval ===")

alias AutonomousOpponentV2Core.VSM.{S1, S2, S3, S4, S5}

subsystems = [
  {S1, AutonomousOpponentV2Core.VSM.S1.Operations},
  {S2, AutonomousOpponentV2Core.VSM.S2.Coordination},
  {S3, AutonomousOpponentV2Core.VSM.S3.Control},
  {S4, AutonomousOpponentV2Core.VSM.S4.Intelligence},
  {S5, AutonomousOpponentV2Core.VSM.S5.Policy}
]

Enum.each(subsystems, fn {short_name, full_module} ->
  IO.puts("\n--- Testing #{short_name} (#{full_module}) ---")
  
  case GenServer.whereis(full_module) do
    nil ->
      IO.puts("❌ Process not registered")
    pid ->
      IO.puts("✅ Process found: #{inspect(pid)}")
      
      # Try to call :get_metrics
      try do
        result = GenServer.call(full_module, :get_metrics, 5_000)
        IO.puts("✅ :get_metrics succeeded: #{inspect(result)}")
        
        case result do
          %{variety_absorbed: variety} ->
            IO.puts("✅ variety_absorbed found: #{variety}")
          _ ->
            IO.puts("❌ variety_absorbed NOT found in result")
        end
      catch
        :exit, {:timeout, _} ->
          IO.puts("❌ :get_metrics timed out")
        :exit, reason ->
          IO.puts("❌ :get_metrics failed: #{inspect(reason)}")
      rescue
        e ->
          IO.puts("❌ :get_metrics error: #{inspect(e)}")
      end
  end
end)

IO.puts("\n=== Testing EventBus.publish (the original trigger) ===")
try do
  AutonomousOpponentV2Core.EventBus.publish(:vsm_state_query, %{
    type: :state_check,
    source: :test_script,
    timestamp: DateTime.utc_now()
  })
  IO.puts("✅ EventBus.publish succeeded")
catch
  :exit, reason ->
    IO.puts("❌ EventBus.publish failed: #{inspect(reason)}")
end

IO.puts("\n=== Test Complete ===")