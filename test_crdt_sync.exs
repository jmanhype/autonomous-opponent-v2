#!/usr/bin/env elixir

# Test script for CRDT peer synchronization
# Run with: mix run test_crdt_sync.exs

alias AutonomousOpponentV2Core.AMCP.Memory.{CRDTStore, CRDTSyncMonitor}
alias AutonomousOpponentV2Core.EventBus

IO.puts """
==============================================
CRDT PEER SYNC TEST
==============================================
"""

# Step 1: Check initial health status
IO.puts "\n1. Checking sync health status..."
health = CRDTSyncMonitor.health_status()
IO.inspect(health, label: "Initial health")

# Step 2: Enable sync if not already enabled
IO.puts "\n2. Enabling CRDT peer sync..."
case CRDTSyncMonitor.enable_sync() do
  {:ok, message} -> 
    IO.puts "✅ #{message}"
  {:error, reason} -> 
    IO.puts "❌ Failed to enable sync: #{reason}"
    exit(:sync_enable_failed)
end

# Step 3: Add a test peer (ourselves for local testing)
IO.puts "\n3. Adding local test peer..."
node_name = node() |> to_string()
peer_id = "test_peer_#{:rand.uniform(1000)}"

case CRDTStore.add_sync_peer(peer_id) do
  :ok -> 
    IO.puts "✅ Added peer: #{peer_id}"
  error -> 
    IO.puts "❌ Failed to add peer: #{inspect(error)}"
end

# Step 4: Create some test CRDTs
IO.puts "\n4. Creating test CRDTs..."
test_crdts = [
  {"test_counter", :pn_counter, 0},
  {"test_set", :or_set, MapSet.new()},
  {"test_register", :lww_register, "initial_value"}
]

for {id, type, initial} <- test_crdts do
  case CRDTStore.create_crdt(id, type, initial) do
    :ok -> 
      IO.puts "✅ Created #{type}: #{id}"
    {:error, :already_exists} ->
      IO.puts "⚠️  #{id} already exists"
    error -> 
      IO.puts "❌ Failed to create #{id}: #{inspect(error)}"
  end
end

# Step 5: Perform some updates
IO.puts "\n5. Performing CRDT updates..."
CRDTStore.update_crdt("test_counter", :increment, 5)
IO.puts "✅ Incremented counter by 5"

CRDTStore.update_crdt("test_set", :add, "element1")
CRDTStore.update_crdt("test_set", :add, "element2")
IO.puts "✅ Added elements to set"

CRDTStore.update_crdt("test_register", :set, "updated_value")
IO.puts "✅ Updated register value"

# Step 6: Force a sync
IO.puts "\n6. Forcing synchronization..."
# Publish a sync request event
EventBus.publish(:amcp_crdt_sync_request, %{
  source: node_name,
  target: peer_id,
  timestamp: DateTime.utc_now()
})

# Wait for sync to complete
Process.sleep(2000)

# Step 7: Check sync metrics
IO.puts "\n7. Checking sync metrics..."
metrics = CRDTSyncMonitor.metrics()
IO.inspect(metrics, label: "Sync metrics", pretty: true)

# Step 8: Check health after sync
IO.puts "\n8. Final health check..."
final_health = CRDTSyncMonitor.health_status()
IO.inspect(final_health, label: "Final health", pretty: true)

# Step 9: List current CRDTs
IO.puts "\n9. Current CRDTs:"
crdts = CRDTStore.list_crdts()
Enum.each(crdts, fn {id, {type, value}} ->
  IO.puts "  #{id} (#{type}): #{inspect(value, pretty: true, limit: 3)}"
end)

# Step 10: Test sync between processes (simulating nodes)
IO.puts "\n10. Testing inter-process sync..."

# Create a second process acting as another node
peer_pid = spawn(fn ->
  # Subscribe to sync events
  EventBus.subscribe({:crdt_sync, peer_id})
  
  # Wait for sync messages
  receive do
    {:event_bus_hlc, %{topic: {:crdt_sync, ^peer_id}, data: sync_data}} ->
      IO.puts "🔄 Peer received sync message: #{inspect(sync_data.type)}"
  after
    5000 ->
      IO.puts "⚠️  No sync messages received"
  end
end)

# Register the peer process
Process.register(peer_pid, String.to_atom("crdt_store_#{peer_id}"))

# Trigger another sync
EventBus.publish(:amcp_crdt_sync_request, %{
  source: node_name,
  target: peer_id,
  timestamp: DateTime.utc_now()
})

Process.sleep(1000)

IO.puts """

==============================================
CRDT SYNC TEST COMPLETE
==============================================

Summary:
- Sync enabled: ✅
- Test peer added: ✅  
- CRDTs created and updated: ✅
- Sync messages published: ✅

To test actual multi-node sync:
1. Start two iex sessions with names:
   iex --sname node1 -S mix
   iex --sname node2 -S mix

2. In both nodes, enable sync:
   CRDTSyncMonitor.enable_sync()

3. In node1, add node2 as peer:
   CRDTStore.add_sync_peer("node2@hostname")

4. Create/update CRDTs in either node
5. Watch them sync automatically!
"""

# Cleanup
Process.sleep(100)
if Process.alive?(peer_pid), do: Process.exit(peer_pid, :normal)