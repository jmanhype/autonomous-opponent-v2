IO.puts("=== Process Registration Debug ===\n")

# Check EventBus registration
IO.puts("1. EventBus:")
case Process.whereis(AutonomousOpponentV2Core.EventBus) do
  nil -> 
    IO.puts("   ❌ Not registered")
    # Try to find it by looking for the ETS table
    case :ets.info(:event_bus_subscriptions) do
      :undefined -> IO.puts("   ❌ ETS table doesn't exist")
      info -> IO.puts("   ✅ ETS table exists but process not registered\!")
    end
  pid -> 
    IO.puts("   ✅ Registered as #{inspect(pid)}")
    IO.puts("   Process alive? #{Process.alive?(pid)}")
end

IO.puts("\n2. VSM S1 Operations:")
case Process.whereis(AutonomousOpponentV2Core.VSM.S1.Operations) do
  nil -> IO.puts("   ❌ Not registered")
  pid -> IO.puts("   ✅ Registered as #{inspect(pid)}")
end

IO.puts("\n3. Check Supervisor tree:")
case Process.whereis(AutonomousOpponentV2Core.Supervisor) do
  nil -> IO.puts("   ❌ Core Supervisor not running\!")
  sup_pid ->
    IO.puts("   ✅ Core Supervisor: #{inspect(sup_pid)}")
    children = Supervisor.which_children(sup_pid)
    
    # Find EventBus
    event_bus = Enum.find(children, fn 
      {AutonomousOpponentV2Core.EventBus, _, _, _} -> true
      _ -> false
    end)
    
    case event_bus do
      nil -> IO.puts("   ❌ EventBus not in supervision tree\!")
      {_, pid, _, _} when is_pid(pid) -> 
        IO.puts("   ✅ EventBus in tree as #{inspect(pid)} but not registered\!")
      {_, :restarting, _, _} ->
        IO.puts("   🔄 EventBus is restarting\!")
      {_, status, _, _} ->
        IO.puts("   ❓ EventBus status: #{inspect(status)}")
    end
end

# Check all registered names
IO.puts("\n4. All registered processes containing 'Event':")
:erlang.registered()
|> Enum.filter(&(to_string(&1) |> String.contains?("Event")))
|> Enum.each(&IO.puts("   - #{inspect(&1)}"))
