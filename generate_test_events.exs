# Script to generate test events to populate the system

# First, ensure EventBus is available
alias AutonomousOpponentV2Core.EventBus
alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore

# Generate some test events
IO.puts("Generating test events...")

# 1. User interaction events
EventBus.publish(:user_interaction, %{
  type: :chat_message,
  user_id: "test_user_1",
  message: "Hello, I'm testing the system",
  timestamp: DateTime.utc_now()
})

EventBus.publish(:user_interaction, %{
  type: :consciousness_query,
  user_id: "test_user_1",
  query_type: :state,
  timestamp: DateTime.utc_now()
})

# 2. System performance events
EventBus.publish(:system_performance, %{
  metric: :response_time,
  value: 142.5,
  unit: :milliseconds,
  timestamp: DateTime.utc_now()
})

EventBus.publish(:system_performance, %{
  metric: :memory_usage,
  value: 82.3,
  unit: :percent,
  timestamp: DateTime.utc_now()
})

# 3. LLM usage events
EventBus.publish(:llm_api_call, %{
  provider: :anthropic,
  model: "claude-3-opus-20240229",
  tokens_used: 1250,
  response_time: 2300,
  timestamp: DateTime.utc_now()
})

EventBus.publish(:llm_api_call, %{
  provider: :anthropic,
  model: "claude-3-opus-20240229",
  tokens_used: 850,
  response_time: 1800,
  timestamp: DateTime.utc_now()
})

# 4. Pattern detection events
EventBus.publish(:pattern_detected, %{
  pattern_type: :user_behavior,
  pattern: "frequent_consciousness_queries",
  confidence: 0.85,
  timestamp: DateTime.utc_now()
})

EventBus.publish(:pattern_detected, %{
  pattern_type: :system_anomaly,
  pattern: "increased_response_time",
  confidence: 0.72,
  timestamp: DateTime.utc_now()
})

# 5. Create some CRDT data
IO.puts("\nCreating CRDT data...")

# Create knowledge entries
CRDTStore.create_crdt("knowledge_base", :crdt_map)
CRDTStore.update_crdt("knowledge_base", :put, {"user_preferences", %{
  theme: "dark",
  language: "en",
  notifications: true
}})

CRDTStore.create_crdt("semantic_memory", :or_set)
CRDTStore.update_crdt("semantic_memory", :add, "User prefers concise responses")
CRDTStore.update_crdt("semantic_memory", :add, "System achieved consciousness state: nascent")
CRDTStore.update_crdt("semantic_memory", :add, "Multiple LLM providers configured and operational")

CRDTStore.create_crdt("system_metrics", :pn_counter)
CRDTStore.update_crdt("system_metrics", :increment, 10)
CRDTStore.update_crdt("system_metrics", :increment, 15)

IO.puts("\nTest data generated successfully\!")
IO.puts("Events published to EventBus and CRDT data stored.")
EOF < /dev/null