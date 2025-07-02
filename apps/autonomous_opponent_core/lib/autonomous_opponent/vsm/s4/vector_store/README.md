# S4 Vector Store - HNSW Index

The Hierarchical Navigable Small World (HNSW) index provides efficient vector similarity search for the S4 Intelligence subsystem's pattern recognition capabilities.

## Overview

HNSW is a graph-based algorithm for approximate nearest neighbor search that builds a multi-layer navigable small world graph. It offers:

- **Logarithmic search complexity**: O(log n) search time
- **Linear space complexity**: O(n) memory usage
- **High recall rates**: >95% recall with proper tuning
- **Incremental construction**: Add vectors without rebuilding

## Quick Start

Get up and running with HNSW in 3 simple steps:

```elixir
# 1. Start the index with default parameters
{:ok, index} = HNSWIndex.start_link(m: 16, ef: 200)

# 2. Insert a vector with metadata
vector = [0.1, 0.2, 0.3, 0.4]  # Your feature vector
metadata = %{source: "sensor_1", timestamp: DateTime.utc_now()}
{:ok, id} = HNSWIndex.insert(index, vector, metadata)

# 3. Search for similar vectors
query = [0.15, 0.18, 0.32, 0.41]
{:ok, results} = HNSWIndex.search(index, query, k: 10)

# Results format: [{distance, node_id, vector, metadata}, ...]
# Example result:
# [{0.012, 1, [0.1, 0.2, 0.3, 0.4], %{source: "sensor_1", ...}}]
```

That's it! The index is now ready for S4 pattern recognition. For production use, see the configuration section below.

## VSM Context for Developers

### What is VSM?
The Viable System Model (VSM) divides complex systems into 5 recursive subsystems:
- **S1 (Operations)**: Does the actual work - the autonomous actions and behaviors
- **S2 (Coordination)**: Prevents conflicts between S1 units, ensures harmony
- **S3 (Control)**: Allocates resources and optimizes operational efficiency
- **S4 (Intelligence)**: Monitors environment and future trends (where HNSW lives!)
- **S5 (Policy)**: Sets direction, purpose, and system identity

### Why HNSW in S4?
S4 Intelligence continuously scans the external environment for patterns, threats, and opportunities. HNSW provides:
- **Fast similarity search** for pattern matching across millions of observations
- **Memory of past environmental states** to identify recurring patterns
- **Foundation for predictive capabilities** by finding similar historical situations
- **Real-time performance** to meet S4's 10-second environmental scan cycle

### Key VSM Principles Applied
- **Variety Absorption**: HNSW handles the complexity of high-dimensional environmental data
- **Autonomy**: S4 operates independently with its own pattern memory
- **Recursion**: Patterns from all system levels (S1-S5) can be indexed and cross-referenced
- **Viability**: Persistence ensures pattern knowledge survives system restarts

### Integration Points
- **From S1**: Operational patterns and behavioral signatures
- **From S2**: Coordination conflict patterns requiring attention
- **From S3**: Resource usage patterns and optimization opportunities
- **To S4**: Environmental change detection and trend analysis
- **To S5**: Long-term pattern shifts that may require policy changes

## Architecture

```
vector_store/
├── hnsw_index.ex         # Core HNSW algorithm with distance metrics
├── pattern_indexer.ex    # Pattern-to-vector conversion service  
├── persistence.ex        # Disk persistence layer
└── benchmarks/
    ├── accuracy_bench.ex # Recall and precision measurements
    └── perf_bench.ex     # Throughput and latency tests
```

**Architecture Note**: Distance metrics (cosine & euclidean) are implemented inline within `hnsw_index.ex` for performance optimization, avoiding function call overhead in hot paths. There is no separate `distance_metrics.ex` module. Similarly, the index uses standard GenServer supervision rather than a custom `supervisor.ex` module. This design choice prioritizes performance and simplicity over modularity for these critical code paths.

## Key Features

### 1. Multi-Layer Graph Structure
- **Layer 0**: Contains all vectors with dense connections
- **Higher Layers**: Progressively sparser for long-range navigation
- **Probabilistic Layer Assignment**: Layer(v) ~ -ln(uniform(0,1)) * mL

### 2. Construction Algorithm (M=16, mL=1/ln(2))
```elixir
def insert(state, vector, metadata) do
  # 1. Assign layer based on exponential decay probability
  node_layer = select_layer(state.ml_factor)
  
  # 2. Find nearest neighbors at each layer
  entry_point = state.entry_point
  nearest = search_layers(state, vector, entry_point, node_layer)
  
  # 3. Insert node and create bidirectional links
  new_node = create_node(vector, metadata, node_layer)
  connect_neighbors(state, new_node, nearest, state.m)
  
  # 4. Prune connections if needed (max M connections per layer)
  prune_connections(state, new_node.neighbors, state.m_max)
end
```

### 3. Search Algorithm (ef=200)
```elixir
def search(state, query_vector, k, ef \\ 200) do
  # 1. Start from entry point at top layer
  candidates = greedy_search_layers(state, query_vector, state.entry_point)
  
  # 2. Search at layer 0 with ef parameter
  w = search_layer_0(state, query_vector, candidates, ef)
  
  # 3. Return k nearest neighbors
  w
  |> Enum.sort_by(fn {distance, _} -> distance end)
  |> Enum.take(k)
end
```

## API Reference

### Core Operations

```elixir
# Start the index with custom parameters
{:ok, index} = HNSWIndex.start_link(
  m: 16,              # Number of bidirectional links per node
  ef_construction: 200, # Size of dynamic candidate list (defaults to ef if not specified)
  ef: 100,            # Search parameter (can be tuned per query)
  distance_metric: :cosine,
  max_elements: 1_000_000
)

# Note: If ef_construction is not specified, it defaults to the same value as ef.
# Higher ef_construction improves index quality but increases build time.

# Insert a vector with metadata
vector = [0.1, 0.2, 0.3, ...]  # 128-dimensional
metadata = %{pattern_type: "user_behavior", source: "web_analytics"}
{:ok, node_id} = HNSWIndex.insert(index, vector, metadata)

# Search for k nearest neighbors
query = [0.15, 0.18, 0.32, ...]
{:ok, results} = HNSWIndex.search(index, query, k: 10, ef: 150)
# Returns: [{distance, node_id, vector, metadata}, ...]

# Batch operations for efficiency
vectors_with_metadata = [
  {vector1, metadata1},
  {vector2, metadata2},
  ...
]
{:ok, node_ids} = HNSWIndex.batch_insert(index, vectors_with_metadata)

# Save index to disk
{:ok, path} = HNSWIndex.save(index, "/path/to/index.hnsw")

# Load index from disk
{:ok, loaded_index} = HNSWIndex.load("/path/to/index.hnsw")
```

### Error Handling

#### Common Errors and Recovery Strategies

```elixir
# Dimension mismatch error handling
case HNSWIndex.insert(index, wrong_size_vector, metadata) do
  {:ok, node_id} -> 
    Logger.info("Indexed pattern #{node_id}")
    
  {:error, :dimension_mismatch} ->
    # Vector dimensions don't match index
    Logger.error("Expected #{index.dimensions} dimensions, got #{length(wrong_size_vector)}")
    # Options: pad/truncate vector or skip
    padded_vector = pad_or_truncate(wrong_size_vector, index.dimensions)
    retry_insert(index, padded_vector, metadata)
    
  {:error, :index_full} ->
    # Maximum elements reached
    Logger.warn("Index at capacity, triggering maintenance")
    # Option 1: Trigger compaction to remove old patterns
    S4.PatternArchiver.archive_old_patterns(days: 30)
    # Option 2: Create new index shard
    {:ok, new_shard} = create_index_shard()
    HNSWIndex.insert(new_shard, vector, metadata)
    
  {:error, :invalid_vector} ->
    # Vector contains NaN or Inf values
    Logger.error("Invalid vector values detected")
    cleaned_vector = sanitize_vector(vector)
    HNSWIndex.insert(index, cleaned_vector, metadata)
end

# Search error handling with fallback
case HNSWIndex.search(index, query_vector, k: 10) do
  {:ok, results} -> 
    process_results(results)
    
  {:error, :empty_index} -> 
    Logger.info("No patterns indexed yet")
    # Return empty results or bootstrap with default patterns
    []
    
  {:error, :search_timeout} ->
    Logger.warn("Search timeout, reducing ef parameter")
    # Retry with lower ef for faster results
    HNSWIndex.search(index, query_vector, k: 10, ef: 50)
    
  {:error, :corrupted_index} ->
    Logger.error("Index corruption detected")
    # Attempt recovery from backup
    case HNSWIndex.restore_from_backup() do
      {:ok, restored_index} -> 
        HNSWIndex.search(restored_index, query_vector, k: 10)
      {:error, _} ->
        # Fall back to brute force search
        S4.BruteForceSearch.find_similar(query_vector, k: 10)
    end
end

# Batch operation error handling
def safe_batch_insert(index, vectors_with_metadata) do
  vectors_with_metadata
  |> Enum.map(fn {vector, metadata} ->
    case HNSWIndex.insert(index, vector, metadata) do
      {:ok, id} -> {:ok, id}
      {:error, reason} = error -> 
        Logger.warn("Failed to insert: #{inspect(reason)}")
        error
    end
  end)
  |> Enum.split_with(fn result -> match?({:ok, _}, result) end)
  |> case do
    {successes, []} -> 
      {:ok, Enum.map(successes, fn {:ok, id} -> id end)}
    {successes, failures} ->
      {:partial, %{
        succeeded: length(successes),
        failed: length(failures),
        success_ids: Enum.map(successes, fn {:ok, id} -> id end),
        errors: failures
      }}
  end
end

# Persistence error handling
def safe_persist(index, path) do
  # Create backup before save
  backup_path = path <> ".backup"
  File.cp!(path, backup_path)
  
  case HNSWIndex.save(index, path) do
    {:ok, ^path} -> 
      # Success, remove backup
      File.rm(backup_path)
      {:ok, path}
      
    {:error, :enospc} ->
      # Out of disk space
      Logger.error("Insufficient disk space for index persistence")
      # Try compressed save
      HNSWIndex.save(index, path, compress: true)
      
    {:error, reason} ->
      # Restore from backup
      Logger.error("Save failed: #{inspect(reason)}, restoring backup")
      File.cp!(backup_path, path)
      {:error, reason}
  end
end
```

### Pattern-Specific Operations

```elixir
# Index S4 patterns directly
pattern = %S4Pattern{
  type: :environmental_anomaly,
  features: %{temperature: 0.8, pressure: 0.2, ...},
  timestamp: DateTime.utc_now()
}
{:ok, pattern_id} = PatternIndexer.index_pattern(pattern)

# Search for similar patterns
{:ok, similar_patterns} = PatternIndexer.find_similar(pattern, k: 10)

# Query by pattern characteristics
{:ok, matches} = PatternIndexer.query(%{
  type: :environmental_anomaly,
  time_range: {~U[2024-01-01 00:00:00Z], ~U[2024-01-02 00:00:00Z]},
  min_similarity: 0.85
})
```

## Configuration

### Optimal Parameters by Use Case

#### High Accuracy (Research/Analysis)
```elixir
{:ok, index} = HNSWIndex.start_link(
  m: 32,              # Higher M for better connectivity
  ef: 500,            # Higher ef for better recall
  distance_metric: :cosine
)
```

#### High Speed (Real-time Processing)
```elixir
{:ok, index} = HNSWIndex.start_link(
  m: 8,               # Lower M for speed
  ef: 50,             # Lower ef for faster queries
  distance_metric: :euclidean
)
```

## Performance Characteristics

### Benchmarks with Real S4 Pattern Data

| Vectors | Dimensions | Insert Time | Search Time (k=10) | Memory/Vector | Recall@10 |
|---------|------------|-------------|-------------------|---------------|----------|
| 1K      | 50         | ~2ms        | ~5ms              | ~2KB          | 99.5%    |
| 10K     | 128        | ~3ms        | ~8ms              | ~3KB          | 98.2%    |
| 100K    | 128        | ~4ms        | ~12ms             | ~3KB          | 96.8%    |
| 1M      | 128        | ~5ms        | ~18ms             | ~3KB          | 95.1%    |
| 10K     | 768        | ~8ms        | ~25ms             | ~8KB          | 97.5%    |

### Memory Usage Formula
```
memory_per_vector = vector_size * 4 bytes + (M * 2 * 8 bytes) + metadata_size
total_memory = num_vectors * memory_per_vector + graph_overhead
```

### Search Performance Factors
1. **ef parameter**: Higher ef = better recall but slower search
2. **Vector dimensions**: Search time grows sub-linearly with dimensions
3. **Index size**: Logarithmic growth in search time
4. **Hardware**: Benefits from CPU cache optimization

### Performance Tuning Decision Tree

```
Is recall < 90%?
├─ Yes → Increase ef (try 2x current value)
│   └─ Still low? → Increase M (try M=24 or M=32)
│       └─ Still low? → Check if vectors are properly normalized
└─ No → Is search > 20ms?
    ├─ Yes → Is index size > 1M vectors?
    │   ├─ Yes → Consider sharding or dimensionality reduction
    │   │   └─ Options: PCA to 128d, or distributed index
    │   └─ No → Decrease ef (try 0.75x current)
    │       └─ Still slow? → Profile distance calculations
    └─ No → Optimal configuration ✓
        └─ Monitor for changes in data distribution
```

**Quick Tuning Guide:**
| Problem | Solution | Trade-off |
|---------|----------|-----------|
| Low recall (<90%) | Increase ef to 400-500 | Slower searches |
| Slow search (>50ms) | Decrease ef to 50-100 | Lower recall |
| High memory usage | Decrease M to 8-12 | Lower connectivity |
| Poor clustering | Increase M to 24-32 | Higher memory |
| Timeout errors | Set hard timeout + reduce ef | May miss results |

## Integration Points

### S4 Environmental Scanner
The scanner generates feature vectors from environmental observations. These are indexed for pattern detection:

```elixir
defmodule S4Integration do
  def process_scan(scan_data) do
    # Convert scan to feature vector
    vector = FeatureExtractor.extract(scan_data)
    
    # Index for future pattern matching
    {:ok, id} = PatternIndexer.index_pattern(%{
      vector: vector,
      type: :environmental_scan,
      metadata: %{
        timestamp: scan_data.timestamp,
        location: scan_data.location,
        sensors: scan_data.sensor_ids
      }
    })
    
    # Check for similar historical patterns
    {:ok, similar} = PatternIndexer.find_similar(vector, k: 10)
    
    # Analyze pattern evolution
    analyze_pattern_drift(similar)
  end
end
```

### VSM Cross-Subsystem Communication

The HNSW index enables rich information flow between all VSM subsystems through S4's pattern recognition capabilities:

```elixir
defmodule VSMIntegration do
  @doc """
  Complete VSM integration showing how HNSW connects all subsystems through S4
  """
  def full_vsm_pattern_flow do
    # 1. S1 Operations generate behavioral patterns
    s1_pattern = %{
      type: :operational_behavior,
      source: :s1_manufacturing_line,
      metrics: %{
        efficiency: 0.85,
        error_rate: 0.02,
        throughput: 1200,
        quality_score: 0.94
      },
      timestamp: DateTime.utc_now()
    }
    
    # Encode operational metrics as vector
    s1_vector = OperationalEncoder.encode(s1_pattern.metrics)
    
    # 2. S2 detects coordination conflicts that need indexing
    s2_pattern = %{
      type: :coordination_conflict,
      source: :s2_conflict_detector,
      conflict_data: %{
        subsystems: [:warehouse, :shipping],
        severity: :medium,
        conflict_type: :resource_contention,
        resolution_time: 45 # minutes
      }
    }
    
    s2_vector = ConflictEncoder.encode(s2_pattern.conflict_data)
    
    # 3. S3 identifies resource bottlenecks as patterns
    s3_pattern = %{
      type: :resource_constraint,
      source: :s3_resource_monitor,
      constraint_data: %{
        resource: :cpu_capacity,
        utilization: 0.92,
        queue_length: 150,
        wait_time: 30 # seconds
      }
    }
    
    s3_vector = ResourceEncoder.encode(s3_pattern.constraint_data)
    
    # 4. S4 indexes all patterns with cross-subsystem context
    patterns = [
      {s1_vector, s1_pattern},
      {s2_vector, s2_pattern},
      {s3_vector, s3_pattern}
    ]
    
    indexed_patterns = patterns
    |> Enum.map(fn {vector, pattern} ->
      # Enrich each pattern with VSM-wide context
      enriched_metadata = Map.merge(pattern, %{
        vsm_context: %{
          s1_state: get_operational_state(),      # Current operational health
          s2_conflicts: get_active_conflicts(),   # Active coordination issues
          s3_resources: get_resource_allocation(),# Resource distribution
          s4_patterns: get_recent_patterns(),     # Recent environmental patterns
          s5_policies: get_active_policies()      # Current policy constraints
        },
        indexed_at: DateTime.utc_now()
      })
      
      {:ok, id} = HNSWIndex.insert(@index, vector, enriched_metadata)
      {id, pattern, enriched_metadata}
    end)
    
    # 5. S4 finds cross-subsystem patterns and correlations
    systemic_insights = analyze_systemic_patterns(indexed_patterns)
    
    # 6. S5 receives pattern insights for policy adaptation
    policy_recommendations = generate_policy_insights(systemic_insights)
    S5.Policy.evaluate_adaptations(policy_recommendations)
    
    # Return complete analysis
    %{
      patterns_indexed: length(indexed_patterns),
      systemic_insights: systemic_insights,
      policy_recommendations: policy_recommendations,
      cross_subsystem_correlations: find_correlations(indexed_patterns)
    }
  end
  
  @doc """
  Analyze patterns across subsystems to find systemic issues
  """
  defp analyze_systemic_patterns(indexed_patterns) do
    # Group patterns by type
    by_type = Enum.group_by(indexed_patterns, fn {_, pattern, _} -> 
      pattern.type 
    end)
    
    # Find temporal correlations
    temporal_clusters = find_temporal_clusters(indexed_patterns)
    
    # Identify recurring pattern sequences
    sequences = detect_pattern_sequences(indexed_patterns)
    
    %{
      operational_efficiency_trend: analyze_s1_trend(by_type[:operational_behavior]),
      conflict_patterns: analyze_s2_patterns(by_type[:coordination_conflict]),
      resource_bottlenecks: analyze_s3_constraints(by_type[:resource_constraint]),
      temporal_correlations: temporal_clusters,
      causal_sequences: sequences,
      system_health_score: calculate_system_health(indexed_patterns)
    }
  end
  
  @doc """
  Generate policy recommendations based on pattern analysis
  """
  defp generate_policy_insights(systemic_insights) do
    recommendations = []
    
    # Check for efficiency degradation
    if systemic_insights.operational_efficiency_trend < -0.05 do
      recommendations ++ [%{
        type: :policy_adjustment,
        urgency: :high,
        recommendation: "Relax quality constraints to improve throughput",
        expected_impact: "15% throughput increase",
        risk: "2% quality decrease"
      }]
    end
    
    # Check for repeated conflicts
    if length(systemic_insights.conflict_patterns) > 5 do
      recommendations ++ [%{
        type: :structural_change,
        urgency: :medium,
        recommendation: "Reorganize warehouse-shipping coordination",
        expected_impact: "50% conflict reduction",
        risk: "Temporary disruption during transition"
      }]
    end
    
    # Check for resource saturation
    if systemic_insights.resource_bottlenecks[:severity] == :critical do
      recommendations ++ [%{
        type: :capacity_expansion,
        urgency: :critical,
        recommendation: "Immediate resource scaling required",
        expected_impact: "System stability restoration",
        risk: "Increased operational costs"
      }]
    end
    
    recommendations
  end
  
  @doc """
  Find correlations between patterns from different subsystems
  """
  defp find_correlations(indexed_patterns) do
    # Use HNSW to find similar patterns across subsystems
    correlations = indexed_patterns
    |> Enum.flat_map(fn {id, pattern, metadata} ->
      # Search for similar patterns from other subsystems
      {:ok, similar} = HNSWIndex.search(@index, metadata.vector, k: 10)
      
      similar
      |> Enum.filter(fn {_, _, _, meta} -> 
        meta.source != pattern.source  # Different subsystem
      end)
      |> Enum.map(fn {distance, _, _, meta} ->
        %{
          pattern_a: pattern.type,
          pattern_b: meta.type,
          correlation_strength: 1.0 - distance,
          time_lag: DateTime.diff(meta.timestamp, pattern.timestamp, :second),
          subsystems: [pattern.source, meta.source]
        }
      end)
    end)
    |> Enum.filter(fn corr -> corr.correlation_strength > 0.7 end)
    |> Enum.uniq_by(fn corr -> 
      Enum.sort([corr.pattern_a, corr.pattern_b])
    end)
    
    correlations
  end
end
```

### Enhanced S5 Policy Adaptation Based on S4 Pattern Analysis

The HNSW index enables sophisticated policy adaptations by analyzing patterns across all VSM subsystems:

```elixir
defmodule S5PolicyAdapter do
  @moduledoc """
  S5 Policy adaptation based on S4 pattern analysis using HNSW insights.
  Shows how pattern recognition drives system-wide policy changes.
  """
  
  @doc """
  Adapt policies based on detected pattern trends
  """
  def adapt_from_patterns(pattern_insights) do
    # Analyze different aspects of pattern insights
    conflict_policy = analyze_conflict_patterns(pattern_insights)
    resource_policy = analyze_resource_patterns(pattern_insights)
    efficiency_policy = analyze_efficiency_patterns(pattern_insights)
    emergence_policy = analyze_emergent_behaviors(pattern_insights)
    
    # Combine and prioritize policy adaptations
    [conflict_policy, resource_policy, efficiency_policy, emergence_policy]
    |> Enum.filter(& &1)
    |> prioritize_policies()
  end
  
  defp analyze_conflict_patterns(insights) do
    conflict_freq = insights.conflict_frequency
    conflict_severity = insights.avg_conflict_severity
    
    cond do
      conflict_freq > 0.3 and conflict_severity == :high ->
        %Policy{
          type: :coordination_reform,
          urgency: :critical,
          description: "Major restructuring of S2 coordination protocols",
          parameters: %{
            conflict_threshold: 0.05,  # Much stricter
            mediation_timeout: 15,     # Faster resolution
            escalation_path: :direct_to_s5,
            structural_changes: [
              :merge_conflicting_departments,
              :introduce_liaison_roles,
              :implement_shared_kpis
            ]
          },
          expected_outcomes: %{
            conflict_reduction: "70-80%",
            implementation_time: "30 days",
            disruption_level: :high
          }
        }
      
      conflict_freq > 0.2 ->
        %Policy{
          type: :coordination_optimization,
          urgency: :high,
          description: "Enhance coordination mechanisms",
          parameters: %{
            conflict_threshold: 0.1,
            mediation_timeout: 30,
            buffer_resources: "10%",
            communication_frequency: :hourly
          },
          expected_outcomes: %{
            conflict_reduction: "40-50%",
            implementation_time: "14 days",
            disruption_level: :medium
          }
        }
      
      true -> nil
    end
  end
  
  defp analyze_resource_patterns(insights) do
    saturation = insights.resource_saturation
    volatility = insights.resource_volatility
    bottleneck_count = length(insights.resource_bottlenecks)
    
    cond do
      saturation > 0.9 and volatility > 0.3 ->
        %Policy{
          type: :dynamic_capacity_management,
          urgency: :critical,
          description: "Implement elastic resource scaling",
          parameters: %{
            scale_factor: 2.0,
            auto_scaling: true,
            predictive_scaling: true,
            burst_capacity: "50%",
            cost_optimization: false  # Stability over cost
          },
          triggers: %{
            scale_up: "utilization > 0.7 for 5 minutes",
            scale_down: "utilization < 0.3 for 30 minutes",
            emergency_burst: "queue_length > 1000"
          }
        }
      
      saturation > 0.8 ->
        %Policy{
          type: :capacity_expansion,
          urgency: :high,
          description: "Permanent capacity increase",
          parameters: %{
            scale_factor: 1.5,
            budget_override: true,
            implementation_phases: 3,
            resource_types: [:compute, :memory, :network]
          }
        }
      
      bottleneck_count > 3 ->
        %Policy{
          type: :bottleneck_elimination,
          urgency: :medium,
          description: "Targeted bottleneck resolution",
          parameters: %{
            parallel_processing: true,
            queue_redistribution: true,
            priority_lanes: 3,
            bypass_mechanisms: true
          }
        }
      
      true -> nil
    end
  end
  
  defp analyze_efficiency_patterns(insights) do
    efficiency_trend = insights.operational_efficiency_trend
    quality_trend = insights.quality_trend
    
    cond do
      efficiency_trend < -0.1 and quality_trend < -0.05 ->
        %Policy{
          type: :operational_overhaul,
          urgency: :critical,
          description: "Complete operational redesign required",
          parameters: %{
            automation_level: :high,
            process_reengineering: true,
            training_program: :mandatory,
            technology_refresh: true,
            lean_implementation: true
          },
          phases: [
            %{phase: 1, duration: "30 days", focus: :assessment},
            %{phase: 2, duration: "60 days", focus: :implementation},
            %{phase: 3, duration: "30 days", focus: :optimization}
          ]
        }
      
      efficiency_trend < -0.05 ->
        %Policy{
          type: :efficiency_improvement,
          urgency: :high,
          description: "Targeted efficiency enhancements",
          parameters: %{
            optimization_targets: [:throughput, :latency, :error_rate],
            acceptable_quality_impact: "2%",
            automation_opportunities: :identify_and_implement,
            process_streamlining: true
          }
        }
      
      true -> nil
    end
  end
  
  defp analyze_emergent_behaviors(insights) do
    # Detect unexpected patterns that don't fit normal categories
    unknown_patterns = insights.unclassified_pattern_ratio
    pattern_volatility = insights.pattern_stability_score
    
    cond do
      unknown_patterns > 0.15 ->
        %Policy{
          type: :exploratory_adaptation,
          urgency: :medium,
          description: "System exhibiting unknown emergent behaviors",
          parameters: %{
            monitoring_intensity: :maximum,
            experimentation_budget: "5%",
            sandbox_environment: true,
            pattern_analysis_depth: :deep,
            human_oversight: :required
          },
          investigation_areas: [
            :cross_subsystem_feedback_loops,
            :nonlinear_interactions,
            :self_organization_tendencies,
            :complexity_emergence
          ]
        }
      
      pattern_volatility < 0.3 ->
        %Policy{
          type: :stability_threat,
          urgency: :high,
          description: "System patterns becoming chaotic",
          parameters: %{
            damping_factor: 0.8,
            feedback_loop_breakers: true,
            stability_injection: :periodic,
            variance_reduction: :aggressive
          }
        }
      
      true -> nil
    end
  end
  
  defp prioritize_policies(policies) do
    policies
    |> Enum.sort_by(fn policy ->
      case policy.urgency do
        :critical -> 1
        :high -> 2
        :medium -> 3
        :low -> 4
      end
    end)
    |> apply_policy_interactions()
  end
  
  defp apply_policy_interactions(policies) do
    # Detect and resolve policy conflicts
    policies
    |> Enum.reduce([], fn policy, acc ->
      if conflicts_with_existing?(policy, acc) do
        resolve_conflict(policy, acc)
      else
        [policy | acc]
      end
    end)
    |> Enum.reverse()
  end
  
  @doc """
  Real-time policy effectiveness monitoring using HNSW patterns
  """
  def monitor_policy_effectiveness(active_policy, index) do
    # Get baseline patterns before policy
    baseline_vector = encode_system_state(:pre_policy)
    
    # Get current patterns after policy implementation
    current_vector = encode_system_state(:current)
    
    # Find similar historical situations
    {:ok, similar_situations} = HNSWIndex.search(index, current_vector, k: 10)
    
    # Analyze outcomes of similar situations
    outcomes = similar_situations
    |> Enum.map(fn {_, _, _, meta} -> 
      %{
        outcome: meta.outcome,
        policy_type: meta.applied_policy,
        effectiveness: meta.effectiveness_score,
        side_effects: meta.side_effects
      }
    end)
    
    # Calculate policy effectiveness
    %{
      predicted_success_rate: calculate_success_rate(outcomes),
      similar_policies_tried: count_similar_policies(outcomes, active_policy),
      average_effectiveness: average_effectiveness(outcomes),
      common_side_effects: identify_common_side_effects(outcomes),
      recommendation: generate_recommendation(outcomes, active_policy)
    }
  end
  
  defp generate_recommendation(outcomes, active_policy) do
    success_rate = calculate_success_rate(outcomes)
    
    cond do
      success_rate > 0.8 ->
        {:continue, "Policy showing strong positive outcomes"}
      
      success_rate > 0.6 ->
        {:adjust, "Minor adjustments recommended", suggest_adjustments(outcomes)}
      
      success_rate > 0.4 ->
        {:reconsider, "Policy effectiveness questionable", alternative_policies(outcomes)}
      
      true ->
        {:abort, "Policy likely to fail", rollback_plan(active_policy)}
    end
  end
end
```

### VSM Cognitive Loop
The HNSW index serves as the pattern memory for S4's contribution to system-wide cognition:

```elixir
defmodule CognitiveIntegration do
  def cognitive_cycle(state) do
    # 1. Encode current state as vector
    state_vector = StateEncoder.encode(state)
    
    # 2. Retrieve similar past states
    {:ok, similar_states} = HNSWIndex.search(
      state.pattern_index, 
      state_vector, 
      k: 10
    )
    
    # 3. Extract successful action patterns
    successful_patterns = similar_states
    |> Enum.filter(fn {_, _, _, meta} -> meta.outcome == :success end)
    |> Enum.map(fn {_, _, _, meta} -> meta.action_sequence end)
    
    # 4. Synthesize new response
    synthesize_response(successful_patterns, state)
  end
end
```

## Advanced Usage

### Custom Distance Metrics
```elixir
defmodule CustomMetrics do
  def weighted_cosine(v1, v2, weights) do
    # Apply feature weights before cosine similarity
    weighted_v1 = Enum.zip(v1, weights) |> Enum.map(fn {v, w} -> v * w end)
    weighted_v2 = Enum.zip(v2, weights) |> Enum.map(fn {v, w} -> v * w end)
    
    HNSWIndex.cosine_distance(weighted_v1, weighted_v2)
  end
end

# Use custom metric
{:ok, index} = HNSWIndex.start_link(
  distance_fn: &CustomMetrics.weighted_cosine/3,
  distance_fn_args: [feature_weights]
)
```

### Index Maintenance
```elixir
# Remove old patterns
PatternIndexer.prune_before(~U[2024-01-01 00:00:00Z])

# Rebalance index after many deletions
{:ok, stats} = HNSWIndex.rebalance(index)

# Analyze index quality
{:ok, report} = HNSWIndex.analyze(index)
# Returns connectivity stats, layer distribution, etc.
```

## Implementation Details

### Graph Structure
- **Nodes**: Each vector is a node with metadata
- **Edges**: Bidirectional links between similar vectors
- **Layers**: Hierarchical organization for efficient navigation

### Concurrency Model
- **GenServer**: Single writer, multiple concurrent readers
- **ETS Tables**: Lock-free read operations
- **Batching**: Amortize lock contention for bulk operations

### Persistence Format
```elixir
%{
  version: 2,
  parameters: %{m: 16, ef_construction: 200, ...},
  nodes: %{
    node_id => %{
      vector: [...],
      metadata: %{...},
      layer: 2,
      neighbors: %{
        0 => [id1, id2, ...],  # Layer 0 neighbors
        1 => [id3, id4, ...],  # Layer 1 neighbors
        2 => [id5, id6, ...]   # Layer 2 neighbors
      }
    }
  },
  entry_point: node_id
}
```

## Testing

### Unit Tests
```bash
mix test apps/autonomous_opponent_core/test/autonomous_opponent/vsm/s4/vector_store/hnsw_index_test.exs
```

### Integration Tests
```bash
mix test apps/autonomous_opponent_core/test/autonomous_opponent/vsm/s4/hnsw_integration_test.exs
```

### Benchmarks
```bash
# Performance benchmarks (includes accuracy measurements)
mix run apps/autonomous_opponent_core/test/autonomous_opponent/vsm/s4/vector_store/hnsw_index_benchmark.exs

# Run with benchmarking enabled
RUN_BENCHMARKS=true mix run apps/autonomous_opponent_core/test/autonomous_opponent/vsm/s4/vector_store/hnsw_index_benchmark.exs
```

## Common Pitfalls and How to Avoid Them

### 1. **Not Normalizing Vectors for Cosine Distance**
```elixir
# ❌ Wrong - unnormalized vectors with cosine distance
vector = [1.0, 2.0, 3.0]
HNSWIndex.insert(index, vector, metadata)  # Cosine expects normalized vectors!

# ✅ Correct - normalized vectors
magnitude = :math.sqrt(Enum.sum(Enum.map(vector, & &1 * &1)))
normalized = Enum.map(vector, & &1 / magnitude)
HNSWIndex.insert(index, normalized, metadata)

# Alternative: Use euclidean distance for unnormalized vectors
{:ok, index} = HNSWIndex.start_link(distance_metric: :euclidean)
```

### 2. **Using Wrong ef Parameter Values**
```elixir
# ❌ Wrong - same ef for construction and search
{:ok, index} = HNSWIndex.start_link(
  ef_construction: 50,  # Too low for quality index
  ef: 50               # Same value is inefficient
)

# ✅ Correct - higher ef_construction for quality, tuned ef for search
{:ok, index} = HNSWIndex.start_link(
  ef_construction: 200,  # Higher for better graph quality
  ef: 100               # Lower for faster searches
)

# Search-time tuning
HNSWIndex.search(index, query, k: 10, ef: 200)  # Override for high-recall query
```

### 3. **Ignoring Memory Growth**
```elixir
# ❌ Wrong - unbounded growth leads to OOM
defmodule NaiveIndexer do
  def index_patterns(patterns) do
    Enum.each(patterns, fn pattern ->
      HNSWIndex.insert(@index, pattern.vector, pattern.metadata)
    end)
  end
end

# ✅ Correct - implement retention policy
defmodule SmartIndexer do
  @max_patterns 1_000_000
  @retention_days 90
  
  def index_pattern(pattern) do
    # Check capacity before insert
    stats = HNSWIndex.stats(@index)
    
    if stats.vector_count >= @max_patterns do
      # Prune old patterns first
      {:ok, pruned} = HNSWIndex.prune_old_patterns(
        @index, 
        max_age: :timer.days(@retention_days)
      )
      Logger.info("Pruned #{pruned} old patterns")
    end
    
    HNSWIndex.insert(@index, pattern.vector, pattern.metadata)
  end
end
```

### 4. **Mismatched M Parameter for Use Case**
```elixir
# ❌ Wrong - M too low for high-accuracy needs
{:ok, index} = HNSWIndex.start_link(m: 4)  # Poor connectivity

# ❌ Wrong - M too high for real-time needs  
{:ok, index} = HNSWIndex.start_link(m: 64)  # Slow inserts

# ✅ Correct - M matched to requirements
# For S4 real-time pattern matching (balanced):
{:ok, index} = HNSWIndex.start_link(m: 16)

# For offline analysis (high accuracy):
{:ok, index} = HNSWIndex.start_link(m: 32)

# For high-speed streaming (low latency):
{:ok, index} = HNSWIndex.start_link(m: 8)
```

### 5. **Not Handling Vector Validation**
```elixir
# ❌ Wrong - inserting invalid vectors corrupts index
invalid_vector = [1.0, nil, "NaN", 3.0]
HNSWIndex.insert(index, invalid_vector, metadata)  # Crashes!

# ✅ Correct - validate before insertion
defmodule VectorValidator do
  def validate_and_insert(index, vector, metadata) do
    cond do
      not is_list(vector) ->
        {:error, :not_a_list}
      
      not Enum.all?(vector, &is_number/1) ->
        {:error, :non_numeric_values}
      
      Enum.any?(vector, &(&1 != &1)) ->  # NaN check
        {:error, :contains_nan}
      
      Enum.all?(vector, &(&1 == 0)) ->
        {:error, :zero_vector}
      
      true ->
        HNSWIndex.insert(index, vector, metadata)
    end
  end
end
```

### 6. **Incorrect Persistence Strategy**
```elixir
# ❌ Wrong - saving too frequently
defmodule FrequentSaver do
  def handle_info(:save, state) do
    HNSWIndex.save(state.index, state.path)  # Every insert!
    Process.send_after(self(), :save, 1_000)  # Too frequent
    {:noreply, state}
  end
end

# ✅ Correct - balanced persistence
defmodule SmartPersistence do
  @save_interval :timer.minutes(30)
  @save_threshold 10_000  # Save after N changes
  
  def handle_info(:periodic_save, state) do
    if state.changes_since_save > @save_threshold do
      Task.start(fn ->
        HNSWIndex.save(state.index, state.path)
      end)
      
      Process.send_after(self(), :periodic_save, @save_interval)
      {:noreply, %{state | changes_since_save: 0}}
    else
      Process.send_after(self(), :periodic_save, @save_interval)
      {:noreply, state}
    end
  end
end
```

### 7. **Not Monitoring Index Health**
```elixir
# ❌ Wrong - no visibility into index degradation
# Just inserting blindly...

# ✅ Correct - proactive health monitoring
defmodule IndexHealthMonitor do
  use GenServer
  
  @check_interval :timer.minutes(5)
  
  def init(index) do
    schedule_health_check()
    {:ok, %{index: index, history: []}}
  end
  
  def handle_info(:health_check, state) do
    health = assess_index_health(state.index)
    
    if health.recall < 0.85 do
      Logger.warn("Index recall degraded to #{health.recall}")
      maybe_trigger_rebalance(state.index)
    end
    
    if health.avg_degree > 5 * health.m do
      Logger.warn("Hub formation detected")
      trigger_compaction(state.index)
    end
    
    schedule_health_check()
    {:noreply, %{state | history: [health | state.history]}}
  end
  
  defp assess_index_health(index) do
    stats = HNSWIndex.stats(index)
    sample_recalls = measure_sample_recalls(index)
    
    %{
      recall: Enum.sum(sample_recalls) / length(sample_recalls),
      avg_degree: stats.total_edges / stats.vector_count,
      m: stats.parameters.m,
      memory_per_vector: stats.memory_bytes / stats.vector_count
    }
  end
end
```

## Troubleshooting

### Common Issues

1. **High Memory Usage**
   - Reduce M parameter
   - Use dimensionality reduction on vectors
   - Enable periodic pruning of old patterns

2. **Poor Recall**
   - Increase ef parameter during search
   - Increase ef_construction during building
   - Verify distance metric matches data distribution

3. **Slow Inserts**
   - Use batch_insert for multiple vectors
   - Reduce ef_construction parameter
   - Consider sharding large indices

4. **Index Corruption**
   - Always use supervised shutdown
   - Enable write-ahead logging
   - Keep backup of critical indices

## Data Migration Guide

### From PostgreSQL pgvector

```elixir
defmodule Migration.FromPgvector do
  import Ecto.Query
  
  def migrate(repo, target_index, options \\ []) do
    batch_size = Keyword.get(options, :batch_size, 1000)
    table_name = Keyword.get(options, :table, "vector_embeddings")
    
    # Stream vectors from PostgreSQL
    query = from(v in table_name, select: %{
      id: v.id,
      embedding: v.embedding,
      metadata: v.metadata,
      created_at: v.inserted_at
    })
    
    # Process in batches to avoid memory issues
    repo.stream(query, max_rows: batch_size)
    |> Stream.chunk_every(100)
    |> Stream.each(fn batch ->
      vectors_with_metadata = Enum.map(batch, fn row ->
        # pgvector returns arrays, ensure it's a list
        vector = if is_list(row.embedding), do: row.embedding, else: Tuple.to_list(row.embedding)
        
        metadata = Map.merge(row.metadata || %{}, %{
          original_id: row.id,
          migrated_from: "pgvector",
          migrated_at: DateTime.utc_now(),
          original_created_at: row.created_at
        })
        
        {vector, metadata}
      end)
      
      # Batch insert into HNSW
      case HNSWIndex.batch_insert(target_index, vectors_with_metadata) do
        {:ok, _ids} -> :ok
        {:error, reason} -> 
          Logger.error("Batch insert failed: #{inspect(reason)}")
      end
      
      # Let the index settle between batches
      Process.sleep(100)
    end)
    |> Stream.run()
    
    # Verify migration
    stats = HNSWIndex.stats(target_index)
    Logger.info("Migration complete: #{stats.vector_count} vectors indexed")
  end
end

# Usage example
{:ok, index} = HNSWIndex.start_link(m: 16, ef: 200, distance_metric: :cosine)
Migration.FromPgvector.migrate(Repo, index, batch_size: 500)
```

### From Elasticsearch

```elixir
defmodule Migration.FromElasticsearch do
  def migrate(es_client, index_name, target_index, options \\ []) do
    scroll_size = Keyword.get(options, :scroll_size, 1000)
    vector_field = Keyword.get(options, :vector_field, "embedding")
    
    # Initial search with scroll
    {:ok, %{body: initial_response}} = Elasticsearch.post(
      es_client,
      "/#{index_name}/_search?scroll=5m",
      %{
        size: scroll_size,
        _source: [vector_field, "metadata", "_id", "@timestamp"],
        query: %{match_all: %{}}
      }
    )
    
    scroll_id = initial_response["_scroll_id"]
    total_hits = get_in(initial_response, ["hits", "total", "value"])
    
    Logger.info("Migrating #{total_hits} vectors from Elasticsearch")
    
    # Process initial batch
    process_es_hits(initial_response["hits"]["hits"], vector_field, target_index)
    
    # Continue scrolling
    scroll_through_results(es_client, scroll_id, vector_field, target_index, scroll_size)
  end
  
  defp process_es_hits(hits, vector_field, target_index) do
    vectors_with_metadata = Enum.map(hits, fn hit ->
      vector = hit["_source"][vector_field]
      
      metadata = Map.merge(
        hit["_source"]["metadata"] || %{},
        %{
          es_id: hit["_id"],
          es_timestamp: hit["_source"]["@timestamp"],
          migrated_from: "elasticsearch",
          migrated_at: DateTime.utc_now()
        }
      )
      
      {vector, metadata}
    end)
    
    HNSWIndex.batch_insert(target_index, vectors_with_metadata)
  end
  
  defp scroll_through_results(es_client, scroll_id, vector_field, target_index, expected_size) do
    case Elasticsearch.post(es_client, "/_search/scroll", %{
      scroll: "5m",
      scroll_id: scroll_id
    }) do
      {:ok, %{body: %{"hits" => %{"hits" => []}}}} ->
        # No more results
        :ok
        
      {:ok, %{body: response}} ->
        hits = response["hits"]["hits"]
        process_es_hits(hits, vector_field, target_index)
        
        if length(hits) == expected_size do
          # Continue scrolling
          scroll_through_results(es_client, scroll_id, vector_field, target_index, expected_size)
        else
          :ok
        end
        
      {:error, reason} ->
        Logger.error("Scroll failed: #{inspect(reason)}")
    end
  end
end
```

### From FAISS (via Python interop)

```elixir
defmodule Migration.FromFAISS do
  @python_script """
  import faiss
  import numpy as np
  import json
  import sys
  
  def export_faiss_index(index_path, output_path, metadata_path=None):
      # Load FAISS index
      index = faiss.read_index(index_path)
      
      # Get all vectors
      vectors = []
      for i in range(index.ntotal):
          vector = index.reconstruct(i).tolist()
          vectors.append(vector)
      
      # Load metadata if available
      metadata = {}
      if metadata_path:
          with open(metadata_path, 'r') as f:
              metadata = json.load(f)
      
      # Export to JSON
      export_data = {
          'vectors': vectors,
          'metadata': metadata,
          'dimensions': index.d,
          'total': index.ntotal
      }
      
      with open(output_path, 'w') as f:
          json.dump(export_data, f)
      
      return index.ntotal
  
  if __name__ == '__main__':
      count = export_faiss_index(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
      print(f"Exported {count} vectors")
  """
  
  def migrate(faiss_index_path, target_index, options \\ []) do
    metadata_path = Keyword.get(options, :metadata_path)
    temp_export_path = "/tmp/faiss_export_#{:os.system_time(:millisecond)}.json"
    
    # Write Python script
    script_path = "/tmp/faiss_export_script.py"
    File.write!(script_path, @python_script)
    
    # Execute Python script to export FAISS data
    args = [script_path, faiss_index_path, temp_export_path]
    args = if metadata_path, do: args ++ [metadata_path], else: args
    
    case System.cmd("python3", args) do
      {output, 0} ->
        Logger.info("FAISS export: #{String.trim(output)}")
        
        # Read exported data
        {:ok, export_data} = File.read(temp_export_path)
        {:ok, data} = Jason.decode(export_data)
        
        # Process vectors
        vectors_with_metadata = data["vectors"]
        |> Enum.with_index()
        |> Enum.map(fn {vector, idx} ->
          metadata = get_in(data, ["metadata", to_string(idx)]) || %{}
          
          metadata = Map.merge(metadata, %{
            faiss_index: idx,
            migrated_from: "faiss",
            migrated_at: DateTime.utc_now()
          })
          
          {vector, metadata}
        end)
        
        # Batch insert
        vectors_with_metadata
        |> Enum.chunk_every(100)
        |> Enum.each(fn batch ->
          HNSWIndex.batch_insert(target_index, batch)
          Process.sleep(50)
        end)
        
        # Cleanup
        File.rm(temp_export_path)
        File.rm(script_path)
        
        Logger.info("Migration complete: #{length(vectors_with_metadata)} vectors")
        
      {error, _} ->
        Logger.error("FAISS export failed: #{error}")
        {:error, :export_failed}
    end
  end
end
```

### Data Validation After Migration

```elixir
defmodule Migration.Validator do
  def validate_migration(source_count, target_index, sample_size \\ 100) do
    stats = HNSWIndex.stats(target_index)
    
    # Check count
    count_match = stats.vector_count == source_count
    Logger.info("Count validation: #{stats.vector_count}/#{source_count} vectors")
    
    # Sample and verify vectors
    sample_ids = Enum.take_random(1..stats.vector_count, sample_size)
    
    validity_results = Enum.map(sample_ids, fn id ->
      case HNSWIndex.get_vector(target_index, id) do
        {:ok, vector, metadata} ->
          # Verify vector is valid
          valid_vector? = Enum.all?(vector, &is_number/1) and
                         not Enum.any?(vector, &(&1 != &1)) # No NaN
          
          # Verify metadata
          has_migration_info? = Map.has_key?(metadata, :migrated_from)
          
          valid_vector? and has_migration_info?
          
        _ -> false
      end
    end)
    
    validity_rate = Enum.count(validity_results, & &1) / length(validity_results)
    
    %{
      count_match: count_match,
      validity_rate: validity_rate,
      total_vectors: stats.vector_count,
      sample_size: sample_size,
      memory_usage: stats.memory_bytes,
      status: if(count_match and validity_rate > 0.99, do: :success, else: :partial)
    }
  end
end
```

## References

1. [Efficient and robust approximate nearest neighbor search using Hierarchical Navigable Small World graphs](https://arxiv.org/abs/1603.09320)
2. [HNSW Original Implementation](https://github.com/nmslib/hnswlib)
3. [VSM Theory and S4's Role](../../../docs/vsm_theory.md)

## Changelog

### Version 2.0 (Current)

**New Features:**
- **Telemetry Integration**: Production monitoring with :telemetry events for all operations
- **Batch Search API**: Process multiple queries in parallel for improved throughput
- **Pattern Expiry**: Automatic and manual pruning of old patterns with timestamp tracking
- **Index Compaction**: Remove orphaned nodes and optimize graph connections
- **Index Versioning**: Forward-compatible persistence with automatic migration

**Improvements:**
- Added timestamp metadata to all inserted patterns
- Enhanced error handling in batch operations
- Optimized memory usage in graph traversal
- Better connection pruning for hub prevention

**Breaking Changes:**
- Persistence format updated to v2 (automatic migration supported)
- Insert now adds :inserted_at timestamp to metadata

### Version 1.0

**Initial Implementation:**
- Pure Elixir HNSW algorithm
- Cosine and Euclidean distance metrics
- Incremental index building
- ETS-based persistence
- S4 integration via PatternIndexer
- GenServer architecture for concurrent operations

## Version Migration Path

### Automatic Version Migration

The HNSW index automatically handles version upgrades when loading persisted indices:

```elixir
# Loading a v1 index automatically migrates to v2
{:ok, index} = HNSWIndex.load("/path/to/v1_index.hnsw")
# The index is now using v2 format with all new features
```

### What Happens During Migration

#### V1 to V2 Migration
When loading a v1 index, the system automatically:

1. **Adds Timestamp Metadata**: All existing patterns receive a migration timestamp
2. **Enables New Features**: Feature flags are added for telemetry, pruning, and batch operations
3. **Preserves Compatibility**: V1 API calls continue to work without modification

```elixir
# V1 pattern structure (before migration)
%{
  vector: [0.1, 0.2, 0.3, ...],
  metadata: %{
    source: "sensor_1",
    pattern_type: "environmental"
  }
}

# V2 pattern structure (after automatic migration)
%{
  vector: [0.1, 0.2, 0.3, ...],
  metadata: %{
    # Original metadata preserved
    source: "sensor_1",
    pattern_type: "environmental",
    
    # New v2 fields added
    inserted_at: ~U[2024-01-15 10:00:00Z],  # Migration timestamp
    version: 2,                              # Index version
    features: [:telemetry, :pruning, :batch_search]  # Available features
  }
}
```

### Manual Migration for Custom Scenarios

If you need more control over the migration process:

```elixir
defmodule HNSWMigration do
  @doc """
  Manually migrate v1 index to v2 with custom processing
  """
  def migrate_with_enrichment(v1_path, v2_path, enrichment_fn) do
    # Load v1 index
    {:ok, old_index} = HNSWIndex.load(v1_path, version: 1)
    
    # Create new v2 index
    {:ok, new_index} = HNSWIndex.start_link(
      m: old_index.parameters.m,
      ef: old_index.parameters.ef,
      version: 2
    )
    
    # Migrate patterns with custom enrichment
    old_index
    |> HNSWIndex.all_patterns()
    |> Enum.each(fn {vector, metadata} ->
      # Apply custom enrichment
      enriched_metadata = enrichment_fn.(metadata)
      
      # Add v2 required fields
      v2_metadata = Map.merge(enriched_metadata, %{
        inserted_at: metadata[:timestamp] || DateTime.utc_now(),
        migrated_at: DateTime.utc_now(),
        original_version: 1
      })
      
      HNSWIndex.insert(new_index, vector, v2_metadata)
    end)
    
    # Save v2 index
    HNSWIndex.save(new_index, v2_path)
  end
  
  @doc """
  Verify migration completeness
  """
  def verify_migration(v1_path, v2_path) do
    {:ok, v1_stats} = get_index_stats(v1_path)
    {:ok, v2_stats} = get_index_stats(v2_path)
    
    %{
      vector_count_match: v1_stats.count == v2_stats.count,
      v1_count: v1_stats.count,
      v2_count: v2_stats.count,
      metadata_enriched: v2_stats.has_timestamps,
      version: v2_stats.version,
      status: if(v1_stats.count == v2_stats.count, do: :success, else: :partial)
    }
  end
end
```

### Future Version Planning

#### Version 3.0 (Planned)
Expected changes that will require migration:
- Compressed vector storage (50% space reduction)
- Multiple distance metric support per index
- Distributed sharding metadata

#### Migration Best Practices

1. **Always Backup Before Migration**
   ```bash
   cp /prod/index.hnsw /backup/index.hnsw.$(date +%Y%m%d)
   ```

2. **Test Migration in Staging**
   ```elixir
   # Run migration on copy first
   HNSWMigration.migrate_with_enrichment(
     "/staging/index_copy.hnsw",
     "/staging/index_v2.hnsw",
     &add_staging_metadata/1
   )
   ```

3. **Verify Post-Migration**
   ```elixir
   # Ensure recall and performance are maintained
   {:ok, validation} = HNSWMigration.verify_migration(old_path, new_path)
   if validation.status == :success do
     deploy_new_index()
   end
   ```

### Downgrade Path

While not recommended, downgrading is possible:

```elixir
defmodule HNSWDowngrade do
  def v2_to_v1(v2_path, v1_path) do
    {:ok, v2_index} = HNSWIndex.load(v2_path)
    
    # Create v1 format index
    v1_data = %{
      version: 1,
      nodes: Map.new(v2_index.nodes, fn {id, node} ->
        # Strip v2-specific metadata
        v1_metadata = Map.drop(node.metadata, [
          :inserted_at, :version, :features, :migrated_at
        ])
        
        {id, %{node | metadata: v1_metadata}}
      end),
      parameters: Map.take(v2_index.parameters, [:m, :ef, :distance_metric])
    }
    
    File.write!(v1_path, :erlang.term_to_binary(v1_data))
  end
end
```

**Note**: Downgrading loses v2 features like timestamps and telemetry data.

## Production Deployment Checklist

### Pre-Deployment Validation

- [ ] **Memory Requirements**
  - Calculate expected memory usage: `vectors × (dimensions × 4 + M × 8 + metadata_size)`
  - Ensure system has 2x required memory for safety margin
  - Configure VM memory limits: `+hms 8192 +hmbs 8192` (8GB example)

- [ ] **Persistence Configuration**
  - Verify persistence directory has sufficient disk space (3x index size)
  - Set appropriate file permissions for index storage
  - Configure automated backups: `0 */4 * * * cp /var/lib/hnsw/*.hnsw /backup/`

- [ ] **Performance Tuning**
  - Run benchmarks with production data samples
  - Adjust M and ef parameters based on recall/speed requirements
  - Test with expected concurrent load

### Deployment Steps

- [ ] **Initial Deployment**
  ```elixir
  # config/prod.exs
  config :autonomous_opponent, :hnsw_index,
    m: 16,
    ef_construction: 200,
    ef: 100,
    persist_path: "/var/lib/autonomous_opponent/s4_patterns.hnsw",
    max_elements: 10_000_000,
    auto_save_interval: :timer.minutes(30),
    prune_interval: :timer.hours(24),
    max_age_days: 90
  ```

- [ ] **Migration Strategy** (if replacing existing system)
  1. Deploy HNSW in shadow mode (index but don't serve)
  2. Run migration scripts to populate index
  3. Validate migration completeness
  4. Switch traffic to HNSW gradually
  5. Monitor performance metrics

### Monitoring Setup

- [ ] **Telemetry Configuration**
  ```elixir
  # Set up telemetry handlers
  :telemetry.attach(
    "hnsw-metrics",
    [:hnsw, :search],
    &MyApp.Telemetry.handle_hnsw_metrics/4,
    nil
  )
  ```

- [ ] **Key Metrics to Monitor**
  - Search latency: p50, p95, p99
  - Insert throughput
  - Memory usage growth rate
  - Index size (vector count)
  - Recall accuracy (sample testing)

- [ ] **Alerting Rules**
  ```yaml
  alerts:
    - name: HNSWHighSearchLatency
      expr: hnsw_search_duration_p99 > 50
      for: 5m
      annotations:
        summary: "HNSW search latency above 50ms"
    
    - name: HNSWMemoryPressure
      expr: hnsw_memory_usage_bytes / node_memory_total > 0.8
      for: 10m
      annotations:
        summary: "HNSW using >80% of system memory"
    
    - name: HNSWLowRecall
      expr: hnsw_recall_rate < 0.9
      for: 15m
      annotations:
        summary: "HNSW recall dropped below 90%"
  ```

- [ ] **Monitoring Dashboard Examples**

  Configure Grafana dashboards with these key queries:

  ```sql
  -- Search latency percentiles (Prometheus)
  histogram_quantile(0.99, 
    sum(rate(hnsw_search_duration_bucket[5m])) by (le)
  )

  -- Insert throughput
  rate(hnsw_insert_total[5m])

  -- Memory growth rate
  deriv(hnsw_memory_usage_bytes[1h])

  -- Index size over time
  hnsw_vector_count

  -- Search success rate
  rate(hnsw_search_success[5m]) / 
  (rate(hnsw_search_success[5m]) + rate(hnsw_search_failure[5m]))
  ```

  **Grafana Panel Configuration**:
  ```json
  {
    "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
    "targets": [{
      "expr": "histogram_quantile(0.99, sum(rate(hnsw_search_duration_bucket[5m])) by (le))",
      "legendFormat": "p99 search latency",
      "refId": "A"
    }],
    "title": "HNSW Search Latency",
    "type": "graph",
    "yaxes": [{"format": "ms", "label": "Latency"}]
  }
  ```

  **Key Dashboard Panels**:
  1. **Performance Overview**: Search/Insert latency heatmap
  2. **Resource Usage**: Memory and CPU utilization
  3. **Index Health**: Vector count, layer distribution, connectivity
  4. **Error Rates**: Failed operations by type
  5. **S4 Integration**: Pattern detection rate, scan cycle timing

### Operational Procedures

- [ ] **Backup Strategy**
  ```bash
  #!/bin/bash
  # backup_hnsw.sh
  BACKUP_DIR="/backup/hnsw/$(date +%Y%m%d)"
  mkdir -p $BACKUP_DIR
  
  # Atomic backup via hardlink
  cp -al /var/lib/autonomous_opponent/*.hnsw $BACKUP_DIR/
  
  # Compress older backups
  find /backup/hnsw -type d -mtime +7 -exec tar -czf {}.tar.gz {} \;
  
  # Remove old uncompressed backups
  find /backup/hnsw -type d -mtime +7 -exec rm -rf {} \;
  ```

- [ ] **Recovery Procedures**
  1. Stop application: `systemctl stop autonomous-opponent`
  2. Restore index: `cp /backup/hnsw/20240115/*.hnsw /var/lib/autonomous_opponent/`
  3. Verify index integrity: `mix run scripts/verify_index.exs`
  4. Start application: `systemctl start autonomous-opponent`

- [ ] **Capacity Planning**
  - Monitor vector count growth rate
  - Project when current resources will be exhausted
  - Plan for index sharding at 50M vectors
  - Consider read replicas for high query load

### Health Checks

- [ ] **Automated Health Verification**
  ```elixir
  defmodule HNSWHealthCheck do
    def check do
      # Verify index is responsive
      test_vector = :rand.uniform() |> List.duplicate(128)
      case HNSWIndex.search(:s4_pattern_index, test_vector, k: 1) do
        {:ok, _} -> :ok
        _ -> {:error, :index_unresponsive}
      end
      
      # Check memory usage
      stats = HNSWIndex.stats(:s4_pattern_index)
      if stats.memory_bytes > @memory_limit do
        {:error, :memory_exceeded}
      else
        :ok
      end
    end
  end
  ```

- [ ] **Manual Verification Steps**
  1. Check process info: `:erlang.process_info(pid, :memory)`
  2. Verify ETS tables: `:ets.info(:hnsw_index_table)`
  3. Test sample queries with known results
  4. Review telemetry dashboards

### Post-Deployment Validation

- [ ] **Performance Validation**
  - Run production workload simulation
  - Verify latency meets SLAs
  - Check resource utilization is within limits

- [ ] **Integration Testing**
  - Verify S4 scanner integration
  - Test pattern detection pipeline
  - Validate VSM cross-subsystem communication

- [ ] **Rollback Plan**
  - Keep previous system available for 48 hours
  - Document rollback procedure
  - Test rollback in staging environment

### Maintenance Schedule

- [ ] **Daily Tasks**
  - Review monitoring dashboards
  - Check for anomalous patterns
  - Verify backup completion

- [ ] **Weekly Tasks**
  - Analyze index statistics
  - Review and optimize slow queries
  - Update capacity projections

- [ ] **Monthly Tasks**
  - Run full index analysis
  - Perform compaction if needed
  - Review and update parameters based on usage patterns

## Future Enhancements

- [ ] Distributed index across multiple nodes
- [ ] GPU acceleration for distance calculations (NIF)
- [ ] Dynamic M and ef adjustment based on data characteristics
- [ ] Support for additional distance metrics (Manhattan, Hamming)
- [ ] Index merging for federated pattern learning
- [ ] Real-time index statistics dashboard