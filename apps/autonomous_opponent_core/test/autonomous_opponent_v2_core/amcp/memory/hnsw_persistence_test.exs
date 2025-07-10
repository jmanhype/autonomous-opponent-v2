defmodule AutonomousOpponentV2Core.AMCP.Memory.HNSWPersistenceTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.Persistence
  
  @test_persist_path "test/tmp/hnsw_test_index"
  @test_vector_dim 16
  
  setup do
    # Clean up any existing test files
    File.rm_rf!(Path.dirname(@test_persist_path))
    File.mkdir_p!(Path.dirname(@test_persist_path))
    
    on_exit(fn ->
      File.rm_rf!(Path.dirname(@test_persist_path))
    end)
    
    :ok
  end
  
  describe "periodic persistence" do
    test "automatically saves index at configured interval" do
      # Start index with short persist interval
      {:ok, index} = HNSWIndex.start_link(
        name: :test_hnsw_auto_save,
        persist_path: @test_persist_path,
        persist_interval: 100  # 100ms for testing
      )
      
      # Add some vectors
      vectors = for i <- 1..10 do
        vector = for _ <- 1..@test_vector_dim, do: :rand.uniform()
        metadata = %{id: i, inserted_at: DateTime.utc_now()}
        HNSWIndex.insert(index, vector, metadata)
        vector
      end
      
      # Wait for automatic persistence
      Process.sleep(150)
      
      # Verify index was persisted
      assert Persistence.index_exists?(@test_persist_path)
      
      # Load and verify contents
      {:ok, info} = Persistence.index_info(@test_persist_path)
      assert info.node_count == 10
      
      # Stop the index
      GenServer.stop(index)
    end
    
    test "persists on graceful shutdown" do
      {:ok, index} = HNSWIndex.start_link(
        name: :test_hnsw_shutdown,
        persist_path: @test_persist_path,
        persist_interval: :timer.hours(1)  # Long interval
      )
      
      # Add vectors
      for i <- 1..5 do
        vector = for _ <- 1..@test_vector_dim, do: :rand.uniform()
        HNSWIndex.insert(index, vector, %{id: i})
      end
      
      # Gracefully stop (should trigger persistence)
      GenServer.stop(index, :normal)
      
      # Verify persistence
      assert Persistence.index_exists?(@test_persist_path)
      {:ok, info} = Persistence.index_info(@test_persist_path)
      assert info.node_count == 5
    end
    
    test "restores index from disk on startup" do
      # Create and populate first index
      {:ok, index1} = HNSWIndex.start_link(
        name: :test_hnsw_restore1,
        persist_path: @test_persist_path
      )
      
      vectors = for i <- 1..20 do
        vector = for _ <- 1..@test_vector_dim, do: :rand.uniform()
        HNSWIndex.insert(index1, vector, %{id: i, data: "test_#{i}"})
        vector
      end
      
      # Persist and stop
      :ok = HNSWIndex.persist(index1)
      GenServer.stop(index1)
      
      # Start new index with same path
      {:ok, index2} = HNSWIndex.start_link(
        name: :test_hnsw_restore2,
        persist_path: @test_persist_path
      )
      
      # Verify data was restored
      stats = HNSWIndex.stats(index2)
      assert stats.node_count == 20
      
      # Test search functionality
      query = Enum.at(vectors, 0)
      {:ok, results} = HNSWIndex.search(index2, query, 5)
      assert length(results) == 5
      assert hd(results).metadata.id == 1
      
      GenServer.stop(index2)
    end
    
    test "handles concurrent operations during persistence" do
      {:ok, index} = HNSWIndex.start_link(
        name: :test_hnsw_concurrent,
        persist_path: @test_persist_path,
        persist_interval: 50
      )
      
      # Start concurrent insertions
      tasks = for i <- 1..100 do
        Task.async(fn ->
          vector = for _ <- 1..@test_vector_dim, do: :rand.uniform()
          HNSWIndex.insert(index, vector, %{id: i})
        end)
      end
      
      # Wait for some persistence cycles
      Process.sleep(200)
      
      # Wait for all insertions
      Task.await_many(tasks)
      
      # Final persist
      :ok = HNSWIndex.persist(index)
      
      # Verify all data
      stats = HNSWIndex.stats(index)
      assert stats.node_count == 100
      
      GenServer.stop(index)
    end
  end
  
  describe "memory optimization" do
    test "persistence does not cause memory spikes" do
      {:ok, index} = HNSWIndex.start_link(
        name: :test_hnsw_memory,
        persist_path: @test_persist_path
      )
      
      # Add substantial data
      for i <- 1..100 do
        vector = for _ <- 1..128, do: :rand.uniform()
        HNSWIndex.insert(index, vector, %{id: i})
      end
      
      # Force garbage collection before measurement
      :erlang.garbage_collect(index)
      Process.sleep(100)
      
      # Get memory before persistence
      {:memory, mem_before} = Process.info(index, :memory)
      
      # Trigger persistence
      :ok = HNSWIndex.persist(index)
      
      # Force garbage collection after persistence
      :erlang.garbage_collect(index)
      Process.sleep(100)
      
      # Get memory after persistence
      {:memory, mem_after} = Process.info(index, :memory)
      
      # Memory increase should be minimal (persistence is non-copying)
      # Allow for some overhead but it should be less than doubling
      assert mem_after < mem_before * 2.0
      
      # Log the actual memory usage for debugging
      memory_increase = (mem_after - mem_before) / mem_before * 100
      IO.puts("Memory increase: #{Float.round(memory_increase, 2)}%")
      
      GenServer.stop(index)
    end
  end
  
  describe "error recovery" do
    test "continues operation if persistence fails" do
      # Use invalid path - but create parent directory to avoid crash
      invalid_base = "test/tmp/readonly"
      File.mkdir_p!(invalid_base)
      File.chmod!(invalid_base, 0o444)  # Read-only
      
      {:ok, index} = HNSWIndex.start_link(
        name: :test_hnsw_error_recovery,
        persist_path: Path.join(invalid_base, "index"),
        persist_interval: 50
      )
      
      # Add data
      vector = for _ <- 1..@test_vector_dim, do: :rand.uniform()
      {:ok, _} = HNSWIndex.insert(index, vector, %{test: true})
      
      # Wait for persist attempt
      Process.sleep(100)
      
      # Index should still be operational despite persistence failure
      stats = HNSWIndex.stats(index)
      assert stats.node_count == 1
      
      # Search should work
      {:ok, results} = HNSWIndex.search(index, vector, 1)
      assert length(results) == 1
      
      GenServer.stop(index)
      
      # Cleanup
      File.chmod!(invalid_base, 0o755)
      File.rm_rf!(invalid_base)
    end
    
    test "handles corrupted persistence files gracefully" do
      # Create corrupted file
      File.mkdir_p!(Path.dirname(@test_persist_path))
      File.write!(@test_persist_path, "corrupted data")
      
      # Should start fresh when corrupted
      {:ok, index} = HNSWIndex.start_link(
        name: :test_hnsw_corrupted,
        persist_path: @test_persist_path
      )
      
      stats = HNSWIndex.stats(index)
      assert stats.node_count == 0
      
      GenServer.stop(index)
    end
  end
end