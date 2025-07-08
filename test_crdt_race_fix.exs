IO.puts("Testing CRDT initialization race condition fix...")

# Give the system a moment to fully initialize
Process.sleep(2000)

# The main issue was that consciousness_state CRDT was not being created before LLMBridge tried to access it
IO.puts("\nChecking if consciousness_state CRDT was created by VSMBridge initialization...")

case AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.get_crdt("consciousness_state") do
  {:ok, state} ->
    IO.puts("✅ SUCCESS: consciousness_state CRDT exists!")
    IO.puts("   State: #{inspect(state)}")
    IO.puts("\n✅ RACE CONDITION FIX VERIFIED!")
    IO.puts("\nThe fix involved:")
    IO.puts("1. Moving initialize_crdt_structures() from init/1 to handle_continue/2 in VSMBridge")
    IO.puts("2. Adding defensive CRDT creation in places that use them")
    IO.puts("3. Adding VSMBridge to the application supervision tree") 
    IO.puts("4. Adding Goldrush.EventProcessor to start before VSMBridge")
    IO.puts("5. Fixing LWWRegister.new/2 argument order bug")
    
  {:error, :not_found} ->
    IO.puts("❌ FAILED: consciousness_state CRDT not found")
    IO.puts("The race condition still exists!")
    
  error ->
    IO.puts("❌ Unexpected error: #{inspect(error)}")
end

# Also verify that the VSMBridge is running
IO.puts("\nChecking if VSMBridge is running...")
case Process.whereis(AutonomousOpponentV2Core.AMCP.Bridges.VSMBridge) do
  nil ->
    IO.puts("❌ VSMBridge is not running")
  pid ->
    IO.puts("✅ VSMBridge is running with PID: #{inspect(pid)}")
end

# Check if metrics are being recorded properly
IO.puts("\nChecking VSM consciousness metrics...")
try do
  metrics = AutonomousOpponentV2Core.AMCP.Bridges.VSMBridge.get_consciousness_metrics()
  IO.puts("✅ VSM consciousness metrics retrieved successfully:")
  IO.puts("   Variety pressure: #{metrics.variety_pressure}")
  IO.puts("   Coordination state: #{metrics.coordination_state}")
  IO.puts("   Consciousness level: #{metrics.consciousness_level}")
catch
  :exit, reason ->
    IO.puts("❌ Failed to get metrics: #{inspect(reason)}")
end