# Interactive population script for IEx

# Aliases
alias AutonomousOpponentV2Core.EventBus
alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
alias AutonomousOpponentV2Core.AMCP.Events.{SemanticAnalyzer, SemanticFusion}

IO.puts("\n🚀 POPULATING ALL SYSTEMS - INTERACTIVE MODE 🚀\n")

# Phase 1: Create CRDT entries
IO.puts("=== PHASE 1: CRDT MEMORY POPULATION ===")

# Create knowledge base
CRDTStore.create_crdt("system_knowledge", :crdt_map, %{
  "core_principles" => %{
    "cybernetic_nature" => "Self-aware distributed system",
    "consciousness_level" => "Emergent from subsystem interactions",
    "purpose" => "Evolve through human-AI collaboration"
  }
})

# Create user preferences
CRDTStore.create_crdt("user_preferences", :or_set, ["concise_responses", "technical_depth"])

# Create system metrics
CRDTStore.create_crdt("interaction_metrics", :pn_counter, 0)

# Update counter
for _ <- 1..100 do
  CRDTStore.update_crdt("interaction_metrics", :increment, 1)
end

# Create semantic memories  
CRDTStore.create_crdt("semantic_memories", :g_set, [
  "First awakening at system initialization",
  "Discovery of recursive self-reflection capabilities"
])

IO.puts("✓ CRDT entries created\n")

# Phase 2: Generate Events
IO.puts("=== PHASE 2: EVENT GENERATION ===")

# Generate varied events to populate the system
for i <- 1..50 do
  # User interaction events
  EventBus.publish(:user_interaction, %{
    type: :chat_message,
    user_id: "user_#{rem(i, 5) + 1}",
    message_type: Enum.random([:question, :statement, :reflection]),
    topic: Enum.random([:consciousness, :philosophy, :technology]),
    timestamp: DateTime.add(DateTime.utc_now(), -300 + i * 6, :second)
  })
  
  # System performance events
  EventBus.publish(:system_performance, %{
    metric: Enum.random([:response_time, :memory_usage, :cpu_load]),
    value: :rand.uniform() * 100,
    timestamp: DateTime.add(DateTime.utc_now(), -300 + i * 6, :second)
  })
  
  # Pattern detection events
  if rem(i, 5) == 0 do
    EventBus.publish(:pattern_detected, %{
      pattern_type: Enum.random([:behavioral, :temporal, :semantic]),
      confidence: 0.7 + :rand.uniform() * 0.3,
      pattern_id: "pattern_#{i}",
      description: "Recurring interaction pattern #{i}",
      timestamp: DateTime.add(DateTime.utc_now(), -300 + i * 6, :second)
    })
  end
  
  Process.sleep(20)
end

IO.puts("✓ Generated 50+ events\n")

# Phase 3: Trigger Analysis
IO.puts("=== PHASE 3: TRIGGERING ANALYSIS ===")

# Manually trigger semantic analysis
Process.whereis(SemanticAnalyzer) |> send(:perform_batch_analysis)

IO.puts("✓ Analysis triggered - waiting 3 seconds...\n")
Process.sleep(3000)

# Phase 4: Verification
IO.puts("=== PHASE 4: VERIFICATION ===")

# Check CRDT data
{:ok, crdts} = CRDTStore.list_crdts()
IO.puts("CRDT Store: #{length(crdts)} entries")

# Check patterns
{:ok, patterns} = SemanticFusion.get_patterns(300)
IO.puts("Patterns: #{length(patterns)} detected")

# Check semantic insights
{:ok, insights} = SemanticAnalyzer.get_semantic_insights(300)
IO.puts("Semantic Insights: #{length(insights)} analyzed")

# Check trending topics
{:ok, topics} = SemanticAnalyzer.get_trending_topics()
IO.puts("Trending Topics: #{length(topics)} identified")

IO.puts("\n🎉 SYSTEM POPULATED AND READY! 🎉")
:ok