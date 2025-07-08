# Try to register a test process with the same name
test_name = AutonomousOpponentV2Core.Core.HybridLogicalClock

IO.puts("Attempting to register with name: #{inspect(test_name)}")

case Process.register(self(), test_name) do
  true -> 
    IO.puts("Successfully registered!")
    Process.unregister(test_name)
  false ->
    IO.puts("Failed to register - name already taken")
    
    # Find who has it
    case Process.whereis(test_name) do
      nil -> IO.puts("  But whereis returns nil?!")
      pid -> IO.puts("  Owned by: #{inspect(pid)}")
    end
end

# Check the atom itself
IO.puts("\nAtom details:")
IO.puts("  As string: #{inspect(to_string(test_name))}")
IO.puts("  Module? #{is_atom(test_name)}")

# Try different variations
IO.puts("\nTrying variations:")
[
  AutonomousOpponentV2Core.Core.HybridLogicalClock,
  :"Elixir.AutonomousOpponentV2Core.Core.HybridLogicalClock",
  :AutonomousOpponentV2Core_Core_HybridLogicalClock
]
|> Enum.each(fn name ->
  pid = Process.whereis(name)
  IO.puts("  #{inspect(name)}: #{inspect(pid)}")
end)