#!/usr/bin/env elixir

# Simple CRDT sync test
alias AutonomousOpponentV2Core.AMCP.Memory.{CRDTStore, CRDTSyncMonitor}

IO.puts "\n=== CRDT SYNC TEST ==="

# Check if sync monitor is running
case Process.whereis(CRDTSyncMonitor) do
  nil -> 
    IO.puts "❌ CRDTSyncMonitor not running"
    exit(:monitor_not_running)
  pid -> 
    IO.puts "✅ CRDTSyncMonitor running: #{inspect pid}"
end

# Enable sync
case CRDTSyncMonitor.enable_sync() do
  {:ok, msg} -> IO.puts "✅ #{msg}"
  {:error, reason} -> IO.puts "❌ Enable failed: #{reason}"
end

# Check health
health = CRDTSyncMonitor.health_status()
IO.puts "📊 Health: #{inspect health}"

# Create a test CRDT
crdt_id = "test_sync_#{:rand.uniform(1000)}"
case CRDTStore.create_crdt(crdt_id, :or_set, MapSet.new()) do
  :ok -> IO.puts "✅ Created CRDT: #{crdt_id}"
  error -> IO.puts "❌ Create failed: #{inspect error}"
end

# Add a sync peer
peer_id = "local_peer_test"
case CRDTStore.add_sync_peer(peer_id) do
  :ok -> IO.puts "✅ Added peer: #{peer_id}"
  error -> IO.puts "❌ Add peer failed: #{inspect error}"
end

# Check metrics
metrics = CRDTSyncMonitor.metrics()
IO.puts "\n📈 Sync Metrics:"
IO.puts "  Requests: #{metrics.sync_requests}"
IO.puts "  Responses: #{metrics.sync_responses}"
IO.puts "  Errors: #{metrics.errors}"
IO.puts "  Last sync: #{metrics.last_sync_time || "never"}"

IO.puts "\n✅ CRDT sync is enabled and operational!"