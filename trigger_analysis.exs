# Trigger semantic analysis manually
sa_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer)

if sa_pid do
  IO.puts("Triggering batch analysis on SemanticAnalyzer...")
  send(sa_pid, :perform_batch_analysis)
  
  # Wait for processing
  Process.sleep(5000)
  
  # Check state
  state = :sys.get_state(sa_pid)
  IO.puts("\nSemanticAnalyzer state after trigger:")
  IO.puts("  Buffer size: #{:queue.len(state.event_buffer)}")
  IO.puts("  Analysis cache size: #{map_size(state.analysis_cache)}")
  IO.puts("  Trending topics: #{map_size(state.semantic_trends)}")
else
  IO.puts("SemanticAnalyzer not found!")
end

# Check SemanticFusion too
sf_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticFusion)
if sf_pid do
  state = :sys.get_state(sf_pid)
  IO.puts("\nSemanticFusion state:")
  IO.puts("  Patterns: #{map_size(state.patterns)}")
  IO.puts("  Event buffer: #{length(state.event_buffer)}")
end