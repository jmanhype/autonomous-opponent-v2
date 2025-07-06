# Trace a single event through the system
require Logger

IO.puts("🔍 TRACING SINGLE EVENT THROUGH FIXED SYSTEM\n")

# Check SemanticAnalyzer
sa_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer)
if sa_pid && Process.alive?(sa_pid) do
  IO.puts("✅ SemanticAnalyzer is running at #{inspect(sa_pid)}")
  
  # Get initial state
  state = :sys.get_state(sa_pid)
  initial_buffer = :queue.len(state.event_buffer)
  IO.puts("   Initial buffer size: #{initial_buffer}")
  
  # Publish ONE event
  IO.puts("\n📡 Publishing single test event...")
  AutonomousOpponentV2Core.EventBus.publish(:user_interaction, %{
    type: :trace_test,
    message: "Testing fixed event flow",
    timestamp: DateTime.utc_now()
  })
  
  # Wait a moment
  Process.sleep(100)
  
  # Check buffer again
  state = :sys.get_state(sa_pid)
  new_buffer = :queue.len(state.event_buffer)
  IO.puts("   Buffer size after event: #{new_buffer}")
  
  if new_buffer > initial_buffer do
    IO.puts("\n✅ SUCCESS! Event was added to buffer!")
    IO.puts("   Buffer increased from #{initial_buffer} to #{new_buffer}")
    
    # Look at the buffered event
    events = :queue.to_list(state.event_buffer)
    latest = List.last(events)
    IO.puts("\n📦 Latest buffered event:")
    IO.inspect(latest, pretty: true, limit: :infinity)
  else
    IO.puts("\n❌ Event was NOT added to buffer")
  end
else
  IO.puts("❌ SemanticAnalyzer is not running!")
end

# Also check SemanticFusion
IO.puts("\n" <> String.duplicate("-", 50))
sf_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticFusion)
if sf_pid && Process.alive?(sf_pid) do
  IO.puts("✅ SemanticFusion is running at #{inspect(sf_pid)}")
  
  state = :sys.get_state(sf_pid)
  buffer_size = length(:queue.to_list(state.event_buffer))
  IO.puts("   Event buffer size: #{buffer_size}")
  IO.puts("   Events received: #{state.fusion_stats.events_received}")
end