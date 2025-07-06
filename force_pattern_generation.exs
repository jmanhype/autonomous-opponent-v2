# MAXIMUM EFFORT - Force all systems to generate data
require Logger

alias AutonomousOpponentV2Core.EventBus
alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
alias AutonomousOpponentV2Core.AMCP.Events.{SemanticAnalyzer, SemanticFusion}

IO.puts("\n🔥 MAXIMUM EFFORT MODE ACTIVATED 🔥\n")

# Phase 1: Directly call SemanticFusion to create patterns
IO.puts("=== PHASE 1: DIRECT PATTERN INJECTION ===")

# Create patterns directly in SemanticFusion
for i <- 1..50 do
  pattern = %{
    id: "forced_pattern_#{i}",
    type: Enum.random([:behavioral, :temporal, :semantic, :emergent]),
    confidence: 0.7 + :rand.uniform() * 0.3,
    description: "Force-generated pattern #{i} showing #{Enum.random(["user behavior", "system anomaly", "data flow", "consciousness emergence"])}",
    timestamp: DateTime.utc_now(),
    event_count: Enum.random(10..100),
    causal_chain: ["event_#{i}_1", "event_#{i}_2", "event_#{i}_3"]
  }
  
  # Try to directly add to SemanticFusion
  SemanticFusion.fuse_event(:pattern_detected, pattern)
end

IO.puts("✓ Injected 50 patterns directly\n")

# Phase 2: Generate specific event patterns that SemanticAnalyzer expects
IO.puts("=== PHASE 2: SEMANTIC ANALYZER SPECIFIC EVENTS ===")

# Generate events in the exact format SemanticAnalyzer processes
for i <- 1..200 do
  # Create events that match what SemanticAnalyzer expects
  event_data = %{
    name: Enum.random([:user_interaction, :system_event, :pattern_detected]),
    data: %{
      type: Enum.random([:chat_message, :system_metric, :behavioral_pattern]),
      user_id: "force_user_#{rem(i, 10)}",
      value: :rand.uniform() * 100,
      message: "Force event #{i} for pattern generation",
      timestamp: DateTime.utc_now()
    },
    timestamp: DateTime.utc_now(),
    id: "force_event_#{i}"
  }
  
  # Publish through EventBus
  EventBus.publish(:all, event_data)
  
  # Also try direct semantic analysis
  SemanticAnalyzer.analyze_event(event_data.name, event_data.data)
end

IO.puts("✓ Generated 200 semantic events\n")

# Phase 3: Force batch processing multiple times
IO.puts("=== PHASE 3: FORCING BATCH PROCESSING ===")

# Get process PIDs
analyzer_pid = Process.whereis(SemanticAnalyzer)
fusion_pid = Process.whereis(SemanticFusion)

# Force SemanticAnalyzer to process
if analyzer_pid do
  for _ <- 1..10 do
    send(analyzer_pid, :perform_batch_analysis)
    Process.sleep(100)
  end
  IO.puts("✓ Forced 10 batch analyses")
end

# Force SemanticFusion to process
if fusion_pid do
  for _ <- 1..10 do
    send(fusion_pid, :process_fusion)
    Process.sleep(100)
  end
  IO.puts("✓ Forced 10 fusion processes")
end

# Phase 4: Create trending topics by repetition
IO.puts("\n=== PHASE 4: CREATING TRENDING TOPICS ===")

trending_topics = ["consciousness", "emergence", "pattern", "cybernetic", "AI"]

for topic <- trending_topics do
  for i <- 1..50 do
    EventBus.publish(:trending_topic, %{
      topic: topic,
      frequency: i,
      context: "Force generating #{topic} trend",
      timestamp: DateTime.add(DateTime.utc_now(), -300 + i * 6, :second)
    })
  end
end

IO.puts("✓ Created 5 trending topics with 50 mentions each\n")

# Phase 5: Update CRDT with massive data
IO.puts("=== PHASE 5: CRDT MASSIVE UPDATE ===")

# Ensure CRDTs exist
for name <- ["pattern_counts", "event_metrics", "topic_frequencies"] do
  CRDTStore.create_crdt(name, :pn_counter, 0)
end

# Update counters massively
for i <- 1..500 do
  counter = Enum.random(["pattern_counts", "event_metrics", "topic_frequencies"])
  CRDTStore.update_crdt(counter, :increment, Enum.random(1..10))
end

IO.puts("✓ Updated CRDT counters 500 times\n")

# Phase 6: Wait and verify
IO.puts("=== PHASE 6: VERIFICATION ===")
Process.sleep(5000)

# Check SemanticAnalyzer state
if analyzer_pid do
  state = :sys.get_state(analyzer_pid)
  cache_size = map_size(state.analysis_cache)
  trends_size = map_size(state.semantic_trends)
  IO.puts("SemanticAnalyzer - Cache: #{cache_size} items, Trends: #{trends_size} topics")
end

# Check SemanticFusion state
if fusion_pid do
  state = :sys.get_state(fusion_pid)
  patterns_size = length(state.pattern_cache)
  IO.puts("SemanticFusion - Patterns: #{patterns_size} cached")
end

# Final API checks
{:ok, patterns} = SemanticFusion.get_patterns(600)
{:ok, insights} = SemanticAnalyzer.get_semantic_insights(600)
{:ok, topics} = SemanticAnalyzer.get_trending_topics()

IO.puts("\n🎯 FINAL RESULTS:")
IO.puts("- Patterns detected: #{length(patterns)}")
IO.puts("- Semantic insights: #{length(insights)}")
IO.puts("- Trending topics: #{length(topics)}")

IO.puts("\n🔥 MAXIMUM EFFORT COMPLETE\! 🔥")
