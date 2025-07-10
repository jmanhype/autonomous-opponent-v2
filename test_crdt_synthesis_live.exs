#!/usr/bin/env elixir

# Live test of CRDT synthesis improvements
# This test runs against the actual implementation

Code.require_file("apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/event_bus.ex")

defmodule CRDTSynthesisLiveTest do
  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
  alias AutonomousOpponentV2Core.EventBus
  
  def run do
    IO.puts("\n🚀 LIVE CRDT SYNTHESIS TEST")
    IO.puts("=" <> String.duplicate("=", 60))
    
    # Subscribe to synthesis events
    EventBus.subscribe(:memory_synthesis)
    EventBus.subscribe(:memory_synthesis_failed)
    
    # Test belief-triggered synthesis
    test_belief_triggered_synthesis()
    
    # Test concurrent synthesis limiting
    test_concurrent_synthesis()
    
    IO.puts("\n✅ Live synthesis tests completed!")
  end
  
  defp test_belief_triggered_synthesis do
    IO.puts("\n📊 Testing Belief-Triggered Synthesis")
    IO.puts("-" <> String.duplicate("-", 40))
    
    # Create beliefs to trigger synthesis
    IO.puts("  • Creating 50 belief updates...")
    
    Enum.each(1..50, fn i ->
      CRDTStore.create_crdt("belief_#{i}", :or_set)
      CRDTStore.update_crdt("belief_#{i}", :add, %{
        belief: "test_belief_#{i}",
        confidence: :rand.uniform(),
        timestamp: DateTime.utc_now()
      })
      
      # Simulate belief change events
      EventBus.publish(:amcp_belief_changed, %{
        agent_id: "test_agent",
        belief_id: "belief_#{i}",
        change_type: :updated
      })
      
      if rem(i, 10) == 0 do
        IO.puts("  • #{i} beliefs created...")
      end
      
      Process.sleep(10) # Small delay to simulate realistic updates
    end)
    
    IO.puts("  • Waiting for synthesis to trigger...")
    
    # Wait for synthesis result
    receive do
      {:event_bus_hlc, %{type: :memory_synthesis, data: data}} ->
        IO.puts("  ✅ Synthesis triggered successfully!")
        IO.puts("  • Trigger: #{data[:topic]}")
        IO.puts("  • Belief count: #{data[:belief_count]}")
        IO.puts("  • CRDT count: #{data[:crdt_count]}")
        
      {:event_bus_hlc, %{type: :memory_synthesis_failed, data: data}} ->
        IO.puts("  ⚠️  Synthesis triggered but failed: #{inspect(data[:reason])}")
        IO.puts("  • This is expected if no LLM API keys are configured")
    after
      5000 ->
        IO.puts("  ❌ Synthesis not triggered within timeout")
        IO.puts("  • Check if synthesis is enabled in config")
    end
  end
  
  defp test_concurrent_synthesis do
    IO.puts("\n🚦 Testing Concurrent Synthesis Limiting")
    IO.puts("-" <> String.duplicate("-", 40))
    
    # Get current state to check active synthesis count
    state = :sys.get_state(CRDTStore)
    IO.puts("  • Current active synthesis tasks: #{state.active_synthesis_count}")
    IO.puts("  • Max concurrent synthesis: #{state.max_concurrent_synthesis}")
    
    # Try to trigger multiple synthesis operations
    IO.puts("\n  • Attempting to trigger multiple concurrent syntheses...")
    
    # First, manually trigger synthesis
    tasks = Enum.map(1..5, fn i ->
      Task.async(fn ->
        IO.puts("  • Requesting synthesis #{i}...")
        result = GenServer.call(CRDTStore, {:synthesize_knowledge, :all})
        {i, result}
      end)
    end)
    
    # Collect results
    results = Enum.map(tasks, fn task ->
      case Task.yield(task, 2000) do
        {:ok, result} -> result
        nil -> 
          Task.shutdown(task)
          {:timeout, nil}
      end
    end)
    
    # Analyze results
    successful = Enum.count(results, fn {_, {:ok, _}} -> true; _ -> false end)
    rate_limited = Enum.count(results, fn 
      {_, {:error, msg}} when is_binary(msg) -> String.contains?(msg, "rate limited")
      _ -> false
    end)
    
    IO.puts("\n  📊 Concurrent synthesis results:")
    IO.puts("  • Successful syntheses: #{successful}")
    IO.puts("  • Rate limited: #{rate_limited}")
    IO.puts("  • Total attempts: #{length(results)}")
    
    if rate_limited > 0 do
      IO.puts("  ✅ Rate limiting is working!")
    end
    
    # Check final state
    final_state = :sys.get_state(CRDTStore)
    IO.puts("\n  • Final active synthesis count: #{final_state.active_synthesis_count}")
  end
end

# Start required processes if not already running
case Process.whereis(AutonomousOpponentV2Core.EventBus) do
  nil ->
    IO.puts("Starting EventBus...")
    AutonomousOpponentV2Core.EventBus.start_link()
  _pid ->
    IO.puts("EventBus already running")
end

case Process.whereis(AutonomousOpponentV2Core.AMCP.Memory.CRDTStore) do
  nil ->
    IO.puts("Starting CRDTStore with synthesis enabled...")
    AutonomousOpponentV2Core.AMCP.Memory.CRDTStore.start_link(synthesis_enabled: true)
  _pid ->
    IO.puts("CRDTStore already running")
end

# Run the tests
CRDTSynthesisLiveTest.run()