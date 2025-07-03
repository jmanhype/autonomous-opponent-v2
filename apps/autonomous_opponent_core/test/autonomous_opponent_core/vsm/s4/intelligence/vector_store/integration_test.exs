defmodule AutonomousOpponentCore.VSM.S4.Intelligence.VectorStore.IntegrationTest do
  use ExUnit.Case, async: false

  alias AutonomousOpponentCore.VSM.S4.Intelligence.VectorStore.Quantizer
  alias AutonomousOpponentV2Core.EventBus

  @vector_dim 8  # Small dimension for fast tests
  @test_vectors_count 10  # Small count for fast tests

  test "basic quantizer functionality works" do
    # Start EventBus if needed
    case EventBus.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Start quantizer
    {:ok, pid} = Quantizer.start_link(
      name: String.to_atom("integration_quantizer_#{:rand.uniform(1000000)}"),
      vector_dim: @vector_dim,
      subspaces: 2
    )

    # Generate simple test vectors
    vectors = Enum.map(1..@test_vectors_count, fn i ->
      Enum.map(1..@vector_dim, fn j -> i * 0.1 + j * 0.01 end)
    end)

    # Test 1: Initial state
    stats = Quantizer.get_stats(pid)
    assert stats.state == :initialized

    # Test 2: Training
    training_vectors = Enum.take(vectors, 5)
    {:ok, training_stats} = Quantizer.train(pid, training_vectors)
    assert training_stats.vectors_trained == 5
    assert training_stats.compression_ratio > 0

    # Test 3: Quantization
    test_vector = Enum.at(vectors, 6)
    {:ok, quantized, error} = Quantizer.quantize(pid, test_vector)
    assert Map.has_key?(quantized, :codes)
    assert error >= 0

    # Test 4: Reconstruction
    {:ok, reconstructed} = Quantizer.reconstruct(pid, quantized)
    assert length(reconstructed) == @vector_dim

    # Test 5: Batch operations
    test_batch = Enum.drop(vectors, 7)
    results = Quantizer.quantize_batch(pid, test_batch)
    assert length(results) == length(test_batch)
    assert Enum.all?(results, fn 
      {:ok, _quantized, _error} -> true
      _ -> false
    end)

    # Test 6: Empty training set error
    {:ok, empty_pid} = Quantizer.start_link(
      name: String.to_atom("empty_quantizer_#{:rand.uniform(1000000)}"),
      vector_dim: @vector_dim
    )
    
    assert {:error, :empty_training_set} = Quantizer.train(empty_pid, [])
  end

  test "quantizer handles configuration correctly" do
    # Start EventBus if needed
    case EventBus.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    {:ok, pid} = Quantizer.start_link(
      name: String.to_atom("config_quantizer_#{:rand.uniform(1000000)}"),
      vector_dim: 16,
      subspaces: 4,
      centroids: 128,
      accuracy_target: 0.8
    )

    stats = Quantizer.get_stats(pid)
    assert stats.config.vector_dim == 16
    assert stats.config.subspaces == 4
    assert stats.config.centroids_per_subspace == 128
    assert stats.config.accuracy_target == 0.8
  end
end