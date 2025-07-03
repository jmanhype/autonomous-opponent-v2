defmodule AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndexTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
  
  describe "start_link/1" do
    test "starts with default configuration" do
      assert {:ok, pid} = HNSWIndex.start_link([])
      assert Process.alive?(pid)
      
      stats = HNSWIndex.stats(pid)
      assert stats.m == 16
      assert stats.ef == 200
      assert stats.node_count == 0
    end
    
    test "starts with custom configuration" do
      assert {:ok, pid} = HNSWIndex.start_link(m: 32, ef: 100, distance_metric: :euclidean)
      
      stats = HNSWIndex.stats(pid)
      assert stats.m == 32
      assert stats.ef == 100
    end
  end
  
  describe "insert/3" do
    setup do
      {:ok, pid} = HNSWIndex.start_link([])
      {:ok, index: pid}
    end
    
    test "inserts single vector", %{index: index} do
      vector = [1.0, 2.0, 3.0]
      metadata = %{label: "test"}
      
      assert {:ok, node_id} = HNSWIndex.insert(index, vector, metadata)
      assert is_integer(node_id)
      assert node_id >= 0
      
      stats = HNSWIndex.stats(index)
      assert stats.node_count == 1
      assert stats.entry_point == node_id
    end
    
    test "inserts multiple vectors", %{index: index} do
      vectors = [
        {[1.0, 0.0, 0.0], %{label: "x"}},
        {[0.0, 1.0, 0.0], %{label: "y"}},
        {[0.0, 0.0, 1.0], %{label: "z"}}
      ]
      
      node_ids = Enum.map(vectors, fn {vec, meta} ->
        {:ok, id} = HNSWIndex.insert(index, vec, meta)
        id
      end)
      
      assert length(node_ids) == 3
      assert Enum.all?(node_ids, &is_integer/1)
      
      stats = HNSWIndex.stats(index)
      assert stats.node_count == 3
    end
    
    test "handles high-dimensional vectors", %{index: index} do
      # 128-dimensional vector (common in ML embeddings)
      vector = Enum.map(1..128, fn i -> :math.sin(i / 10.0) end)
      
      assert {:ok, _node_id} = HNSWIndex.insert(index, vector)
      
      stats = HNSWIndex.stats(index)
      assert stats.node_count == 1
    end
  end
  
  describe "search/4" do
    setup do
      {:ok, pid} = HNSWIndex.start_link(distance_metric: :euclidean)
      
      # Insert test vectors in 3D space
      test_vectors = [
        {[0.0, 0.0, 0.0], %{label: "origin"}},
        {[1.0, 0.0, 0.0], %{label: "x1"}},
        {[2.0, 0.0, 0.0], %{label: "x2"}},
        {[0.0, 1.0, 0.0], %{label: "y1"}},
        {[0.0, 2.0, 0.0], %{label: "y2"}},
        {[0.0, 0.0, 1.0], %{label: "z1"}},
        {[1.0, 1.0, 0.0], %{label: "xy"}},
        {[1.0, 0.0, 1.0], %{label: "xz"}},
        {[0.0, 1.0, 1.0], %{label: "yz"}},
        {[1.0, 1.0, 1.0], %{label: "xyz"}}
      ]
      
      Enum.each(test_vectors, fn {vec, meta} ->
        HNSWIndex.insert(pid, vec, meta)
      end)
      
      {:ok, index: pid}
    end
    
    test "finds exact match", %{index: index} do
      query = [1.0, 0.0, 0.0]
      {:ok, results} = HNSWIndex.search(index, query, 1)
      
      assert length(results) == 1
      [%{distance: dist, metadata: %{label: label}}] = results
      assert dist < 0.0001  # Should be nearly 0
      assert label == "x1"
    end
    
    test "finds k nearest neighbors", %{index: index} do
      query = [0.5, 0.0, 0.0]  # Between origin and x1
      {:ok, results} = HNSWIndex.search(index, query, 3)
      
      assert length(results) == 3
      
      # Should find x1, origin, and x2 in that order
      labels = Enum.map(results, fn %{metadata: %{label: label}} -> label end)
      assert "x1" in labels
      assert "origin" in labels
    end
    
    test "handles empty index gracefully" do
      {:ok, empty_index} = HNSWIndex.start_link([])
      {:ok, results} = HNSWIndex.search(empty_index, [1.0, 2.0, 3.0], 5)
      
      assert results == []
    end
    
    test "respects k parameter", %{index: index} do
      query = [0.0, 0.0, 0.0]
      
      for k <- [1, 3, 5, 20] do
        {:ok, results} = HNSWIndex.search(index, query, k)
        assert length(results) == min(k, 10)  # We only have 10 vectors
      end
    end
    
    test "returns results sorted by distance", %{index: index} do
      query = [0.0, 0.0, 0.0]
      {:ok, results} = HNSWIndex.search(index, query, 10)
      
      distances = Enum.map(results, & &1.distance)
      assert distances == Enum.sort(distances)
    end
  end
  
  describe "cosine distance" do
    setup do
      {:ok, pid} = HNSWIndex.start_link(distance_metric: :cosine)
      {:ok, index: pid}
    end
    
    test "finds similar direction vectors", %{index: index} do
      # Insert vectors with different magnitudes but similar directions
      vectors = [
        {[1.0, 0.0], %{label: "east_1"}},
        {[2.0, 0.0], %{label: "east_2"}},
        {[10.0, 0.0], %{label: "east_10"}},
        {[0.0, 1.0], %{label: "north_1"}},
        {[0.0, 5.0], %{label: "north_5"}},
        {[-1.0, 0.0], %{label: "west_1"}},
        {[0.707, 0.707], %{label: "northeast"}}
      ]
      
      Enum.each(vectors, fn {vec, meta} ->
        HNSWIndex.insert(index, vec, meta)
      end)
      
      # Query with east direction
      query = [5.0, 0.0]
      {:ok, results} = HNSWIndex.search(index, query, 3)
      
      # Should find all east-pointing vectors regardless of magnitude
      labels = Enum.map(results, fn %{metadata: %{label: label}} -> label end)
      assert "east_1" in labels or "east_2" in labels or "east_10" in labels
      
      # Should have very small distances for same-direction vectors
      east_results = Enum.filter(results, fn %{metadata: %{label: label}} ->
        String.starts_with?(label, "east")
      end)
      
      Enum.each(east_results, fn %{distance: dist} ->
        assert dist < 0.0001  # Cosine distance should be ~0 for same direction
      end)
    end
  end
  
  describe "edge cases" do
    setup do
      {:ok, pid} = HNSWIndex.start_link([])
      {:ok, index: pid}
    end
    
    test "handles zero vectors", %{index: index} do
      zero_vector = [0.0, 0.0, 0.0]
      assert {:ok, _} = HNSWIndex.insert(index, zero_vector, %{label: "zero"})
      
      # Search should still work
      {:ok, results} = HNSWIndex.search(index, [1.0, 0.0, 0.0], 1)
      assert length(results) == 1
    end
    
    test "handles duplicate vectors", %{index: index} do
      vector = [1.0, 2.0, 3.0]
      
      # Insert same vector multiple times with different metadata
      {:ok, id1} = HNSWIndex.insert(index, vector, %{version: 1})
      {:ok, id2} = HNSWIndex.insert(index, vector, %{version: 2})
      {:ok, id3} = HNSWIndex.insert(index, vector, %{version: 3})
      
      assert id1 != id2
      assert id2 != id3
      
      # Should find all duplicates
      {:ok, results} = HNSWIndex.search(index, vector, 3)
      assert length(results) == 3
      
      # All should have distance 0
      Enum.each(results, fn %{distance: dist} ->
        assert dist < 0.0001
      end)
    end
  end
  
  describe "memory and performance characteristics" do
    @tag :performance
    test "handles large number of insertions efficiently" do
      {:ok, index} = HNSWIndex.start_link(m: 8, ef: 50)
      
      # Insert 1000 random 10-dimensional vectors
      dimension = 10
      n_vectors = 1000
      
      insert_time = :timer.tc(fn ->
        for i <- 1..n_vectors do
          vector = Enum.map(1..dimension, fn _ -> :rand.uniform() end)
          HNSWIndex.insert(index, vector, %{id: i})
        end
      end) |> elem(0)
      
      avg_insert_time = insert_time / n_vectors / 1000  # ms per insertion
      assert avg_insert_time < 10  # Should be well under 10ms per insert
      
      # Test search performance
      query = Enum.map(1..dimension, fn _ -> :rand.uniform() end)
      
      search_time = :timer.tc(fn ->
        HNSWIndex.search(index, query, 10)
      end) |> elem(0)
      
      search_time_ms = search_time / 1000
      assert search_time_ms < 50  # Should complete in under 50ms
      
      # Check memory usage
      stats = HNSWIndex.stats(index)
      assert stats.node_count == n_vectors
      
      # Memory should be reasonable (rough estimate: ~1KB per vector)
      total_memory = 
        stats.memory_usage.graph_size + 
        stats.memory_usage.data_size + 
        stats.memory_usage.level_size
      
      memory_per_vector = total_memory / n_vectors
      assert memory_per_vector < 5000  # Should use less than 5KB per vector
    end
  end
  
  describe "integration with S4 environmental scanning" do
    setup do
      {:ok, index} = HNSWIndex.start_link(distance_metric: :cosine)
      
      # Simulate pattern vectors from S4 scanning
      # These might represent environmental features
      patterns = [
        {generate_pattern_vector(:stable), %{type: :stable, confidence: 0.9}},
        {generate_pattern_vector(:increasing), %{type: :increasing, confidence: 0.85}},
        {generate_pattern_vector(:decreasing), %{type: :decreasing, confidence: 0.8}},
        {generate_pattern_vector(:cyclic), %{type: :cyclic, confidence: 0.75}},
        {generate_pattern_vector(:anomaly), %{type: :anomaly, confidence: 0.95}}
      ]
      
      Enum.each(patterns, fn {vec, meta} ->
        HNSWIndex.insert(index, vec, meta)
      end)
      
      {:ok, index: index}
    end
    
    test "finds similar environmental patterns", %{index: index} do
      # Query with a new pattern that's similar to cyclic
      query = generate_pattern_vector(:cyclic, 0.1)  # Slightly perturbed
      
      {:ok, results} = HNSWIndex.search(index, query, 2)
      
      # Should find the cyclic pattern as closest match
      [%{metadata: %{type: type}} | _] = results
      assert type == :cyclic
    end
    
    test "identifies anomalous patterns", %{index: index} do
      # Query with a very different pattern
      anomalous = Enum.map(1..50, fn _ -> :rand.uniform() * 10 end)
      
      {:ok, results} = HNSWIndex.search(index, anomalous, 5)
      
      # Anomaly should have high distance to all normal patterns
      avg_distance = 
        results
        |> Enum.map(& &1.distance)
        |> Enum.sum()
        |> Kernel./(5)
      
      assert avg_distance > 0.5  # High distance indicates anomaly
    end
  end
  
  # Helper functions
  
  # Define default once
  defp generate_pattern_vector(type, noise \\ 0.0)
  
  defp generate_pattern_vector(:stable, noise) do
    base = 0.5
    Enum.map(1..50, fn _ -> base + :rand.uniform() * noise end)
  end
  
  defp generate_pattern_vector(:increasing, noise) do
    Enum.map(1..50, fn i -> i / 50.0 + :rand.uniform() * noise end)
  end
  
  defp generate_pattern_vector(:decreasing, noise) do
    Enum.map(1..50, fn i -> 1.0 - i / 50.0 + :rand.uniform() * noise end)
  end
  
  defp generate_pattern_vector(:cyclic, noise) do
    Enum.map(1..50, fn i -> 
      :math.sin(i * 2 * :math.pi() / 10) + :rand.uniform() * noise 
    end)
  end
  
  defp generate_pattern_vector(:anomaly, _noise) do
    Enum.map(1..50, fn i ->
      if rem(i, 7) == 0, do: :rand.uniform() * 5, else: 0.1
    end)
  end
  
  describe "search_batch/4" do
    setup do
      {:ok, pid} = HNSWIndex.start_link([])
      
      # Insert test vectors
      vectors = [
        {[1.0, 0.0, 0.0], %{label: "x"}},
        {[0.0, 1.0, 0.0], %{label: "y"}},
        {[0.0, 0.0, 1.0], %{label: "z"}},
        {[0.707, 0.707, 0.0], %{label: "xy"}},
        {[0.707, 0.0, 0.707], %{label: "xz"}}
      ]
      
      Enum.each(vectors, fn {v, m} ->
        HNSWIndex.insert(pid, v, m)
      end)
      
      {:ok, index: pid}
    end
    
    test "searches multiple vectors in parallel", %{index: index} do
      queries = [
        [1.0, 0.0, 0.0],    # Should find x
        [0.0, 1.0, 0.0],    # Should find y
        [0.0, 0.0, 1.0]     # Should find z
      ]
      
      assert {:ok, results} = HNSWIndex.search_batch(index, queries, 1)
      assert length(results) == 3
      
      # Check each result
      [r1, r2, r3] = results
      assert [%{metadata: %{label: "x"}}] = r1
      assert [%{metadata: %{label: "y"}}] = r2
      assert [%{metadata: %{label: "z"}}] = r3
    end
    
    test "returns results in same order as queries", %{index: index} do
      queries = [
        [0.0, 0.0, 1.0],    # z
        [1.0, 0.0, 0.0],    # x
        [0.0, 1.0, 0.0]     # y
      ]
      
      assert {:ok, results} = HNSWIndex.search_batch(index, queries, 2)
      assert length(results) == 3
      
      # Verify order is preserved
      [r1, r2, r3] = results
      assert hd(r1).metadata.label == "z"
      assert hd(r2).metadata.label == "x"
      assert hd(r3).metadata.label == "y"
    end
    
    test "handles empty index", %{index: _} do
      {:ok, empty_index} = HNSWIndex.start_link([])
      queries = [[1.0, 0.0], [0.0, 1.0]]
      
      assert {:ok, results} = HNSWIndex.search_batch(empty_index, queries, 5)
      assert results == [[], []]
    end
  end
  
  describe "compact/1" do
    setup do
      {:ok, pid} = HNSWIndex.start_link([])
      {:ok, index: pid}
    end
    
    test "compacts index and returns stats", %{index: index} do
      # Insert some vectors
      for i <- 1..10 do
        vector = Enum.map(1..5, fn _ -> :rand.uniform() end)
        HNSWIndex.insert(index, vector, %{id: i})
      end
      
      assert {:ok, stats} = HNSWIndex.compact(index)
      assert Map.has_key?(stats, :removed_nodes)
      assert Map.has_key?(stats, :optimized_connections)
      assert stats.total_nodes > 0
    end
  end
  
  describe "prune_old_patterns/2" do
    setup do
      {:ok, pid} = HNSWIndex.start_link([])
      {:ok, index: pid}
    end
    
    test "removes patterns older than max age", %{index: index} do
      # Insert old pattern with past timestamp
      old_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      HNSWIndex.insert(index, [1.0, 2.0], %{inserted_at: old_time})
      
      # Insert recent pattern
      HNSWIndex.insert(index, [3.0, 4.0], %{})
      
      # Prune patterns older than 30 minutes
      assert {:ok, removed} = HNSWIndex.prune_old_patterns(index, 30 * 60 * 1000)
      assert removed == 1
      
      # Verify only recent pattern remains
      assert {:ok, results} = HNSWIndex.search(index, [3.0, 4.0], 10)
      assert length(results) == 1
    end
    
    test "preserves patterns without timestamp", %{index: index} do
      # Insert pattern without timestamp (legacy data)
      HNSWIndex.insert(index, [1.0, 2.0], %{label: "legacy"})
      
      # Attempt to prune
      assert {:ok, removed} = HNSWIndex.prune_old_patterns(index, 1000)
      assert removed == 0
      
      # Verify pattern still exists
      assert {:ok, results} = HNSWIndex.search(index, [1.0, 2.0], 1)
      assert length(results) == 1
      assert hd(results).metadata.label == "legacy"
    end
  end
  
  describe "automatic pruning" do
    test "schedules periodic pruning when configured" do
      {:ok, index} = HNSWIndex.start_link(
        prune_interval: 100,  # 100ms for testing
        prune_max_age: 50     # 50ms max age
      )
      
      # Insert pattern that will become old
      HNSWIndex.insert(index, [1.0, 2.0], %{label: "old"})
      
      # Wait for auto-prune to trigger
      Process.sleep(150)
      
      # Insert new pattern
      HNSWIndex.insert(index, [3.0, 4.0], %{label: "new"})
      
      # Verify old pattern was pruned
      assert {:ok, results} = HNSWIndex.search(index, [1.0, 2.0], 10)
      # Old pattern should be gone or new pattern should be found
      assert length(results) <= 1
    end
  end
  
  describe "telemetry events" do
    setup do
      {:ok, pid} = HNSWIndex.start_link([])
      {:ok, index: pid}
    end
    
    test "emits telemetry events for operations", %{index: index} do
      # Set up telemetry handler
      :telemetry.attach(
        "test-handler",
        [:hnsw, :insert],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      # Insert vector
      HNSWIndex.insert(index, [1.0, 2.0, 3.0], %{})
      
      # Verify telemetry event
      assert_receive {:telemetry_event, [:hnsw, :insert], measurements, metadata}
      assert measurements.duration > 0
      assert measurements.vector_size == 3
      assert metadata.m == 16
      
      :telemetry.detach("test-handler")
    end
  end
end