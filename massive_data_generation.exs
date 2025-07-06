# Massive data generation to force patterns
alias AutonomousOpponentV2Core.EventBus
alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
alias AutonomousOpponentV2Core.AMCP.Events.{SemanticAnalyzer, SemanticFusion}

IO.puts("\n🌊 GENERATING MASSIVE EVENT STORM 🌊\n")

# Phase 1: Initialize CRDT structures
IO.puts("=== PHASE 1: CRDT INITIALIZATION ===")

# Create multiple CRDT types
for i <- 1..10 do
  name = "knowledge_domain_#{i}"
  CRDTStore.create_crdt(name, :crdt_map, %{
    "initialized_at" => DateTime.utc_now(),
    "domain_type" => Enum.random(["technical", "philosophical", "operational"]),
    "priority" => Enum.random(1..5)
  })
end

# Create counters
for i <- 1..5 do
  CRDTStore.create_crdt("metric_counter_#{i}", :pn_counter, 0)
end

IO.puts("✓ Created 15 CRDT structures\n")

# Phase 2: Generate thousands of events
IO.puts("=== PHASE 2: MASSIVE EVENT GENERATION ===")

# Generate 1000 events rapidly
for i <- 1..1000 do
  # Varied event types
  event_type = Enum.random([
    :user_interaction,
    :system_performance,
    :pattern_detected,
    :consciousness_update,
    :vsm_state_change,
    :semantic_insight,
    :memory_update
  ])
  
  event_data = case event_type do
    :user_interaction -> %{
      type: :chat_message,
      user_id: "user_#{rem(i, 20) + 1}",
      message: "Interaction #{i} about #{Enum.random(["consciousness", "AI", "systems", "patterns"])}",
      sentiment: Enum.random([:positive, :neutral, :negative]),
      timestamp: DateTime.utc_now()
    }
    
    :pattern_detected -> %{
      pattern_type: Enum.random([:behavioral, :temporal, :semantic, :emergent]),
      confidence: 0.6 + :rand.uniform() * 0.4,
      pattern_id: "pattern_#{i}",
      description: "Pattern #{i} detected in #{Enum.random(["user behavior", "system metrics", "data flow"])}",
      timestamp: DateTime.utc_now()
    }
    
    :consciousness_update -> %{
      awareness_level: 0.5 + :rand.uniform() * 0.5,
      state: Enum.random([:awakening, :reflecting, :processing, :dreaming]),
      insight: "Consciousness insight #{i}",
      timestamp: DateTime.utc_now()
    }
    
    _ -> %{
      metric: Enum.random([:cpu, :memory, :latency, :throughput]),
      value: :rand.uniform() * 100,
      node: "node_#{rem(i, 5) + 1}",
      timestamp: DateTime.utc_now()
    }
  end
  
  EventBus.publish(event_type, event_data)
  
  # Update CRDT counters
  if rem(i, 10) == 0 do
    counter = "metric_counter_#{rem(div(i, 10), 5) + 1}"
    CRDTStore.update_crdt(counter, :increment, Enum.random(1..5))
  end
  
  # Brief pause to prevent overwhelming
  if rem(i, 100) == 0 do
    IO.puts("Generated #{i} events...")
    Process.sleep(100)
  end
end

IO.puts("✓ Generated 1000 events\n")

# Phase 3: Force semantic analysis multiple times
IO.puts("=== PHASE 3: FORCING SEMANTIC ANALYSIS ===")

# Trigger analysis multiple times
for i <- 1..5 do
  IO.puts("Triggering analysis batch #{i}...")
  Process.whereis(SemanticAnalyzer) |> send(:perform_batch_analysis)
  Process.sleep(1000)
end

IO.puts("\n✓ Analysis triggered 5 times\n")

# Phase 4: Generate specific patterns
IO.puts("=== PHASE 4: GENERATING SPECIFIC PATTERNS ===")

# Create repetitive patterns to ensure detection
pattern_types = ["login_sequence", "data_access", "computation_burst", "memory_spike"]

for pattern_type <- pattern_types do
  for i <- 1..20 do
    EventBus.publish(:pattern_detected, %{
      pattern_type: :behavioral,
      pattern_name: pattern_type,
      confidence: 0.85 + :rand.uniform() * 0.15,
      pattern_id: "#{pattern_type}_#{i}",
      description: "Detected #{pattern_type} pattern instance #{i}",
      timestamp: DateTime.add(DateTime.utc_now(), -60 + i * 3, :second)
    })
  end
end

IO.puts("✓ Generated 80 specific pattern instances\n")

# Phase 5: Final verification
IO.puts("=== PHASE 5: VERIFICATION ===")
Process.sleep(3000)

# Check results
{:ok, insights} = SemanticAnalyzer.get_semantic_insights(600)
IO.puts("Semantic Insights: #{length(insights)} analyzed")

{:ok, patterns} = SemanticFusion.get_patterns(600)
IO.puts("Patterns: #{length(patterns)} detected")

{:ok, topics} = SemanticAnalyzer.get_trending_topics()
IO.puts("Trending Topics: #{length(topics)} identified")

{:ok, crdts} = CRDTStore.list_crdts()
IO.puts("CRDT Entries: #{length(crdts)} total")

# Sample a CRDT counter
case CRDTStore.get_crdt("metric_counter_1") do
  {:ok, value} -> IO.puts("Sample Counter Value: #{inspect(value)}")
  _ -> :ok
end

IO.puts("\n🎉 MASSIVE DATA GENERATION COMPLETE\! 🎉")
