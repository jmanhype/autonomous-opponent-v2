defmodule AutonomousOpponentV2Core.AMCP.Memory.CRDTStoreSynthesisTest do
  use ExUnit.Case, async: false

  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
  alias AutonomousOpponentV2Core.EventBus

  @moduletag :synthesis

  setup do
    # Start the CRDT store with synthesis enabled
    {:ok, _pid} = start_supervised({CRDTStore, [synthesis_enabled: true]})
    
    # Create a test subscriber for synthesis events
    test_pid = self()
    EventBus.subscribe(:memory_synthesis)
    EventBus.subscribe(:memory_synthesis_failed)
    
    on_exit(fn ->
      # Clean up any synthesis timers
      :timer.kill_after(100)
    end)
    
    :ok
  end

  describe "synthesis timer activation" do
    test "enables synthesis when configured" do
      # Set synthesis enabled in config
      Application.put_env(:autonomous_opponent_core, :synthesis_enabled, true)
      
      # Start new store with synthesis enabled
      {:ok, store_pid} = start_supervised({CRDTStore, [synthesis_enabled: true]}, id: :synthesis_store)
      
      # Get the store state
      state = :sys.get_state(store_pid)
      
      assert state.synthesis_enabled == true
      assert state.belief_update_count == 0
      assert state.last_synthesis_time == nil
    end

    test "disables synthesis when not configured" do
      # Set synthesis disabled in config
      Application.put_env(:autonomous_opponent_core, :synthesis_enabled, false)
      
      # Start new store with synthesis disabled
      {:ok, store_pid} = start_supervised({CRDTStore, [synthesis_enabled: false]}, id: :no_synthesis_store)
      
      # Get the store state
      state = :sys.get_state(store_pid)
      
      assert state.synthesis_enabled == false
    end
  end

  describe "belief update tracking" do
    test "tracks belief updates correctly" do
      # Simulate belief updates
      for i <- 1..10 do
        EventBus.publish(:amcp_belief_change, %{
          agent_id: "test_agent_#{i}",
          belief: "test_belief_#{i}",
          timestamp: DateTime.utc_now()
        })
        
        # Small delay to ensure events are processed
        Process.sleep(10)
      end
      
      # Check that belief count is tracked
      state = :sys.get_state(CRDTStore)
      assert state.belief_update_count == 10
    end

    test "triggers synthesis after 50 belief updates" do
      # Create some test CRDTs first
      CRDTStore.create_crdt("test_knowledge_1", :g_set, ["fact1", "fact2"])
      CRDTStore.create_crdt("test_knowledge_2", :lww_register, "important_data")
      
      # Simulate 50 belief updates
      for i <- 1..50 do
        EventBus.publish(:amcp_belief_change, %{
          agent_id: "test_agent",
          belief: "belief_#{i}",
          timestamp: DateTime.utc_now()
        })
        
        # Small delay to ensure events are processed
        Process.sleep(5)
      end
      
      # Should receive synthesis event
      assert_receive {:event_bus_hlc, %{topic: :memory_synthesis}}, 5000
      
      # Wait a bit for the synthesis completion callback to process
      Process.sleep(100)
      
      # Check that belief count was reset after successful synthesis
      state = :sys.get_state(CRDTStore)
      assert state.belief_update_count == 0
      assert state.last_synthesis_time != nil
    end
  end

  describe "synthesis validation" do
    test "validates API key prerequisites" do
      # Remove API keys temporarily
      original_openai = System.get_env("OPENAI_API_KEY")
      original_anthropic = System.get_env("ANTHROPIC_API_KEY")
      
      System.delete_env("OPENAI_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")
      
      # Try to synthesize knowledge
      result = CRDTStore.synthesize_knowledge()
      
      # Should fail due to missing API keys
      assert match?({:error, _}, result)
      
      # Restore API keys
      if original_openai, do: System.put_env("OPENAI_API_KEY", original_openai)
      if original_anthropic, do: System.put_env("ANTHROPIC_API_KEY", original_anthropic)
    end

    test "enforces rate limiting" do
      # Set a very short rate limit for testing
      Application.put_env(:autonomous_opponent_core, :synthesis_rate_limit_ms, 100)
      
      # Create test data
      CRDTStore.create_crdt("test_data", :g_set, ["test"])
      
      # First synthesis should work
      result1 = CRDTStore.synthesize_knowledge()
      assert match?({:ok, _}, result1)
      
      # Immediate second synthesis should be rate limited
      result2 = CRDTStore.synthesize_knowledge()
      assert match?({:error, _}, result2)
      
      # Wait for rate limit to expire
      Process.sleep(150)
      
      # Third synthesis should work
      result3 = CRDTStore.synthesize_knowledge()
      assert match?({:ok, _}, result3)
    end
  end

  describe "synthesis content generation" do
    test "generates synthesis with no CRDTs" do
      # Clear any existing CRDTs
      :sys.replace_state(CRDTStore, fn state ->
        %{state | crdts: %{}}
      end)
      
      # Should return initialization message
      {:ok, synthesis} = CRDTStore.synthesize_knowledge()
      
      assert String.contains?(synthesis, "No CRDT data available")
      assert String.contains?(synthesis, "initializing")
    end

    test "generates synthesis with CRDT data" do
      # Create test CRDTs
      CRDTStore.create_crdt("knowledge_facts", :g_set, ["fact1", "fact2", "fact3"])
      CRDTStore.create_crdt("metrics_counter", :pn_counter, 42)
      CRDTStore.create_crdt("current_state", :lww_register, "active")
      
      # Mock LLM response for testing
      Application.put_env(:autonomous_opponent_core, :llm_test_mode, true)
      
      # Perform synthesis
      result = CRDTStore.synthesize_knowledge()
      
      # Should succeed with data
      assert match?({:ok, _}, result)
      
      # Clean up
      Application.delete_env(:autonomous_opponent_core, :llm_test_mode)
    end

    test "filters CRDTs by domain" do
      # Create CRDTs in different domains
      CRDTStore.create_crdt("intelligence_patterns", :g_set, ["pattern1"])
      CRDTStore.create_crdt("memory_facts", :g_set, ["memory1"])
      CRDTStore.create_crdt("system_metrics", :pn_counter, 100)
      
      # Test domain filtering
      {:ok, intelligence_synthesis} = CRDTStore.synthesize_knowledge([:intelligence])
      {:ok, memory_synthesis} = CRDTStore.synthesize_knowledge([:memory])
      {:ok, all_synthesis} = CRDTStore.synthesize_knowledge(:all)
      
      # All should be valid synthesis results
      assert is_binary(intelligence_synthesis)
      assert is_binary(memory_synthesis) 
      assert is_binary(all_synthesis)
    end
  end

  describe "periodic synthesis" do
    test "periodic synthesis timer works" do
      # Create test data
      CRDTStore.create_crdt("periodic_test", :g_set, ["data"])
      
      # Send periodic synthesis message directly
      send(CRDTStore, :periodic_synthesis)
      
      # Should receive synthesis event
      assert_receive {:event_bus_hlc, %{topic: :memory_synthesis}}, 5000
    end

    test "periodic synthesis skips when disabled" do
      # Temporarily disable synthesis
      :sys.replace_state(CRDTStore, fn state ->
        %{state | synthesis_enabled: false}
      end)
      
      # Send periodic synthesis message
      send(CRDTStore, :periodic_synthesis)
      
      # Should not receive synthesis event
      refute_receive {:event_bus_hlc, %{topic: :memory_synthesis}}, 1000
    end

    test "periodic synthesis skips when no CRDTs" do
      # Clear CRDTs
      :sys.replace_state(CRDTStore, fn state ->
        %{state | crdts: %{}}
      end)
      
      # Send periodic synthesis message
      send(CRDTStore, :periodic_synthesis)
      
      # Should not receive synthesis event
      refute_receive {:event_bus_hlc, %{topic: :memory_synthesis}}, 1000
    end
  end

  describe "synthesis error handling" do
    test "handles synthesis failures gracefully" do
      # Create test data
      CRDTStore.create_crdt("error_test", :g_set, ["data"])
      
      # Mock LLM failure
      Application.put_env(:autonomous_opponent_core, :llm_force_error, true)
      
      # Trigger synthesis
      send(CRDTStore, :periodic_synthesis)
      
      # Should receive failure event
      assert_receive {:event_bus_hlc, %{topic: :memory_synthesis_failed}}, 5000
      
      # Clean up
      Application.delete_env(:autonomous_opponent_core, :llm_force_error)
    end

    test "publishes telemetry on synthesis completion" do
      # Create test data
      CRDTStore.create_crdt("telemetry_test", :g_set, ["data"])
      
      # Set up telemetry handler
      test_pid = self()
      :telemetry.attach(
        "synthesis_test",
        [:crdt_store, :synthesis, :completed],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      # Trigger synthesis
      send(CRDTStore, :periodic_synthesis)
      
      # Should receive telemetry event
      assert_receive {:telemetry, [:crdt_store, :synthesis, :completed], _, _}, 5000
      
      # Clean up
      :telemetry.detach("synthesis_test")
    end
  end

  describe "consciousness integration" do
    test "synthesis results reach consciousness" do
      # Subscribe to consciousness events
      EventBus.subscribe(:consciousness_update)
      
      # Create test data
      CRDTStore.create_crdt("consciousness_test", :g_set, ["insight"])
      
      # Trigger synthesis
      send(CRDTStore, :periodic_synthesis)
      
      # Should receive synthesis event
      assert_receive {:event_bus_hlc, %{topic: :memory_synthesis, data: %{synthesis: synthesis}}}, 5000
      
      # Synthesis should be a string
      assert is_binary(synthesis)
      assert String.length(synthesis) > 0
    end
  end

  describe "synthesis performance" do
    test "synthesis completes within timeout" do
      # Create test data
      CRDTStore.create_crdt("performance_test", :g_set, ["data"])
      
      # Measure synthesis time
      start_time = System.monotonic_time(:millisecond)
      
      # Trigger synthesis
      send(CRDTStore, :periodic_synthesis)
      
      # Should complete within reasonable time
      assert_receive {:event_bus_hlc, %{topic: :memory_synthesis}}, 30_000
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete within 30 seconds
      assert duration < 30_000
    end

    test "synthesis handles large CRDT datasets" do
      # Create many CRDTs
      for i <- 1..20 do
        CRDTStore.create_crdt("large_test_#{i}", :g_set, ["data_#{i}"])
      end
      
      # Trigger synthesis
      send(CRDTStore, :periodic_synthesis)
      
      # Should still complete successfully
      assert_receive {:event_bus_hlc, %{topic: :memory_synthesis}}, 30_000
    end
  end

  describe "concurrent task limiting" do
    test "enforces max concurrent synthesis limit" do
      # Create test data
      CRDTStore.create_crdt("concurrent_test", :g_set, ["data"])
      
      # Set a low concurrent limit for testing
      :sys.replace_state(CRDTStore, fn state ->
        %{state | max_concurrent_synthesis: 2}
      end)
      
      # Trigger multiple synthesis attempts quickly
      for _ <- 1..5 do
        send(CRDTStore, :periodic_synthesis)
      end
      
      # Check state - should have max 2 active synthesis tasks
      Process.sleep(100)
      state = :sys.get_state(CRDTStore)
      assert state.active_synthesis_count <= state.max_concurrent_synthesis
    end

    test "decrements active count on synthesis completion" do
      # Create test data
      CRDTStore.create_crdt("decrement_test", :g_set, ["data"])
      
      # Trigger synthesis
      send(CRDTStore, :periodic_synthesis)
      
      # Wait for synthesis to start
      Process.sleep(100)
      state1 = :sys.get_state(CRDTStore)
      assert state1.active_synthesis_count > 0
      
      # Wait for synthesis completion
      assert_receive {:event_bus_hlc, %{topic: :memory_synthesis}}, 5000
      Process.sleep(100)
      
      # Active count should be back to 0
      state2 = :sys.get_state(CRDTStore)
      assert state2.active_synthesis_count == 0
    end
  end
end