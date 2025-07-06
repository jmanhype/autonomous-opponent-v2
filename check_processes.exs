# Check if analyzer processes are running
IO.puts("\n🔍 Checking Analyzer Processes:\n")

# Check SemanticAnalyzer
sa_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer)
IO.puts("SemanticAnalyzer PID: #{inspect(sa_pid)}")

# Check SemanticFusion  
sf_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticFusion)
IO.puts("SemanticFusion PID: #{inspect(sf_pid)}")

# Check EventBus
eb_pid = Process.whereis(AutonomousOpponentV2Core.EventBus)
IO.puts("EventBus PID: #{inspect(eb_pid)}")

# Check subscriptions
if eb_pid do
  state = :sys.get_state(eb_pid)
  IO.puts("\nEventBus subscribers:")
  Enum.each(state.subscriptions, fn {event, subs} ->
    IO.puts("  #{event}: #{length(subs)} subscribers")
  end)
end

# Generate a test event
IO.puts("\n📡 Publishing test event...")
AutonomousOpponentV2Core.EventBus.publish(:user_interaction, %{
  type: :test,
  message: "Direct test event",
  timestamp: DateTime.utc_now()
})

# Wait and check analyzer states
Process.sleep(1000)

if sa_pid do
  state = :sys.get_state(sa_pid)
  buffer_size = :queue.len(state.event_buffer)
  IO.puts("\nSemanticAnalyzer buffer size: #{buffer_size}")
  IO.puts("Analysis cache size: #{map_size(state.analysis_cache)}")
  IO.puts("Trending topics: #{map_size(state.semantic_trends)}")
end

if sf_pid do
  state = :sys.get_state(sf_pid)
  IO.puts("\nSemanticFusion patterns: #{map_size(state.patterns)}")
  IO.puts("Event buffer size: #{length(state.event_buffer)}")
end
