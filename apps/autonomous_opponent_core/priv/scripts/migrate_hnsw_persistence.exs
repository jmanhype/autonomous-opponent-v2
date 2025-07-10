#!/usr/bin/env elixir

# Migration script for enabling HNSW persistence
# Run with: mix run priv/scripts/migrate_hnsw_persistence.exs

require Logger

defmodule HNSWPersistenceMigration do
  @moduledoc """
  Migrates existing HNSW indexes to use persistence.
  
  This script:
  1. Checks for existing vector store data
  2. Creates persistence directories
  3. Saves current indexes to disk
  4. Updates configuration
  """
  
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.Persistence
  
  def run do
    Logger.info("Starting HNSW persistence migration...")
    
    # Ensure persistence directory exists
    persist_base = Application.get_env(:autonomous_opponent_core, :hnsw_persist_path, "priv/vector_store")
    File.mkdir_p!(persist_base)
    
    Logger.info("Created persistence directory: #{persist_base}")
    
    # Check if S4 vector store is running
    case Process.whereis(:s4_vector_store_hnsw) do
      nil ->
        Logger.warn("No running HNSW index found. Skipping migration.")
        Logger.info("New indexes will automatically use persistence.")
      
      pid when is_pid(pid) ->
        migrate_running_index(pid, persist_base)
    end
    
    Logger.info("Migration complete!")
    
    # Print configuration instructions
    print_configuration_instructions()
  end
  
  defp migrate_running_index(pid, persist_base) do
    Logger.info("Found running HNSW index, migrating...")
    
    # Get current stats
    stats = HNSWIndex.stats(pid)
    Logger.info("Current index has #{stats.node_count} nodes")
    
    # Trigger immediate persistence
    persist_path = Path.join(persist_base, "s4_vector_store_hnsw")
    
    case GenServer.call(pid, {:set_persist_path, persist_path}) do
      :ok ->
        Logger.info("Set persistence path: #{persist_path}")
      _ ->
        Logger.warn("Could not set persistence path dynamically")
    end
    
    # Save current state
    case HNSWIndex.persist(pid) do
      :ok ->
        Logger.info("Successfully persisted index to disk")
        
        # Verify persistence
        case Persistence.index_info(persist_path) do
          {:ok, info} ->
            Logger.info("Verified persistence: #{info.node_count} nodes saved")
          {:error, reason} ->
            Logger.error("Failed to verify persistence: #{inspect(reason)}")
        end
        
      error ->
        Logger.error("Failed to persist index: #{inspect(error)}")
    end
  end
  
  defp print_configuration_instructions do
    IO.puts("""
    
    ========================================
    HNSW Persistence Configuration
    ========================================
    
    To enable automatic persistence, add the following to your config:
    
    # config/runtime.exs or config/prod.exs
    config :autonomous_opponent_core,
      hnsw_persist_enabled: true,
      hnsw_persist_path: "priv/vector_store/hnsw_index",
      hnsw_persist_interval: :timer.minutes(5),
      hnsw_prune_interval: :timer.hours(1),
      hnsw_prune_max_age: :timer.hours(24)
    
    For Docker deployments, ensure the persistence directory is mounted:
    
    volumes:
      - ./priv/vector_store:/app/priv/vector_store
    
    The index will now:
    - Automatically save every 5 minutes
    - Persist on graceful shutdown
    - Restore on startup
    - Prune old patterns hourly
    
    ========================================
    """)
  end
end

# Run the migration
HNSWPersistenceMigration.run()