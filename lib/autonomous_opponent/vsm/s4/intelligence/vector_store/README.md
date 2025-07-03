# S4 Intelligence Vector Store

## Overview

The Vector Store provides memory-efficient pattern storage and similarity search for S4 Intelligence. It uses vector quantization to compress high-dimensional pattern vectors by 10-100x while maintaining 90%+ search accuracy.

## Architecture

```
Pattern Extraction → Vectorization → Quantization → Storage → Similarity Search
                                          ↓
                                    HNSW Index (Future)
```

## Components

### 1. Vector Quantizer (`quantizer.ex`)

Implements product quantization with k-means clustering for vector compression.

**Key Features:**
- Product quantization splits vectors into subspaces
- K-means clustering finds representative centroids
- Adaptive retraining handles data drift
- Configurable accuracy/storage trade-offs

**Usage:**
```elixir
# Start quantizer
{:ok, quantizer} = Quantizer.start_link(
  vector_dim: 64,
  subspaces: 8,
  accuracy_target: 0.9
)

# Train on data
vectors = [...]  # Your pattern vectors
{:ok, stats} = Quantizer.train(quantizer, vectors)

# Quantize vectors
{:ok, compressed, error} = Quantizer.quantize(quantizer, vector)

# Reconstruct if needed
{:ok, reconstructed} = Quantizer.reconstruct(quantizer, compressed)
```

### 2. HNSW Interface (`hnsw_interface.ex`)

Defines the interface for future HNSW (Hierarchical Navigable Small World) index integration.

**Note:** This is a placeholder for Task 4 implementation. The interface shows how quantized vectors will integrate with the graph-based index.

### 3. Vector Store (`vector_store.ex`)

High-level integration layer that combines pattern extraction, quantization, and indexing.

**Usage:**
```elixir
# Start vector store
{:ok, store} = VectorStore.start_link(vector_dim: 64)

# Store patterns
{:ok, pattern_id} = VectorStore.store_pattern(store, pattern, metadata)

# Find similar patterns
{:ok, similar} = VectorStore.find_similar_patterns(store, query_pattern, k: 10)
```

## Configuration

### Accuracy vs Storage Trade-offs

```elixir
# High accuracy (95%+) - Less compression
Quantizer.configure_tradeoff(quantizer, 0.95)
# → 512 centroids, 4 subspaces

# Balanced (90%) - Default
Quantizer.configure_tradeoff(quantizer, 0.9)
# → 256 centroids, 8 subspaces

# High compression (80%) - More compression
Quantizer.configure_tradeoff(quantizer, 0.8)
# → 128 centroids, 16 subspaces
```

### Memory Calculations

For 1M vectors of dimension 64:
- Uncompressed: 1M × 64 × 4 bytes = 256 MB
- Compressed (8 subspaces): 1M × 8 × 1 byte = 8 MB
- Compression ratio: 32x

## Integration with S4 Intelligence

The Vector Store automatically integrates with S4's pattern extraction:

1. **Automatic Storage**: Patterns extracted by S4 are automatically vectorized and stored
2. **Similarity Search**: Historical patterns can be quickly retrieved for comparison
3. **Adaptive Learning**: The quantizer retrains as new patterns are discovered

## Testing

Run the comprehensive test suite:

```bash
# Run all vector store tests
mix test test/autonomous_opponent/vsm/s4/intelligence/vector_store/

# Run specific test file
mix test test/autonomous_opponent/vsm/s4/intelligence/vector_store/quantizer_test.exs

# Run benchmarks
mix test --only benchmark
```

## Performance Characteristics

- **Quantization Speed**: < 100 μs per vector
- **Batch Quantization**: < 50 μs per vector
- **Training Time**: < 10s for 1000 vectors
- **Memory Savings**: 10-100x compression
- **Accuracy**: 90%+ recall at k=10 (configurable)

## Future Enhancements

1. **HNSW Integration** (Task 4): Graph-based index for log(n) search
2. **GPU Acceleration**: CUDA kernels for k-means training
3. **Distributed Quantization**: Multi-node training for large datasets
4. **Learned Quantization**: Neural networks for optimal code assignment
5. **Streaming Updates**: Online k-means for continuous adaptation

## Implementation Notes

### Why Product Quantization?

Product quantization provides exponential compression by dividing vectors into independent subspaces. With 8 subspaces and 256 centroids each, we get 256^8 possible encodings using only 8 bytes.

### K-means++ Initialization

We use k-means++ for centroid initialization, which spreads initial points for better convergence and avoids poor local minima.

### Adaptive Retraining

The quantizer buffers incoming vectors and retrains every 1000 vectors to handle distribution drift in S4's evolving pattern space.

## Dependencies

This implementation has no external dependencies beyond Elixir/OTP. When HNSW is implemented (Task 4), it may require:
- NIF for performance-critical graph operations
- Memory-mapped files for large indices
- SIMD instructions for distance calculations

## Wisdom Preservation

The 90% accuracy target balances pattern recognition quality with memory efficiency. Below 90%, S4's pattern matching degrades noticeably. Above 95%, compression benefits diminish rapidly. This sweet spot enables S4 to maintain 10-100x larger pattern libraries.