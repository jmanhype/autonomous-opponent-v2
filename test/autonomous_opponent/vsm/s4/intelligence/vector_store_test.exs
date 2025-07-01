defmodule AutonomousOpponent.VSM.S4.Intelligence.VectorStoreTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponent.VSM.S4.Intelligence.VectorStore
  alias AutonomousOpponent.EventBus
  
  setup do
    {:ok, _} = EventBus.start_link()
    
    {:ok, pid} = VectorStore.start_link(
      id: "test_vector_store",
      vector_dim: 64,
      accuracy_target: 0.9
    )
    
    {:ok, pid: pid}
  end
  
  describe "pattern storage" do
    test "stores pattern and returns ID", %{pid: pid} do
      pattern = create_test_pattern(:temporal, :trend)
      
      assert {:ok, pattern_id} = VectorStore.store_pattern(pid, pattern)
      assert is_binary(pattern_id)
      assert String.length(pattern_id) == 64  # SHA256 hex
    end
    
    test "stores pattern with metadata", %{pid: pid} do
      pattern = create_test_pattern(:statistical, :distribution)
      metadata = %{source: "test", importance: :high}
      
      assert {:ok, _pattern_id} = VectorStore.store_pattern(pid, pattern, metadata)
      
      # Verify storage in stats
      stats = VectorStore.get_stats(pid)
      assert stats.patterns_stored == 1
    end
    
    test "handles multiple pattern types", %{pid: pid} do
      patterns = [
        create_test_pattern(:temporal, :trend),
        create_test_pattern(:statistical, :correlation),
        create_test_pattern(:structural, :clustering),
        create_test_pattern(:behavioral, :anomaly)
      ]
      
      pattern_ids = Enum.map(patterns, fn pattern ->
        {:ok, id} = VectorStore.store_pattern(pid, pattern)
        id
      end)
      
      # All IDs should be unique
      assert length(Enum.uniq(pattern_ids)) == 4
      
      stats = VectorStore.get_stats(pid)
      assert stats.patterns_stored == 4
    end
  end
  
  describe "similarity search" do
    setup %{pid: pid} do
      # Store various patterns for searching
      patterns = [
        create_test_pattern(:temporal, :trend, increasing: true, strength: 0.8),
        create_test_pattern(:temporal, :trend, increasing: true, strength: 0.9),
        create_test_pattern(:temporal, :trend, increasing: false, strength: 0.7),
        create_test_pattern(:statistical, :distribution, mean: 0.5, variance: 0.1),
        create_test_pattern(:statistical, :distribution, mean: 0.6, variance: 0.15)
      ]
      
      Enum.each(patterns, fn pattern ->
        VectorStore.store_pattern(pid, pattern)
      end)
      
      {:ok, stored_patterns: patterns}
    end
    
    test "finds similar patterns", %{pid: pid} do
      # Query with a temporal trend pattern
      query = create_test_pattern(:temporal, :trend, increasing: true, strength: 0.85)
      
      assert {:ok, results} = VectorStore.find_similar_patterns(pid, query, 3)
      
      assert length(results) == 3
      assert Enum.all?(results, fn result ->
        Map.has_key?(result, :pattern_id) and
        Map.has_key?(result, :pattern) and
        Map.has_key?(result, :distance)
      end)
      
      # Most similar should be other increasing trends
      top_result = hd(results)
      assert top_result.pattern.type == :temporal
      assert top_result.pattern[:direction] == :increasing
    end
    
    test "respects k parameter", %{pid: pid} do
      query = create_test_pattern(:statistical, :distribution)
      
      assert {:ok, results_2} = VectorStore.find_similar_patterns(pid, query, 2)
      assert {:ok, results_5} = VectorStore.find_similar_patterns(pid, query, 5)
      
      assert length(results_2) == 2
      assert length(results_5) == 5
    end
    
    test "returns empty list when no patterns stored" do
      {:ok, empty_store} = VectorStore.start_link(vector_dim: 64)
      query = create_test_pattern(:temporal, :trend)
      
      assert {:ok, results} = VectorStore.find_similar_patterns(empty_store, query, 10)
      assert results == []
    end
  end
  
  describe "automatic pattern extraction integration" do
    test "automatically stores patterns from events", %{pid: pid} do
      patterns = [
        create_test_pattern(:temporal, :seasonality),
        create_test_pattern(:behavioral, :sequence),
        create_test_pattern(:structural, :hierarchy)
      ]
      
      # Publish pattern extraction event
      EventBus.publish(:patterns_extracted, %{patterns: patterns})
      
      # Give time to process
      Process.sleep(100)
      
      stats = VectorStore.get_stats(pid)
      assert stats.patterns_stored == 3
    end
    
    test "trains quantizer when enough patterns accumulated", %{pid: pid} do
      # Generate 101 patterns to trigger training (threshold is 100)
      patterns = for i <- 1..101 do
        create_test_pattern(:temporal, :trend, strength: i / 100)
      end
      
      # Store them via events
      EventBus.publish(:patterns_extracted, %{patterns: patterns})
      
      # Give time to process and train
      Process.sleep(500)
      
      stats = VectorStore.get_stats(pid)
      assert stats.patterns_stored == 101
      assert stats.quantizer_stats.state == :trained
    end
  end
  
  describe "statistics and monitoring" do
    test "tracks quantization errors", %{pid: pid} do
      patterns = for _ <- 1..10 do
        create_test_pattern(:random, :random)
      end
      
      Enum.each(patterns, fn pattern ->
        VectorStore.store_pattern(pid, pattern)
      end)
      
      stats = VectorStore.get_stats(pid)
      assert stats.metrics.average_quantization_error >= 0
      assert stats.patterns_stored == 10
    end
    
    test "provides comprehensive statistics", %{pid: pid} do
      # Store some patterns
      for _ <- 1..5 do
        pattern = create_test_pattern(:temporal, :trend)
        VectorStore.store_pattern(pid, pattern)
      end
      
      stats = VectorStore.get_stats(pid)
      
      assert Map.has_key?(stats, :patterns_stored)
      assert Map.has_key?(stats, :vector_dim)
      assert Map.has_key?(stats, :quantizer_stats)
      assert Map.has_key?(stats, :metrics)
      
      assert stats.vector_dim == 64
      assert stats.patterns_stored == 5
    end
  end
  
  describe "pattern vectorization" do
    test "converts different pattern types to vectors", %{pid: pid} do
      pattern_types = [
        :temporal, :statistical, :structural, :behavioral
      ]
      
      for type <- pattern_types do
        pattern = create_test_pattern(type, :test)
        assert {:ok, _} = VectorStore.store_pattern(pid, pattern)
      end
      
      stats = VectorStore.get_stats(pid)
      assert stats.patterns_stored == 4
    end
    
    test "handles patterns with missing fields gracefully", %{pid: pid} do
      # Minimal pattern
      minimal_pattern = %{type: :unknown}
      
      assert {:ok, _} = VectorStore.store_pattern(pid, minimal_pattern)
      
      # Pattern with some fields
      partial_pattern = %{
        type: :temporal,
        confidence: 0.8
      }
      
      assert {:ok, _} = VectorStore.store_pattern(pid, partial_pattern)
    end
  end
  
  # Helper functions
  
  defp create_test_pattern(type, subtype, attrs \\ []) do
    base_pattern = %{
      type: type,
      subtype: subtype,
      confidence: attrs[:confidence] || 0.8,
      timestamp: System.monotonic_time(:millisecond)
    }
    
    # Add type-specific attributes
    type_specific = case type do
      :temporal ->
        %{
          direction: if(attrs[:increasing], do: :increasing, else: :stable),
          strength: attrs[:strength] || 0.5,
          period: attrs[:period] || 3600
        }
        
      :statistical ->
        %{
          mean: attrs[:mean] || 0.0,
          variance: attrs[:variance] || 1.0,
          correlation: attrs[:correlation] || 0.0
        }
        
      :structural ->
        %{
          cluster_count: attrs[:clusters] || 3,
          density: attrs[:density] || 0.5,
          levels: attrs[:levels] || 2
        }
        
      :behavioral ->
        %{
          frequency: attrs[:frequency] || 10,
          severity: attrs[:severity] || :medium,
          count: attrs[:count] || 5
        }
        
      _ ->
        %{}
    end
    
    Map.merge(base_pattern, type_specific)
  end
end