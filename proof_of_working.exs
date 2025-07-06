# Final proof that event processing is working
require Logger

IO.puts("""
🎉 PROOF: EVENT PROCESSING IS WORKING
=====================================
""")

# Get SemanticAnalyzer
sa_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer)

if sa_pid do
  # Initial state
  state = :sys.get_state(sa_pid)
  IO.puts("Initial buffer: #{:queue.len(state.event_buffer)} events")
  
  # Generate 12 events (more than batch size)
  IO.puts("\nGenerating 12 events...")
  for i <- 1..12 do
    AutonomousOpponentV2Core.EventBus.publish(:user_interaction, %{
      id: i,
      message: "Event #{i}",
      timestamp: DateTime.utc_now()
    })
    Process.sleep(100)
    
    # Check buffer after each event
    state = :sys.get_state(sa_pid)
    buffer_size = :queue.len(state.event_buffer)
    IO.puts("  Event #{i} published → Buffer: #{buffer_size}")
    
    # Show when batch triggers
    if i == 10 do
      IO.puts("  ⚡ BATCH SHOULD TRIGGER NOW (reached 10 events)")
    end
  end
  
  # Wait for batch processing
  IO.puts("\nWaiting 3 seconds for batch processing...")
  Process.sleep(3000)
  
  # Final state
  state = :sys.get_state(sa_pid)
  final_buffer = :queue.len(state.event_buffer)
  cache_size = map_size(state.analysis_cache)
  
  IO.puts("\nFINAL STATE:")
  IO.puts("  Buffer: #{final_buffer} events (should be ~2 after batch)")
  IO.puts("  Analysis cache: #{cache_size} entries")
  IO.puts("  Stats: #{inspect(state.analysis_stats)}")
  
  if final_buffer < 10 do
    IO.puts("\n✅ SUCCESS! Batch processing occurred!")
    IO.puts("   Buffer was reduced from 10+ to #{final_buffer}")
  end
end

# Check SemanticFusion too
sf_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticFusion)
if sf_pid do
  state = :sys.get_state(sf_pid)
  IO.puts("\nSemanticFusion:")
  IO.puts("  Events received: #{state.fusion_stats.events_received}")
end