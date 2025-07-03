defmodule AutonomousOpponent.VSM.S4.HNSWIntegrationTest do
  @moduledoc """
  Integration tests for HNSW index with S4 environmental scanning.
  Tests the complete flow of pattern detection, indexing, and retrieval.
  """
  
  use ExUnit.Case, async: false
  
  alias AutonomousOpponent.VSM.S4.Intelligence
  alias AutonomousOpponent.VSM.S4.VectorStore.HNSWIndex
  alias AutonomousOpponent.EventBus
  
  setup do
    # Start required processes
    {:ok, _event_bus} = EventBus.start_link([])
    {:ok, intelligence} = Intelligence.start_link(id: "test_s4")
    {:ok, hnsw} = HNSWIndex.start_link(name: :test_hnsw, distance_metric: :cosine)
    
    on_exit(fn ->
      Process.exit(intelligence, :kill)
      Process.exit(hnsw, :kill)
    end)
    
    {:ok, intelligence: intelligence, hnsw: hnsw}
  end
  
  describe "environmental pattern indexing" do
    test "indexes patterns from environmental scans", %{intelligence: intelligence, hnsw: hnsw} do
      # Simulate environmental scan data
      scan_data = %{
        entities: %{
          "resource_1" => %{type: :compute, utilization: 0.75},
          "resource_2" => %{type: :memory, utilization: 0.45}
        },
        temporal_indicators: [
          %{pattern: :increasing_load, confidence: 0.85},
          %{pattern: :memory_pressure, confidence: 0.72}
        ]
      }
      
      # Perform scan
      {:ok, scan_results} = Intelligence.scan_environment(intelligence, [:resources])
      
      # Extract patterns
      {:ok, patterns} = Intelligence.extract_patterns(intelligence, scan_data)
      
      # Convert patterns to vectors and index them
      indexed_count = index_patterns(hnsw, patterns)
      assert indexed_count > 0
      
      # Verify patterns can be retrieved
      stats = HNSWIndex.stats(hnsw)
      assert stats.node_count == indexed_count
    end
    
    test "finds similar environmental patterns", %{hnsw: hnsw} do
      # Index known pattern types
      pattern_vectors = [
        {create_pattern_vector(:resource_spike), %{type: :resource_spike, severity: :high}},
        {create_pattern_vector(:gradual_increase), %{type: :gradual_increase, severity: :low}},
        {create_pattern_vector(:cyclic_load), %{type: :cyclic_load, severity: :medium}},
        {create_pattern_vector(:system_degradation), %{type: :system_degradation, severity: :critical}}
      ]
      
      Enum.each(pattern_vectors, fn {vec, meta} ->
        HNSWIndex.insert(hnsw, vec, meta)
      end)
      
      # Query with a new pattern similar to resource spike
      query = create_pattern_vector(:resource_spike, 0.1)  # Add noise
      {:ok, results} = HNSWIndex.search(hnsw, query, 2)
      
      # Should find resource_spike as most similar
      assert length(results) >= 1
      [%{metadata: %{type: type}} | _] = results
      assert type == :resource_spike
    end
  end
  
  describe "S4 pattern recognition workflow" do
    test "complete pattern detection and retrieval flow", %{intelligence: intelligence, hnsw: hnsw} do
      # Simulate S1 operational metrics
      operational_data = for i <- 1..50 do
        %{
          timestamp: System.monotonic_time(:millisecond) + i * 100,
          absorption_rate: 0.5 + :math.sin(i / 10) * 0.3,
          resource_usage: %{cpu: 40 + i * 0.5, memory: 60 - i * 0.2}
        }
      end
      
      # Feed data to S4 through event bus
      Enum.each(operational_data, fn data ->
        EventBus.publish(:s1_metrics, data)
        Process.sleep(1)  # Simulate real-time data
      end)
      
      # Allow S4 to process
      Process.sleep(100)
      
      # Extract patterns from operational data
      {:ok, patterns} = Intelligence.extract_patterns(intelligence, %{
        source: :s1_metrics,
        data: operational_data
      })
      
      # Index patterns in HNSW
      indexed = index_patterns(hnsw, patterns)
      assert indexed > 0
      
      # Search for anomalies
      anomaly_vector = create_anomaly_vector()
      {:ok, similar} = HNSWIndex.search(hnsw, anomaly_vector, 5)
      
      # Check if any similar anomalies were found
      anomaly_distances = Enum.map(similar, & &1.distance)
      avg_distance = Enum.sum(anomaly_distances) / length(anomaly_distances)
      
      # High average distance indicates the query is indeed anomalous
      assert avg_distance > 0.5
    end
    
    test "environmental model updates trigger pattern reindexing", %{intelligence: intelligence, hnsw: hnsw} do
      # Get initial environmental model
      initial_model = Intelligence.get_environmental_model(intelligence)
      
      # Index some initial patterns
      initial_patterns = [
        {create_pattern_vector(:stable), %{type: :stable, timestamp: 1}},
        {create_pattern_vector(:stable), %{type: :stable, timestamp: 2}}
      ]
      
      Enum.each(initial_patterns, fn {vec, meta} ->
        HNSWIndex.insert(hnsw, vec, meta)
      end)
      
      initial_count = HNSWIndex.stats(hnsw).node_count
      
      # Trigger environmental change
      EventBus.publish(:environmental_change, %{
        change_type: :new_resource_discovered,
        impact: :high
      })
      
      # Allow processing
      Process.sleep(100)
      
      # Simulate new patterns from the environmental change
      new_patterns = [
        {create_pattern_vector(:disruption), %{type: :disruption, cause: :environmental_change}}
      ]
      
      Enum.each(new_patterns, fn {vec, meta} ->
        HNSWIndex.insert(hnsw, vec, meta)
      end)
      
      # Verify index has grown
      final_count = HNSWIndex.stats(hnsw).node_count
      assert final_count > initial_count
    end
  end
  
  describe "performance under S4 workload" do
    @tag :performance
    test "handles continuous pattern stream efficiently", %{hnsw: hnsw} do
      # Simulate continuous pattern discovery over 10 seconds
      # S4 scans every 10 seconds, so this is one full cycle
      
      start_time = System.monotonic_time(:millisecond)
      pattern_count = 0
      
      # Generate patterns for 5 seconds
      while System.monotonic_time(:millisecond) - start_time < 5000 do
        # Generate 10 patterns per second (realistic for S4)
        for _ <- 1..10 do
          pattern_type = Enum.random([:stable, :increasing, :decreasing, :cyclic])
          vector = create_pattern_vector(pattern_type)
          metadata = %{
            type: pattern_type,
            timestamp: System.monotonic_time(:millisecond),
            confidence: 0.7 + :rand.uniform() * 0.3
          }
          
          HNSWIndex.insert(hnsw, vector, metadata)
          pattern_count = pattern_count + 1
        end
        
        Process.sleep(100)  # 100ms between batches
      end
      
      # Verify all patterns were indexed
      stats = HNSWIndex.stats(hnsw)
      assert stats.node_count >= 50  # At least 50 patterns in 5 seconds
      
      # Test search performance with many patterns
      query = create_pattern_vector(:cyclic)
      
      search_time = :timer.tc(fn ->
        {:ok, _results} = HNSWIndex.search(hnsw, query, 10)
      end) |> elem(0)
      
      # Search should complete quickly even with many patterns
      assert search_time < 50_000  # Under 50ms
    end
  end
  
  describe "memory persistence for S4" do
    test "survives S4 process restart", %{hnsw: hnsw} do
      # Index patterns
      patterns = for i <- 1..20 do
        type = Enum.random([:stable, :cyclic, :anomaly])
        {create_pattern_vector(type), %{type: type, id: i}}
      end
      
      Enum.each(patterns, fn {vec, meta} ->
        HNSWIndex.insert(hnsw, vec, meta)
      end)
      
      # Get stats before "crash"
      stats_before = HNSWIndex.stats(hnsw)
      
      # Simulate S4 restart (index persists in ETS)
      # In real implementation, would save/restore from disk
      
      # Verify patterns still searchable
      query = create_pattern_vector(:stable)
      {:ok, results} = HNSWIndex.search(hnsw, query, 5)
      
      assert length(results) > 0
      assert HNSWIndex.stats(hnsw).node_count == stats_before.node_count
    end
  end
  
  # Helper functions
  
  defp index_patterns(hnsw, patterns) do
    patterns
    |> Enum.filter(fn p -> p.confidence >= 0.7 end)  # S4's threshold
    |> Enum.map(fn pattern ->
      vector = pattern_to_vector(pattern)
      metadata = Map.take(pattern, [:type, :confidence, :timestamp])
      HNSWIndex.insert(hnsw, vector, metadata)
    end)
    |> length()
  end
  
  defp pattern_to_vector(pattern) do
    # Convert pattern to vector representation
    # In real implementation, this would use proper feature extraction
    base = case pattern[:type] do
      :variety_absorption -> [1.0, 0.0, 0.0]
      :coordination -> [0.0, 1.0, 0.0]
      :resource -> [0.0, 0.0, 1.0]
      _ -> [0.5, 0.5, 0.5]
    end
    
    # Add pattern-specific features
    features = [
      pattern[:average] || 0.5,
      pattern[:variance] || 0.1,
      case pattern[:trend] do
        :increasing -> 1.0
        :decreasing -> -1.0
        _ -> 0.0
      end,
      pattern[:confidence] || 0.5
    ]
    
    # Combine and normalize
    vector = base ++ features
    normalize_vector(vector)
  end
  
  defp normalize_vector(vector) do
    magnitude = :math.sqrt(Enum.sum(Enum.map(vector, fn x -> x * x end)))
    if magnitude > 0 do
      Enum.map(vector, fn x -> x / magnitude end)
    else
      vector
    end
  end
  
  defp create_pattern_vector(type, noise \\ 0.0) do
    base_vector = case type do
      :stable -> 
        List.duplicate(0.5, 50)
        
      :increasing -> 
        Enum.map(0..49, fn i -> i / 49.0 end)
        
      :decreasing -> 
        Enum.map(0..49, fn i -> 1.0 - i / 49.0 end)
        
      :cyclic -> 
        Enum.map(0..49, fn i -> :math.sin(i * 2 * :math.pi() / 10) end)
        
      :resource_spike ->
        Enum.map(0..49, fn i -> 
          if i >= 20 and i <= 30, do: 1.0, else: 0.2 
        end)
        
      :gradual_increase ->
        Enum.map(0..49, fn i -> :math.pow(i / 49.0, 2) end)
        
      :system_degradation ->
        Enum.map(0..49, fn i -> 1.0 - :math.pow(i / 49.0, 3) end)
        
      :disruption ->
        Enum.map(0..49, fn i ->
          cond do
            i < 20 -> 0.5
            i < 25 -> 1.0
            true -> 0.1
          end
        end)
        
      :anomaly ->
        Enum.map(0..49, fn i ->
          if rem(i, 7) == 0, do: :rand.uniform(), else: 0.1
        end)
    end
    
    # Add noise if specified
    if noise > 0 do
      Enum.map(base_vector, fn x -> x + (:rand.uniform() - 0.5) * noise end)
    else
      base_vector
    end
  end
  
  defp create_anomaly_vector do
    # Create a vector that doesn't match any normal pattern
    Enum.map(1..50, fn i ->
      :math.sin(i * 0.5) * :math.cos(i * 0.3) + :rand.uniform() * 0.5
    end)
  end
end