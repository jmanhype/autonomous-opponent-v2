defmodule AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndexBenchmark do
  @moduledoc """
  Performance benchmarks for HNSW index implementation.
  
  Run with: mix run test/autonomous_opponent/vsm/s4/vector_store/hnsw_index_benchmark.exs
  """
  
  alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
  
  @vector_dimensions [10, 50, 128, 256]
  @dataset_sizes [100, 1000, 5000]
  @k_values [1, 10, 50]
  @m_values [8, 16, 32]
  
  def run do
    IO.puts("HNSW Index Performance Benchmarks")
    IO.puts("=================================\n")
    
    run_insertion_benchmarks()
    run_search_benchmarks()
    run_accuracy_benchmarks()
    run_memory_benchmarks()
  end
  
  defp run_insertion_benchmarks do
    IO.puts("## Insertion Performance")
    IO.puts("| Dimensions | Vectors | M | Avg Insert Time (ms) | Total Time (s) |")
    IO.puts("|------------|---------|---|---------------------|----------------|")
    
    for dim <- @vector_dimensions,
        size <- @dataset_sizes,
        m <- [16] do  # Test with default M
      
      {:ok, index} = HNSWIndex.start_link(m: m)
      
      vectors = generate_random_vectors(size, dim)
      
      {total_time, _} = :timer.tc(fn ->
        Enum.each(vectors, fn vec ->
          HNSWIndex.insert(index, vec)
        end)
      end)
      
      avg_time = total_time / size / 1000  # ms
      total_s = total_time / 1_000_000  # seconds
      
      IO.puts("| #{dim} | #{size} | #{m} | #{Float.round(avg_time, 3)} | #{Float.round(total_s, 2)} |")
      
      Process.exit(index, :kill)
    end
    
    IO.puts("")
  end
  
  defp run_search_benchmarks do
    IO.puts("## Search Performance")
    IO.puts("| Dimensions | Vectors | K | EF | Avg Search Time (ms) | Queries/sec |")
    IO.puts("|------------|---------|---|----|--------------------|-------------|")
    
    for dim <- [50, 128],
        size <- [1000, 5000],
        k <- @k_values do
      
      {:ok, index} = HNSWIndex.start_link(m: 16, ef: 200)
      
      # Build index
      vectors = generate_random_vectors(size, dim)
      Enum.each(vectors, fn vec ->
        HNSWIndex.insert(index, vec)
      end)
      
      # Test queries
      queries = generate_random_vectors(100, dim)
      
      {query_time, _} = :timer.tc(fn ->
        Enum.each(queries, fn q ->
          HNSWIndex.search(index, q, k)
        end)
      end)
      
      avg_query_time = query_time / 100 / 1000  # ms
      queries_per_sec = 1000 / avg_query_time
      
      IO.puts("| #{dim} | #{size} | #{k} | 200 | #{Float.round(avg_query_time, 3)} | #{Float.round(queries_per_sec, 1)} |")
      
      Process.exit(index, :kill)
    end
    
    IO.puts("")
  end
  
  defp run_accuracy_benchmarks do
    IO.puts("## Search Accuracy (Recall @ K)")
    IO.puts("| Dimensions | Vectors | M | EF | K | Recall |")
    IO.puts("|------------|---------|---|----|----|--------|")
    
    for dim <- [50],
        size <- [1000],
        m <- @m_values,
        k <- [10] do
      
      # Generate dataset
      vectors = generate_random_vectors(size, dim)
      queries = generate_random_vectors(10, dim)
      
      # Calculate ground truth (brute force)
      ground_truth = calculate_ground_truth(vectors, queries, k)
      
      # Build HNSW index
      {:ok, index} = HNSWIndex.start_link(m: m, ef: m * 2, distance_metric: :euclidean)
      
      Enum.each(Enum.with_index(vectors), fn {vec, idx} ->
        HNSWIndex.insert(index, vec, %{id: idx})
      end)
      
      # Search with HNSW
      hnsw_results = Enum.map(queries, fn q ->
        {:ok, results} = HNSWIndex.search(index, q, k)
        Enum.map(results, fn %{metadata: %{id: id}} -> id end)
      end)
      
      # Calculate recall
      recall = calculate_recall(ground_truth, hnsw_results)
      
      IO.puts("| #{dim} | #{size} | #{m} | #{m * 2} | #{k} | #{Float.round(recall * 100, 1)}% |")
      
      Process.exit(index, :kill)
    end
    
    IO.puts("")
  end
  
  defp run_memory_benchmarks do
    IO.puts("## Memory Usage")
    IO.puts("| Dimensions | Vectors | M | Memory (MB) | Bytes/Vector |")
    IO.puts("|------------|---------|---|-------------|--------------|")
    
    for dim <- [50, 128],
        size <- @dataset_sizes,
        m <- [16] do
      
      {:ok, index} = HNSWIndex.start_link(m: m)
      
      # Measure initial memory
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)
      
      # Build index
      vectors = generate_random_vectors(size, dim)
      Enum.each(vectors, fn vec ->
        HNSWIndex.insert(index, vec)
      end)
      
      # Measure final memory
      :erlang.garbage_collect()
      final_memory = :erlang.memory(:total)
      
      # Get index stats
      stats = HNSWIndex.stats(index)
      index_memory = 
        stats.memory_usage.graph_size + 
        stats.memory_usage.data_size + 
        stats.memory_usage.level_size
      
      memory_mb = index_memory / 1_048_576
      bytes_per_vector = div(index_memory, size)
      
      IO.puts("| #{dim} | #{size} | #{m} | #{Float.round(memory_mb, 2)} | #{bytes_per_vector} |")
      
      Process.exit(index, :kill)
    end
    
    IO.puts("")
  end
  
  # Helper functions
  
  defp generate_random_vectors(count, dimensions) do
    for _ <- 1..count do
      for _ <- 1..dimensions, do: :rand.uniform()
    end
  end
  
  defp calculate_ground_truth(vectors, queries, k) do
    Enum.map(queries, fn query ->
      vectors
      |> Enum.with_index()
      |> Enum.map(fn {vec, idx} ->
        {euclidean_distance(query, vec), idx}
      end)
      |> Enum.sort()
      |> Enum.take(k)
      |> Enum.map(fn {_, idx} -> idx end)
    end)
  end
  
  defp euclidean_distance(v1, v2) do
    v1
    |> Enum.zip(v2)
    |> Enum.map(fn {a, b} -> :math.pow(a - b, 2) end)
    |> Enum.sum()
    |> :math.sqrt()
  end
  
  defp calculate_recall(ground_truth, results) do
    recall_scores = 
      Enum.zip(ground_truth, results)
      |> Enum.map(fn {truth, found} ->
        truth_set = MapSet.new(truth)
        found_set = MapSet.new(found)
        intersection = MapSet.intersection(truth_set, found_set)
        MapSet.size(intersection) / MapSet.size(truth_set)
      end)
    
    Enum.sum(recall_scores) / length(recall_scores)
  end
end

# Run benchmarks if executed directly
if System.get_env("RUN_BENCHMARKS") == "true" do
  AutonomousOpponent.VSM.S4.VectorStore.HNSWIndexBenchmark.run()
end