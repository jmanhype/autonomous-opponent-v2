#!/usr/bin/env elixir

IO.puts("=== Testing HLC Lifecycle ===")

# Test 1: Check if HLC is registered
IO.puts("\n1. Checking if HLC is registered...")
case Process.whereis(AutonomousOpponentV2Core.Core.HybridLogicalClock) do
  nil -> 
    IO.puts("  ❌ HLC is NOT registered!")
  pid -> 
    IO.puts("  ✅ HLC is registered with PID: #{inspect(pid)}")
    IO.puts("  Process alive? #{Process.alive?(pid)}")
end

# Test 2: Try to call HLC.now()
IO.puts("\n2. Attempting to call HLC.now()...")
try do
  case AutonomousOpponentV2Core.Core.HybridLogicalClock.now() do
    {:ok, timestamp} ->
      IO.puts("  ✅ HLC.now() succeeded!")
      IO.puts("  Timestamp: #{inspect(timestamp)}")
    {:error, reason} ->
      IO.puts("  ❌ HLC.now() failed with error: #{inspect(reason)}")
  end
catch
  :exit, {:noproc, {GenServer, :call, [name, :now, _timeout]}} ->
    IO.puts("  ❌ HLC process not found! Name: #{inspect(name)}")
  :exit, reason ->
    IO.puts("  ❌ Exit caught: #{inspect(reason)}")
  error ->
    IO.puts("  ❌ Error caught: #{inspect(error)}")
end

# Test 3: Check if EventBus is running (since it uses HLC)
IO.puts("\n3. Checking EventBus (which depends on HLC)...")
case Process.whereis(AutonomousOpponentV2Core.EventBus) do
  nil -> 
    IO.puts("  ❌ EventBus is NOT registered!")
  pid -> 
    IO.puts("  ✅ EventBus is registered with PID: #{inspect(pid)}")
    IO.puts("  Process alive? #{Process.alive?(pid)}")
end

# Test 4: Try to publish an event (which will use HLC)
IO.puts("\n4. Testing EventBus.publish (uses HLC internally)...")
try do
  AutonomousOpponentV2Core.EventBus.publish(:test_event, %{test: true})
  IO.puts("  ✅ EventBus.publish succeeded!")
catch
  :exit, reason ->
    IO.puts("  ❌ EventBus.publish failed: #{inspect(reason)}")
  error ->
    IO.puts("  ❌ Error: #{inspect(error)}")
end

# Test 5: Check all running processes with "Clock" in name
IO.puts("\n5. Searching for all Clock-related processes...")
Process.list()
|> Enum.filter(fn pid ->
  case Process.info(pid, :registered_name) do
    {:registered_name, name} when is_atom(name) ->
      String.contains?(Atom.to_string(name), "Clock")
    _ ->
      false
  end
end)
|> Enum.each(fn pid ->
  {:registered_name, name} = Process.info(pid, :registered_name)
  IO.puts("  Found: #{name} - PID: #{inspect(pid)}")
end)

# Test 6: Check the supervision tree
IO.puts("\n6. Checking supervision tree for HLC...")
case Process.whereis(AutonomousOpponentV2Core.Supervisor) do
  nil ->
    IO.puts("  ❌ Core supervisor not found!")
  sup_pid ->
    IO.puts("  ✅ Core supervisor found: #{inspect(sup_pid)}")
    children = Supervisor.which_children(sup_pid)
    hlc_child = Enum.find(children, fn
      {AutonomousOpponentV2Core.Core.HybridLogicalClock, _, _, _} -> true
      _ -> false
    end)
    
    case hlc_child do
      nil ->
        IO.puts("  ❌ HLC not found in supervision tree!")
      {_, child_pid, _, _} ->
        IO.puts("  ✅ HLC found in supervision tree!")
        IO.puts("     Child PID: #{inspect(child_pid)}")
        IO.puts("     Status: #{if child_pid == :undefined, do: "NOT STARTED", else: "Started"}")
    end
end

IO.puts("\n=== Test Complete ===")