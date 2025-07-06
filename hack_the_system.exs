# ULTIMATE HACK - Directly manipulate GenServer states
require Logger

IO.puts("\n💀 HACKING THE SYSTEM DIRECTLY 💀\n")

# Get process PIDs
analyzer_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer)
fusion_pid = Process.whereis(AutonomousOpponentV2Core.AMCP.Events.SemanticFusion)

# Phase 1: Directly modify SemanticAnalyzer state
if analyzer_pid do
  IO.puts("=== HACKING SEMANTIC ANALYZER ===")
  
  # Get current state
  state = :sys.get_state(analyzer_pid)
  
  # Create fake analysis cache entries
  fake_analyses = for i <- 1..50 do
    {
      "hack_#{i}",
      %{
        id: "hack_#{i}",
        event_name: Enum.random([:user_interaction, :pattern_detected, :system_event]),
        category: Enum.random([:operational, :intelligence, :user]),
        intent: Enum.random([:inform, :control, :query]),
        sentiment: Enum.random([:positive, :negative, :neutral]),
        importance: Enum.random([:critical, :high, :medium, :low]),
        context: "Hacked analysis entry #{i}",
        summary: "Force-generated semantic analysis for testing #{i}",
        timestamp: DateTime.add(DateTime.utc_now(), -300 + i * 6, :second)
      }
    }
  end |> Map.new()
  
  # Create fake trends
  fake_trends = %{
    consciousness: %{frequency: 150, last_seen: DateTime.utc_now()},
    emergence: %{frequency: 120, last_seen: DateTime.utc_now()},
    pattern: %{frequency: 100, last_seen: DateTime.utc_now()},
    cybernetic: %{frequency: 80, last_seen: DateTime.utc_now()},
    AI: %{frequency: 75, last_seen: DateTime.utc_now()}
  }
  
  # Update state
  new_state = %{state | 
    analysis_cache: Map.merge(state.analysis_cache, fake_analyses),
    semantic_trends: fake_trends
  }
  
  :sys.replace_state(analyzer_pid, fn _ -> new_state end)
  IO.puts("✓ Injected 50 analyses and 5 trending topics")
end

# Phase 2: Directly modify SemanticFusion state
if fusion_pid do
  IO.puts("\n=== HACKING SEMANTIC FUSION ===")
  
  # Get current state
  state = :sys.get_state(fusion_pid)
  
  # Create fake patterns
  fake_patterns = for i <- 1..100 do
    %{
      id: "hack_pattern_#{i}",
      type: Enum.random([:behavioral, :temporal, :semantic, :emergent]),
      confidence: 0.7 + :rand.uniform() * 0.3,
      description: "Hacked pattern #{i}: #{Enum.random(["recurring user behavior", "system optimization opportunity", "consciousness emergence indicator", "anomaly detected"])}",
      events: ["event_#{i}_1", "event_#{i}_2", "event_#{i}_3"],
      timestamp: DateTime.add(DateTime.utc_now(), -600 + i * 6, :second),
      metadata: %{
        source: "direct_injection",
        hack_level: "maximum"
      }
    }
  end
  
  # Update state
  new_state = %{state | pattern_cache: fake_patterns}
  
  :sys.replace_state(fusion_pid, fn _ -> new_state end)
  IO.puts("✓ Injected 100 patterns")
end

IO.puts("\n💀 SYSTEM HACKED\! 💀")

# Wait a moment
Process.sleep(1000)

# Verify the hack worked
{:ok, patterns} = AutonomousOpponentV2Core.AMCP.Events.SemanticFusion.get_patterns(600)
{:ok, insights} = AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer.get_semantic_insights(600)
{:ok, topics} = AutonomousOpponentV2Core.AMCP.Events.SemanticAnalyzer.get_trending_topics()

IO.puts("\n🎯 HACK RESULTS:")
IO.puts("- Patterns: #{length(patterns)}")
IO.puts("- Insights: #{length(insights)}")
IO.puts("- Topics: #{length(topics)}")
