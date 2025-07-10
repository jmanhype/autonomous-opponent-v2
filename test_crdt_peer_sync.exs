#!/usr/bin/env elixir

# Test script for CRDT peer synchronization
# Run with: mix run test_crdt_peer_sync.exs

require Logger

alias AutonomousOpponentV2Core.AMCP.Memory.{CRDTStore, CRDTSyncMonitor}
alias AutonomousOpponentV2Core.EventBus

defmodule CRDTPeerSyncTest do
  def run do
    Logger.info("Starting CRDT Peer Sync Test...")
    
    # 1. Check initial health
    IO.puts("\n1. Checking initial health status:")
    health = CRDTSyncMonitor.health_status()
    IO.inspect(health, label: "Health Status")
    
    # 2. Enable sync with safety checks
    IO.puts("\n2. Enabling CRDT peer sync:")
    case CRDTSyncMonitor.enable_sync() do
      :ok ->
        IO.puts("✓ Peer sync enabled successfully")
      {:error, reason} ->
        IO.puts("✗ Failed to enable sync: #{inspect(reason)}")
        System.halt(1)
    end
    
    # 3. Discover peers
    IO.puts("\n3. Initiating peer discovery:")
    CRDTStore.discover_peers()
    Process.sleep(100)
    
    # 4. Check stats
    IO.puts("\n4. Checking CRDT store stats:")
    stats = CRDTStore.get_stats()
    IO.inspect(stats, label: "Store Stats")
    
    # 5. Create test CRDTs
    IO.puts("\n5. Creating test CRDTs:")
    
    # Create a belief set
    :ok = CRDTStore.create_belief_set("test_agent")
    :ok = CRDTStore.add_belief("test_agent", "test_belief_1")
    :ok = CRDTStore.add_belief("test_agent", "test_belief_2")
    IO.puts("✓ Created belief set with 2 beliefs")
    
    # Create a context graph
    :ok = CRDTStore.create_context_graph("test_context")
    :ok = CRDTStore.add_context_relationship("test_context", "concept_a", "concept_b", "relates_to")
    IO.puts("✓ Created context graph with relationship")
    
    # Create a metric counter
    :ok = CRDTStore.create_metric_counter("test_metric")
    :ok = CRDTStore.increment_metric("test_metric", 5)
    IO.puts("✓ Created metric counter with value 5")
    
    # 6. List all CRDTs
    IO.puts("\n6. Listing all CRDTs:")
    crdts = CRDTStore.list_crdts()
    Enum.each(crdts, fn crdt ->
      IO.puts("  - #{crdt.id} (#{crdt.type}): #{inspect(crdt.value, limit: 3)}")
    end)
    
    # 7. Force sync
    IO.puts("\n7. Forcing peer sync:")
    CRDTStore.sync_with_peers()
    Process.sleep(100)
    
    # 8. Check sync metrics
    IO.puts("\n8. Checking sync metrics:")
    metrics = CRDTSyncMonitor.metrics()
    IO.inspect(metrics, label: "Sync Metrics")
    
    # 9. Perform test sync
    IO.puts("\n9. Running sync test:")
    case CRDTSyncMonitor.test_sync() do
      {:ok, result} ->
        IO.puts("✓ Test sync successful")
        IO.inspect(result, label: "Test Result")
      {:error, error} ->
        IO.puts("✗ Test sync failed: #{inspect(error)}")
    end
    
    # 10. Final health check
    IO.puts("\n10. Final health check:")
    final_health = CRDTSyncMonitor.health_status()
    IO.inspect(final_health, label: "Final Health")
    
    # Summary
    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("CRDT Peer Sync Test Summary:")
    IO.puts("- CRDTs created: #{length(crdts)}")
    IO.puts("- Sync requests: #{metrics.sync_requests}")
    IO.puts("- Sync responses: #{metrics.sync_responses}")
    IO.puts("- Peer count: #{metrics.peer_count}")
    IO.puts("- Health status: #{final_health.health}")
    IO.puts(String.duplicate("=", 50))
    
    if metrics.peer_count == 0 do
      IO.puts("\nNote: No peers discovered. This is expected in a single-node setup.")
      IO.puts("To test actual peer sync, run multiple nodes with:")
      IO.puts("  iex --sname node1 -S mix")
      IO.puts("  iex --sname node2 -S mix")
    end
  rescue
    error ->
      Logger.error("Test failed: #{Exception.format(:error, error)}")
      IO.puts("\n✗ Test failed with error: #{inspect(error)}")
      System.halt(1)
  end
end

# Run the test
CRDTPeerSyncTest.run()