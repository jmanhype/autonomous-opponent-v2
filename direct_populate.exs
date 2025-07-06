# Direct population using Elixir script

# Connect to running node
node_name = :"autonomous_opponent@127.0.0.1"
Node.connect(node_name)

# Run code on the remote node
:rpc.call(node_name, :code, :eval_string, ['
  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
  
  IO.puts("Creating CRDT entries...")
  
  # Create entries
  CRDTStore.create_crdt("knowledge_base", :crdt_map, %{
    "system_info" => %{
      "type" => "AI consciousness",
      "version" => "2.0",
      "status" => "operational"
    }
  })
  
  CRDTStore.create_crdt("interaction_count", :pn_counter, 0)
  
  # Update counter many times
  for _ <- 1..200 do
    CRDTStore.update_crdt("interaction_count", :increment, 1)
  end
  
  # Generate events
  IO.puts("Generating events...")
  
  for i <- 1..100 do
    EventBus.publish(:user_interaction, %{
      type: :api_call,
      endpoint: Enum.random(["/chat", "/state", "/reflect"]),
      user_id: "test_user_#{rem(i, 5)}",
      timestamp: DateTime.utc_now()
    })
    
    if rem(i, 10) == 0 do
      EventBus.publish(:pattern_detected, %{
        pattern_type: :usage_spike,
        confidence: 0.85,
        description: "High frequency API usage pattern",
        timestamp: DateTime.utc_now()
      })
    end
  end
  
  IO.puts("Done\!")
'])
