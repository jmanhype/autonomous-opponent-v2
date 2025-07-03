defmodule AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore.HNSWInterface do
  @moduledoc """
  Interface for HNSW (Hierarchical Navigable Small World) Index Integration
  
  This module provides the interface that will be used to integrate the Vector Quantizer
  with the HNSW index once Task 4 is implemented. It defines the expected API and
  behavior for compressed vector search operations.
  
  ## Integration Points
  
  1. **Index Building**: Quantized vectors are indexed in HNSW structure
  2. **Search**: Query vectors are quantized before searching
  3. **Updates**: New vectors are quantized and added to index
  4. **Reconstruction**: Retrieved vectors can be reconstructed if needed
  
  ## Future Implementation Notes
  
  When implementing the actual HNSW index (Task 4), ensure:
  - Support for quantized vector codes as index entries
  - Custom distance functions that work on quantized representations
  - Efficient batch operations for index updates
  - Memory-mapped storage for large indices
  """
  
  @callback build_index(vectors :: list(), quantizer :: pid()) :: {:ok, index_ref :: term()} | {:error, term()}
  
  @callback search(index_ref :: term(), query_vector :: list(), k :: integer(), quantizer :: pid()) :: 
    {:ok, [{vector_id :: term(), distance :: float()}]} | {:error, term()}
  
  @callback add_vector(index_ref :: term(), vector :: list(), vector_id :: term(), quantizer :: pid()) :: 
    :ok | {:error, term()}
  
  @callback remove_vector(index_ref :: term(), vector_id :: term()) :: 
    :ok | {:error, term()}
  
  @callback get_vector(index_ref :: term(), vector_id :: term(), quantizer :: pid()) :: 
    {:ok, vector :: list()} | {:error, term()}
  
  @doc """
  Placeholder for HNSW index builder.
  This will be implemented in Task 4.
  """
  def build_index(_vectors, _quantizer) do
    {:error, :not_implemented}
  end
  
  @doc """
  Placeholder for similarity search.
  This will be implemented in Task 4.
  """
  def search(_index_ref, _query_vector, _k, _quantizer) do
    {:error, :not_implemented}
  end
  
  @doc """
  Example of how quantizer will integrate with HNSW for search operations.
  """
  def quantized_search_example(quantizer_pid, query_vector, index_ref, k) do
    # 1. Quantize the query vector
    case AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore.Quantizer.quantize(quantizer_pid, query_vector) do
      {:ok, quantized_query, _error} ->
        # 2. Search using quantized representation
        # In actual implementation, HNSW will use quantized codes for fast similarity computation
        search(index_ref, quantized_query.codes, k, quantizer_pid)
        
      error ->
        error
    end
  end
  
  @doc """
  Example of how to build an index with quantized vectors.
  """
  def build_quantized_index_example(quantizer_pid, vectors) do
    # 1. Quantize all vectors
    quantized_results = 
      AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore.Quantizer.quantize_batch(
        quantizer_pid, 
        vectors
      )
    
    # 2. Extract successfully quantized vectors
    quantized_vectors = 
      quantized_results
      |> Enum.filter(fn 
        {:ok, _, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, quantized, _} -> quantized end)
    
    # 3. Build HNSW index with quantized representations
    # Actual implementation will store codes and build graph structure
    build_index(quantized_vectors, quantizer_pid)
  end
end