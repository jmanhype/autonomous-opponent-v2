defmodule AutonomousOpponent.VSM.S4.Intelligence.VectorStore.QuantizerTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponent.VSM.S4.Intelligence.VectorStore.Quantizer
  alias AutonomousOpponent.EventBus
  
  @vector_dim 64
  @test_vectors_count 1000
  
  setup do
    {:ok, _} = EventBus.start_link()
    
    {:ok, pid} = Quantizer.start_link(
      id: "test_quantizer",
      vector_dim: @vector_dim,
      subspaces: 8
    )
    
    # Generate test vectors
    vectors = generate_test_vectors(@test_vectors_count, @vector_dim)
    
    {:ok, pid: pid, vectors: vectors}
  end
  
  describe "initialization" do
    test "starts with correct configuration", %{pid: pid} do
      stats = Quantizer.get_stats(pid)
      
      assert stats.config.vector_dim == @vector_dim
      assert stats.config.subspaces == 8
      assert stats.config.centroids_per_subspace == 256
      assert stats.config.accuracy_target == 0.9
      assert stats.state == :initialized
    end
    
    test "supports custom configuration" do
      {:ok, custom_pid} = Quantizer.start_link(
        vector_dim: 128,
        subspaces: 16,
        centroids: 512,
        accuracy_target: 0.95,
        type: :scalar
      )
      
      stats = Quantizer.get_stats(custom_pid)
      
      assert stats.config.vector_dim == 128
      assert stats.config.subspaces == 16
      assert stats.config.centroids_per_subspace == 512
      assert stats.config.accuracy_target == 0.95
      assert stats.config.quantization_type == :scalar
    end
  end
  
  describe "training" do
    test "trains codebooks on vector dataset", %{pid: pid, vectors: vectors} do
      training_vectors = Enum.take(vectors, 500)
      
      assert {:ok, stats} = Quantizer.train(pid, training_vectors)
      
      assert stats.vectors_trained == 500
      assert stats.compression_ratio > 0
      assert stats.average_error >= 0
      
      # Check state changed to trained
      current_stats = Quantizer.get_stats(pid)
      assert current_stats.state == :trained
    end
    
    test "calculates compression ratio correctly", %{pid: pid, vectors: vectors} do
      training_vectors = Enum.take(vectors, 100)
      
      {:ok, stats} = Quantizer.train(pid, training_vectors)
      
      # Expected compression ratio: 
      # Original: 100 vectors * 64 dims * 4 bytes = 25,600 bytes
      # Compressed: 100 vectors * 8 subspaces * 1 byte = 800 bytes
      # Ratio: 25,600 / 800 = 32
      expected_ratio = 32.0
      
      assert_in_delta stats.compression_ratio, expected_ratio, 0.1
    end
    
    test "handles empty training set gracefully", %{pid: pid} do
      assert {:error, _} = Quantizer.train(pid, [])
    end
  end
  
  describe "quantization" do
    setup %{pid: pid, vectors: vectors} do
      # Train the quantizer first
      training_vectors = Enum.take(vectors, 500)
      {:ok, _} = Quantizer.train(pid, training_vectors)
      
      {:ok, trained_pid: pid}
    end
    
    test "quantizes single vector", %{trained_pid: pid, vectors: vectors} do
      test_vector = hd(vectors)
      
      assert {:ok, quantized, error} = Quantizer.quantize(pid, test_vector)
      
      assert Map.has_key?(quantized, :codes)
      assert Map.has_key?(quantized, :type)
      assert quantized.type == :product_quantized
      assert length(quantized.codes) == 8  # 8 subspaces
      assert error >= 0 and error < 1.0
    end
    
    test "quantizes batch of vectors", %{trained_pid: pid, vectors: vectors} do
      test_batch = Enum.take(vectors, 10)
      
      results = Quantizer.quantize_batch(pid, test_batch)
      
      assert length(results) == 10
      assert Enum.all?(results, fn 
        {:ok, _quantized, _error} -> true
        _ -> false
      end)
    end
    
    test "returns error when not trained", %{vectors: vectors} do
      {:ok, untrained_pid} = Quantizer.start_link(vector_dim: @vector_dim)
      
      test_vector = hd(vectors)
      assert {:error, :not_trained} = Quantizer.quantize(untrained_pid, test_vector)
    end
  end
  
  describe "reconstruction" do
    setup %{pid: pid, vectors: vectors} do
      # Train the quantizer
      training_vectors = Enum.take(vectors, 500)
      {:ok, _} = Quantizer.train(pid, training_vectors)
      
      {:ok, trained_pid: pid}
    end
    
    test "reconstructs quantized vector", %{trained_pid: pid, vectors: vectors} do
      test_vector = hd(vectors)
      
      {:ok, quantized, _} = Quantizer.quantize(pid, test_vector)
      {:ok, reconstructed} = Quantizer.reconstruct(pid, quantized)
      
      assert length(reconstructed) == @vector_dim
      assert Enum.all?(reconstructed, &is_float/1)
    end
    
    test "reconstruction error is within acceptable bounds", %{trained_pid: pid, vectors: vectors} do
      test_vectors = Enum.take(vectors, 100)
      
      errors = Enum.map(test_vectors, fn vector ->
        {:ok, quantized, _} = Quantizer.quantize(pid, vector)
        {:ok, reconstructed} = Quantizer.reconstruct(pid, quantized)
        
        # Calculate L2 error
        calculate_l2_error(vector, reconstructed)
      end)
      
      avg_error = Enum.sum(errors) / length(errors)
      
      # Average error should be reasonable for 90% accuracy target
      assert avg_error < 0.2
    end
  end
  
  describe "accuracy vs storage trade-off" do
    setup %{pid: pid, vectors: vectors} do
      # Train with default settings
      training_vectors = Enum.take(vectors, 500)
      {:ok, _} = Quantizer.train(pid, training_vectors)
      
      {:ok, trained_pid: pid}
    end
    
    test "adjusts configuration for high accuracy", %{trained_pid: pid} do
      :ok = Quantizer.configure_tradeoff(pid, 0.95)
      
      stats = Quantizer.get_stats(pid)
      assert stats.config.centroids_per_subspace == 512
      assert stats.config.subspaces <= 4
    end
    
    test "adjusts configuration for high compression", %{trained_pid: pid} do
      :ok = Quantizer.configure_tradeoff(pid, 0.7)
      
      stats = Quantizer.get_stats(pid)
      assert stats.config.centroids_per_subspace == 64
      assert stats.config.subspaces >= 16
    end
    
    test "retrains when configuration changes with sufficient data", %{trained_pid: pid, vectors: vectors} do
      # Add vectors to buffer
      Enum.each(Enum.take(vectors, 200), fn vector ->
        Quantizer.quantize(pid, vector)
      end)
      
      :ok = Quantizer.configure_tradeoff(pid, 0.8)
      
      # Should have retrained with new config
      stats = Quantizer.get_stats(pid)
      assert stats.config.centroids_per_subspace == 128
    end
  end
  
  describe "adaptive retraining" do
    setup %{pid: pid, vectors: vectors} do
      # Train initially
      training_vectors = Enum.take(vectors, 200)
      {:ok, _} = Quantizer.train(pid, training_vectors)
      
      {:ok, trained_pid: pid}
    end
    
    test "buffers vectors for retraining", %{trained_pid: pid, vectors: vectors} do
      initial_stats = Quantizer.get_stats(pid)
      
      # Quantize some vectors
      Enum.each(Enum.take(vectors, 50), fn vector ->
        Quantizer.quantize(pid, vector)
      end)
      
      stats = Quantizer.get_stats(pid)
      assert stats.buffer_size == 50
      assert stats.vectors_quantized == initial_stats.vectors_quantized + 50
    end
    
    test "automatically retrains when buffer threshold reached", %{trained_pid: pid} do
      # Generate and quantize enough vectors to trigger retraining
      # Note: threshold is 1000 vectors
      large_vector_set = generate_test_vectors(1001, @vector_dim)
      
      initial_stats = Quantizer.get_stats(pid)
      
      Enum.each(large_vector_set, fn vector ->
        Quantizer.quantize(pid, vector)
      end)
      
      final_stats = Quantizer.get_stats(pid)
      
      # Buffer should be cleared after retraining
      assert final_stats.buffer_size < 1000
      assert final_stats.quantization_stats.last_retrain != nil
    end
  end
  
  describe "event integration" do
    setup %{pid: pid, vectors: vectors} do
      # Train the quantizer
      training_vectors = Enum.take(vectors, 300)
      {:ok, _} = Quantizer.train(pid, training_vectors)
      
      {:ok, trained_pid: pid}
    end
    
    test "processes pattern extraction events", %{trained_pid: pid} do
      pattern_vectors = generate_test_vectors(10, @vector_dim)
      
      EventBus.publish(:pattern_extracted, %{
        patterns: ["pattern1", "pattern2"],
        vectors: pattern_vectors
      })
      
      # Give time to process
      Process.sleep(100)
      
      stats = Quantizer.get_stats(pid)
      assert stats.buffer_size == 10
    end
    
    test "pre-quantizes vectors for index search", %{trained_pid: pid} do
      search_vector = generate_random_vector(@vector_dim)
      
      EventBus.publish(:vector_index_update, %{
        operation: :search,
        vector: search_vector
      })
      
      # Should process without error
      Process.sleep(100)
    end
  end
  
  describe "memory efficiency" do
    test "tracks memory savings", %{pid: pid, vectors: vectors} do
      training_vectors = Enum.take(vectors, 500)
      {:ok, _} = Quantizer.train(pid, training_vectors)
      
      # Quantize test vectors
      test_vectors = Enum.take(Enum.drop(vectors, 500), 100)
      
      Enum.each(test_vectors, fn vector ->
        Quantizer.quantize(pid, vector)
      end)
      
      stats = Quantizer.get_stats(pid)
      
      # Should show memory saved
      # 100 vectors * 64 dims * 4 bytes = 25,600 bytes original
      # 100 vectors * 8 subspaces * 1 byte = 800 bytes compressed
      # Saved: 24,800 bytes
      assert stats.memory_saved_bytes > 0
    end
  end
  
  describe "performance benchmarks" do
    @tag :benchmark
    test "quantization speed benchmark", %{pid: pid, vectors: vectors} do
      # Train first
      training_vectors = Enum.take(vectors, 500)
      {:ok, _} = Quantizer.train(pid, training_vectors)
      
      # Benchmark single vector quantization
      test_vector = hd(vectors)
      
      {time, _result} = :timer.tc(fn ->
        Enum.each(1..1000, fn _ ->
          Quantizer.quantize(pid, test_vector)
        end)
      end)
      
      avg_time_us = time / 1000
      
      # Should be fast - target < 100 microseconds per vector
      assert avg_time_us < 100
    end
    
    @tag :benchmark
    test "batch quantization performance", %{pid: pid, vectors: vectors} do
      # Train first
      training_vectors = Enum.take(vectors, 500)
      {:ok, _} = Quantizer.train(pid, training_vectors)
      
      # Benchmark batch quantization
      test_batch = Enum.take(Enum.drop(vectors, 500), 100)
      
      {time, _result} = :timer.tc(fn ->
        Quantizer.quantize_batch(pid, test_batch)
      end)
      
      avg_time_per_vector_us = time / 100
      
      # Batch should be more efficient than single
      assert avg_time_per_vector_us < 50
    end
    
    @tag :benchmark
    test "training performance benchmark", %{pid: pid} do
      training_vectors = generate_test_vectors(1000, @vector_dim)
      
      {time, {:ok, _}} = :timer.tc(fn ->
        Quantizer.train(pid, training_vectors, iterations: 10)
      end)
      
      time_seconds = time / 1_000_000
      
      # Training 1000 vectors should complete in reasonable time
      assert time_seconds < 10.0
    end
  end
  
  # Helper functions
  
  defp generate_test_vectors(count, dim) do
    # Generate clustered data for more realistic testing
    num_clusters = 5
    vectors_per_cluster = div(count, num_clusters)
    
    Enum.flat_map(1..num_clusters, fn cluster_id ->
      # Generate cluster center
      center = generate_random_vector(dim)
      
      # Generate vectors around center
      Enum.map(1..vectors_per_cluster, fn _ ->
        add_noise_to_vector(center, 0.1)
      end)
    end)
  end
  
  defp generate_random_vector(dim) do
    Enum.map(1..dim, fn _ -> :rand.uniform() end)
  end
  
  defp add_noise_to_vector(vector, noise_level) do
    Enum.map(vector, fn v ->
      v + (:rand.uniform() - 0.5) * noise_level
    end)
  end
  
  defp calculate_l2_error(v1, v2) do
    Enum.zip(v1, v2)
    |> Enum.map(fn {a, b} -> :math.pow(a - b, 2) end)
    |> Enum.sum()
    |> :math.sqrt()
  end
end