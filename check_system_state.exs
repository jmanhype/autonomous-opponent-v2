# Check the current state of the system processes

IO.puts("\n=== System Process Status ===\n")

processes = [
  {AutonomousOpponentV2Core.Consciousness, "Consciousness"},
  {AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge, "LLMBridge"},
  {AutonomousOpponentV2Core.EventBus, "EventBus"},
  {AutonomousOpponentV2Core.Core.HybridLogicalClock, "HLC"},
  {AutonomousOpponentV2Core.AMCP.Memory.CRDTStore, "CRDTStore"},
  {AutonomousOpponentV2Core.Core.RateLimiter, "RateLimiter"},
  {AutonomousOpponentV2Core.Core.Metrics, "Metrics"},
  {AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer, "SemanticAnalyzer"},
  {AutonomousOpponentV2Core.AMCP.Events.SemanticFusion, "SemanticFusion"}
]

running = Enum.reduce(processes, 0, fn {module, name}, count ->
  case Process.whereis(module) do
    nil -> 
      IO.puts("❌ #{name}: NOT RUNNING")
      count
    pid -> 
      IO.puts("✅ #{name}: Running (#{inspect(pid)})")
      count + 1
  end
end)

IO.puts("\n#{running}/#{length(processes)} processes running")

# Check if we can run the tests
if running == 0 do
  IO.puts("\n⚠️  No core processes are running. The system needs to be started.")
  IO.puts("Run: iex -S mix phx.server")
else
  IO.puts("\n✓ Some processes are running. Testing fallback removal...")
end