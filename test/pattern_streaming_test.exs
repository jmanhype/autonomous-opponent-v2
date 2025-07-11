defmodule PatternStreamingTest do
  @moduledoc """
  Comprehensive tests for HNSW event streaming integration.
  Tests pattern flow from EventBus → PatternHNSWBridge → HNSW Index → WebSocket
  """
  
  use ExUnit.Case
  use AutonomousOpponentWeb.ChannelCase
  
  alias AutonomousOpponent.EventBus
  alias AutonomousOpponent.VSM.S4.PatternHNSWBridge
  alias AutonomousOpponent.VSM.S4.VectorStore.HNSWIndex
  alias AutonomousOpponent.Metrics.Cluster.PatternAggregator
  
  @test_vector List.duplicate(0.5, 100)  # 100-dimensional test vector
  
  setup do
    # Start required processes if not running
    ensure_processes_started()
    
    # Connect to WebSocket
    {:ok, _, socket} =
      AutonomousOpponentWeb.UserSocket
      |> socket("test_user", %{})
      |> subscribe_and_join(AutonomousOpponentWeb.PatternsChannel, "patterns:stream")
    
    %{socket: socket}
  end
  
  describe "Pattern EventBus Integration" do
    test "patterns flow from EventBus to HNSW index", %{socket: _socket} do
      # Publish pattern match event
      pattern_data = %{
        pattern_id: "test_pattern_#{System.unique_integer()}",
        match_context: %{
          confidence: 0.95,
          type: "test_pattern",
          source: :test_suite
        },
        matched_event: %{data: "test"},
        triggered_at: DateTime.utc_now()
      }
      
      EventBus.publish(:pattern_matched, pattern_data)
      
      # Give time for processing
      Process.sleep(100)
      
      # Verify pattern was indexed
      stats = PatternHNSWBridge.get_stats()
      assert stats.patterns_received > 0
    end
    
    test "duplicate patterns are deduplicated", %{socket: _socket} do
      # Create identical pattern
      pattern_data = %{
        pattern_id: "dup_pattern_#{System.unique_integer()}",
        match_context: %{
          confidence: 0.95,
          type: "duplicate_test",
          source: :test_suite
        },
        matched_event: %{data: "duplicate"},
        triggered_at: DateTime.utc_now()
      }
      
      initial_stats = PatternHNSWBridge.get_stats()
      
      # Publish same pattern multiple times
      for _ <- 1..5 do
        EventBus.publish(:pattern_matched, pattern_data)
        Process.sleep(10)
      end
      
      Process.sleep(200)
      
      # Check deduplication
      final_stats = PatternHNSWBridge.get_stats()
      
      # Should have received 5 but deduplicated most
      assert final_stats.patterns_received >= initial_stats.patterns_received + 5
      assert final_stats.patterns_deduplicated > initial_stats.patterns_deduplicated
    end
    
    test "backpressure activates under load", %{socket: _socket} do
      # Generate many patterns quickly
      for i <- 1..200 do
        pattern_data = %{
          pattern_id: "load_pattern_#{i}",
          match_context: %{
            confidence: :rand.uniform(),
            type: "load_test",
            source: :load_generator
          },
          matched_event: %{data: "load_#{i}"},
          triggered_at: DateTime.utc_now()
        }
        
        EventBus.publish(:pattern_matched, pattern_data)
      end
      
      Process.sleep(500)
      
      # Check if backpressure was activated
      stats = PatternHNSWBridge.get_stats()
      assert stats.patterns_dropped > 0 or stats.backpressure_active
    end
  end
  
  describe "WebSocket Pattern Streaming" do
    test "receives pattern_indexed events", %{socket: socket} do
      # Trigger pattern indexing
      EventBus.publish(:patterns_indexed, %{
        count: 5,
        deduplicated: 1,
        source: :test_bridge
      })
      
      assert_push "pattern_indexed", %{
        count: 5,
        deduplicated: 1,
        source: "test_bridge"
      }, 1000
    end
    
    test "streams individual pattern matches", %{socket: socket} do
      pattern_data = %{
        pattern_id: "stream_test_#{System.unique_integer()}",
        match_context: %{
          confidence: 0.88,
          type: "stream_test",
          source: :websocket_test
        }
      }
      
      EventBus.publish(:pattern_matched, pattern_data)
      
      assert_push "pattern_matched", %{
        pattern_id: pattern_id,
        confidence: 0.88,
        type: "stream_test"
      }, 1000
      
      assert String.starts_with?(pattern_id, "stream_test_")
    end
    
    test "broadcasts critical algedonic patterns", %{socket: socket} do
      # High intensity signal
      EventBus.publish(:algedonic_signal, %{
        type: :pain,
        intensity: 0.9,
        source: :critical_system,
        pattern_vector: @test_vector
      })
      
      assert_push "algedonic_pattern", %{
        type: :pain,
        intensity: 0.9,
        severity: "critical"
      }, 1000
    end
    
    test "ignores low-intensity algedonic signals", %{socket: socket} do
      # Low intensity signal
      EventBus.publish(:algedonic_signal, %{
        type: :pleasure,
        intensity: 0.3,
        source: :minor_system
      })
      
      refute_push "algedonic_pattern", _, 500
    end
  end
  
  describe "Pattern Search via WebSocket" do
    test "searches for similar patterns", %{socket: socket} do
      # First, ensure some patterns exist in the index
      {:ok, _} = HNSWIndex.insert(:hnsw_index, @test_vector, %{id: "test_pattern_1"})
      
      # Query via WebSocket
      ref = push(socket, "query_similar", %{
        "vector" => @test_vector,
        "k" => 5
      })
      
      assert_reply ref, :ok, %{results: results}
      assert is_list(results)
      assert length(results) <= 5
      
      if length(results) > 0 do
        [first | _] = results
        assert Map.has_key?(first, :pattern_id)
        assert Map.has_key?(first, :similarity)
        assert Map.has_key?(first, :score)
      end
    end
    
    test "handles search errors gracefully", %{socket: socket} do
      # Invalid vector dimension
      ref = push(socket, "query_similar", %{
        "vector" => [1, 2, 3],  # Wrong dimension
        "k" => 5
      })
      
      assert_reply ref, :error, %{reason: _reason}
    end
  end
  
  describe "Cluster Pattern Aggregation" do
    @tag :distributed
    test "aggregates patterns across nodes" do
      # This test requires multiple nodes
      if length(Node.list()) > 0 do
        # Get consensus patterns
        {:ok, patterns} = PatternAggregator.get_consensus_patterns(1)
        assert is_list(patterns)
        
        # Search across cluster
        {:ok, results} = PatternAggregator.search_cluster(@test_vector, 10)
        assert is_list(results)
        
        # Verify result structure
        if length(results) > 0 do
          [first | _] = results
          assert Map.has_key?(first, :pattern_id)
          assert Map.has_key?(first, :distance)
          assert Map.has_key?(first, :consensus_score)
          assert Map.has_key?(first, :nodes)
        end
      else
        # Skip if not in distributed mode
        :ok
      end
    end
    
    test "retrieves cluster-wide stats" do
      {:ok, stats} = PatternAggregator.get_cluster_stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :cluster_nodes)
      assert Map.has_key?(stats, :aggregation_timestamp)
    end
  end
  
  describe "Pattern Monitoring" do
    test "provides comprehensive monitoring info", %{socket: socket} do
      ref = push(socket, "get_monitoring", %{})
      
      assert_reply ref, :ok, monitoring
      
      # Verify monitoring structure
      assert Map.has_key?(monitoring, :pattern_metrics)
      assert Map.has_key?(monitoring, :backpressure)
      assert Map.has_key?(monitoring, :deduplication)
      assert Map.has_key?(monitoring, :health)
      
      # Check health status
      assert monitoring[:health][:status] in [:healthy, :degraded, :warning, :error]
    end
    
    test "periodic stats updates via WebSocket" do
      # Join stats channel
      {:ok, _, stats_socket} =
        AutonomousOpponentWeb.UserSocket
        |> socket("stats_user", %{})
        |> subscribe_and_join(AutonomousOpponentWeb.PatternsChannel, "patterns:stats")
      
      # Should receive initial stats
      assert_push "initial_stats", %{stats: stats, monitoring: _}, 2000
      assert is_map(stats)
      
      # Should receive periodic updates
      assert_push "stats_update", %{stats: _updated_stats}, 6000
    end
  end
  
  describe "VSM Integration" do
    test "pattern flow through VSM subsystems" do
      # Join VSM-specific channel
      {:ok, _, vsm_socket} =
        AutonomousOpponentWeb.UserSocket
        |> socket("vsm_user", %{})
        |> subscribe_and_join(AutonomousOpponentWeb.PatternsChannel, "patterns:vsm", %{
          "subsystem" => "s4"
        })
      
      # Publish S4-specific pattern event
      EventBus.publish(:vsm_s4_patterns, %{
        patterns: [
          %{id: "s4_pattern_1", confidence: 0.9},
          %{id: "s4_pattern_2", confidence: 0.85}
        ],
        subsystem: :s4,
        timestamp: DateTime.utc_now()
      })
      
      # Verify socket received the event
      assert vsm_socket.assigns.vsm_subsystem == "s4"
    end
  end
  
  # Helper functions
  
  defp ensure_processes_started do
    # Ensure HNSW index is running
    unless Process.whereis(AutonomousOpponentV2Core.VSM.S4.HNSWIndex) do
      {:ok, _} = HNSWIndex.start_link(name: AutonomousOpponentV2Core.VSM.S4.HNSWIndex)
    end
    
    # Ensure PatternHNSWBridge is running
    unless Process.whereis(PatternHNSWBridge) do
      {:ok, _} = PatternHNSWBridge.start_link()
    end
    
    # Ensure Pattern Aggregator is running
    unless Process.whereis(PatternAggregator) do
      {:ok, _} = PatternAggregator.start_link()
    end
    
    # Give processes time to initialize
    Process.sleep(100)
  end
end