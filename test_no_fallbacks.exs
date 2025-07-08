# Test script to verify that fallbacks have been removed
# Run with: elixir test_no_fallbacks.exs

alias AutonomousOpponentV2Core.Consciousness
alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge

IO.puts("\n=== Testing Fallback Removal ===\n")

# Test 1: Consciousness.get_consciousness_state without running consciousness
IO.puts("Test 1: Consciousness.get_consciousness_state")
case Consciousness.get_consciousness_state() do
  {:ok, state} ->
    IO.puts("❌ FAIL: Got state when consciousness not running:")
    IO.inspect(state, limit: 3)
  {:error, reason} ->
    IO.puts("✅ PASS: Correctly returned error: #{inspect(reason)}")
end

# Test 2: LLMBridge.converse_with_consciousness without LLMBridge running
IO.puts("\nTest 2: LLMBridge.converse_with_consciousness")
case LLMBridge.converse_with_consciousness("Hello, are you there?") do
  {:ok, response} ->
    IO.puts("❌ FAIL: Got response when LLMBridge not running:")
    IO.puts(response)
  {:error, reason} ->
    IO.puts("✅ PASS: Correctly returned error: #{inspect(reason)}")
end

# Test 3: LLMBridge.call_llm_api without LLMBridge running  
IO.puts("\nTest 3: LLMBridge.call_llm_api")
case LLMBridge.call_llm_api("Test prompt", :test_intent) do
  {:ok, response} ->
    IO.puts("❌ FAIL: Got response when LLMBridge not running:")
    IO.puts(response)
  {:error, reason} ->
    IO.puts("✅ PASS: Correctly returned error: #{inspect(reason)}")
end

IO.puts("\n=== Test Complete ===\n")