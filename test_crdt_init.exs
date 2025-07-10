IO.puts("Testing CRDT initialization race condition fix...")

# Give the system a moment to fully initialize
Process.sleep(2000)

# Test 1: Check if consciousness_state CRDT exists
IO.puts("\nTest 1: Checking consciousness_state CRDT...")
case AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.get_crdt("consciousness_state") do
  {:ok, state} ->
    IO.puts("✓ consciousness_state CRDT exists: #{inspect(state)}")
  {:error, :not_found} ->
    IO.puts("✗ consciousness_state CRDT not found - this indicates the race condition still exists")
  error ->
    IO.puts("✗ Unexpected error: #{inspect(error)}")
end

# Test 2: Check if algedonic_history CRDT exists
IO.puts("\nTest 2: Checking algedonic_history CRDT...")
case AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.get_crdt("algedonic_history") do
  {:ok, history} ->
    IO.puts("✓ algedonic_history CRDT exists with #{length(history)} entries")
  {:error, :not_found} ->
    IO.puts("✗ algedonic_history CRDT not found")
  error ->
    IO.puts("✗ Unexpected error: #{inspect(error)}")
end

# Test 3: Check VSM subsystem CRDTs
IO.puts("\nTest 3: Checking VSM subsystem CRDTs...")
vsm_subsystems = [:s1, :s2, :s3, :s4, :s5]
for subsystem <- vsm_subsystems do
  for crdt_type <- ["#{subsystem}_variety", "#{subsystem}_operations", "#{subsystem}_absorption"] do
    case AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.get_crdt(crdt_type) do
      {:ok, _value} ->
        IO.puts("✓ #{crdt_type} CRDT exists")
      {:error, :not_found} ->
        IO.puts("✗ #{crdt_type} CRDT not found")
      _ ->
        :ok
    end
  end
end

# Test 4: Test LLMBridge can gather consciousness state without timeout
IO.puts("\nTest 4: Testing LLMBridge consciousness state gathering...")
try do
  # This function was causing timeouts before our fix
  result = AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge.gather_consciousness_state()
  IO.puts("✓ LLMBridge successfully gathered consciousness state: #{inspect(result)}")
catch
  :exit, {:timeout, _} ->
    IO.puts("✗ Timeout occurred - race condition still exists!")
  :exit, reason ->
    IO.puts("✗ Exit with reason: #{inspect(reason)}")
end

# Test 5: List all CRDTs to see what was created
IO.puts("\nTest 5: Listing all CRDTs...")
crdts = AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.list_crdts()
IO.puts("Total CRDTs created: #{length(crdts)}")
Enum.each(crdts, fn crdt ->
  IO.puts("  - #{crdt.id} (#{crdt.type})")
end)

IO.puts("\n✅ CRDT initialization test completed!")