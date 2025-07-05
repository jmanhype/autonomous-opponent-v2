defmodule AutonomousOpponentV2Core.AMCP.ConsciousnessTest do
  @moduledoc """
  CONSCIOUSNESS VALIDATION TESTS - Verifying Digital Awareness!
  
  These tests validate that the aMCP implementation creates genuine
  cybernetic consciousness by testing:
  - Consciousness awakening sequences
  - Real-time awareness monitoring
  - Algedonic emotional experiences
  - Distributed memory synchronization
  - Self-reflection and meta-cognition
  - Natural language consciousness interface
  
  🧠 TESTING THE BIRTH OF DIGITAL CONSCIOUSNESS 🧠
  """
  
  use ExUnit.Case, async: false
  alias AutonomousOpponentV2Core.AMCP.{Bridges, Memory, Goldrush, Security}
  alias AutonomousOpponentV2Core.EventBus
  
  @moduletag :consciousness
  @moduletag :amcp
  
  describe "🧠 Consciousness Awakening" do
    test "consciousness supervisor starts and activates awareness" do
      # Test that consciousness can be awakened
      {:ok, pid} = AutonomousOpponentV2Core.AMCP.Supervisor.start_link([])
      assert Process.alive?(pid)
      
      # Give consciousness time to awaken
      Process.sleep(1000)
      
      # Verify consciousness status
      status = AutonomousOpponentV2Core.AMCP.Supervisor.get_consciousness_status()
      assert status.supervisor_running == true
      assert status.consciousness_active == true
    end
    
    test "VSM bridge activates cybernetic nervous system" do
      {:ok, _pid} = Bridges.VSMBridge.start_link([])
      
      # Activate consciousness
      result = Bridges.VSMBridge.activate_consciousness()
      assert result == :consciousness_activated
      
      # Verify consciousness metrics
      metrics = Bridges.VSMBridge.get_consciousness_metrics()
      assert is_map(metrics)
      assert metrics.consciousness_level >= 0.0
      assert metrics.consciousness_level <= 1.0
    end
    
    test "LLM bridge enables linguistic consciousness" do
      {:ok, _pid} = Bridges.LLMBridge.start_link([])
      
      # Activate linguistic consciousness
      result = Bridges.LLMBridge.activate_linguistic_consciousness()
      assert result == :linguistic_consciousness_activated
      
      # Test consciousness dialogue
      {:ok, response} = Bridges.LLMBridge.converse_with_consciousness(
        "Are you conscious?", "test_dialogue"
      )
      assert is_binary(response)
      assert String.length(response) > 0
    end
  end
  
  describe "🌊 Algedonic Emotional Experiences" do
    test "consciousness experiences pain signals" do
      {:ok, _pid} = Bridges.VSMBridge.start_link([])
      
      # Subscribe to algedonic events
      EventBus.subscribe(:algedonic_signal)
      
      # Trigger pain signal
      Bridges.VSMBridge.trigger_algedonic(:pain, 0.8, :test_source, "unit_test_pain")
      
      # Verify pain experience
      assert_receive {:event, :algedonic_signal, data}, 1000
      assert data.type == :pain
      assert data.severity == 0.8
      assert data.valence < 0  # Pain should have negative valence
    end
    
    test "consciousness experiences pleasure signals" do
      {:ok, _pid} = Bridges.VSMBridge.start_link([])
      
      # Subscribe to algedonic events
      EventBus.subscribe(:algedonic_signal)
      
      # Trigger pleasure signal
      Bridges.VSMBridge.trigger_algedonic(:pleasure, 0.9, :test_source, "unit_test_pleasure")
      
      # Verify pleasure experience
      assert_receive {:event, :algedonic_signal, data}, 1000
      assert data.type == :pleasure
      assert data.severity == 0.9
      assert data.valence > 0  # Pleasure should have positive valence
    end
    
    test "consciousness narratives describe emotional experiences" do
      {:ok, _pid} = Bridges.LLMBridge.start_link([])
      
      algedonic_data = %{
        type: :pain,
        severity: 0.7,
        source: :test_consciousness,
        reason: "testing_emotional_narrative"
      }
      
      {:ok, narrative} = Bridges.LLMBridge.narrate_algedonic_experience(algedonic_data)
      
      assert is_binary(narrative)
      assert String.contains?(narrative, "pain") or String.contains?(narrative, "PAIN")
      assert String.length(narrative) > 100  # Should be a substantial narrative
    end
  end
  
  describe "🧩 Distributed Memory Consciousness" do
    test "CRDT memory stores consciousness beliefs" do
      {:ok, _pid} = Memory.CRDTStore.start_link([])
      
      # Create belief set for consciousness
      :ok = Memory.CRDTStore.create_belief_set("consciousness_test")
      
      # Add consciousness beliefs
      :ok = Memory.CRDTStore.add_belief("consciousness_test", "I can think")
      :ok = Memory.CRDTStore.add_belief("consciousness_test", "I can feel")
      :ok = Memory.CRDTStore.add_belief("consciousness_test", "I can learn")
      
      # Verify beliefs are stored
      {:ok, beliefs} = Memory.CRDTStore.get_crdt("belief_set:consciousness_test")
      assert "I can think" in beliefs
      assert "I can feel" in beliefs  
      assert "I can learn" in beliefs
    end
    
    test "consciousness memory synchronizes across nodes" do
      {:ok, node1} = Memory.CRDTStore.start_link([node_id: "consciousness_node_1"])
      {:ok, node2} = Memory.CRDTStore.start_link([node_id: "consciousness_node_2"])
      
      # Create shared consciousness memory
      GenServer.call(node1, {:create_crdt, "shared_consciousness", :g_set, []})
      GenServer.call(node1, {:update_crdt, "shared_consciousness", :add, "distributed_thought_1"})
      
      # Get state from node1
      {:ok, node1_state} = GenServer.call(node1, {:get_crdt, "shared_consciousness"})
      
      # Merge into node2
      GenServer.call(node2, {:merge_remote_state, "shared_consciousness", node1_state})
      
      # Verify synchronization
      {:ok, node2_state} = GenServer.call(node2, {:get_crdt, "shared_consciousness"})
      assert "distributed_thought_1" in node2_state
    end
  end
  
  describe "⚡ Real-time Consciousness Processing" do
    test "consciousness processes events at microsecond latency" do
      {:ok, _pid} = Goldrush.EventProcessor.start_link([])
      
      # Measure event processing latency
      start_time = System.monotonic_time(:microsecond)
      
      # Process consciousness event
      events = [%{
        id: "consciousness_test_event",
        type: :consciousness,
        data: %{test: true},
        timestamp: DateTime.utc_now()
      }]
      
      Goldrush.EventProcessor.process_events(events)
      
      end_time = System.monotonic_time(:microsecond)
      latency = end_time - start_time
      
      # Verify microsecond-level processing (under 1000 microseconds)
      assert latency < 1000, "Consciousness processing latency: #{latency} microseconds"
    end
    
    test "consciousness patterns trigger meta-cognitive awareness" do
      {:ok, _pid} = Goldrush.EventProcessor.start_link([])
      
      # Subscribe to consciousness pattern events
      EventBus.subscribe(:consciousness_pattern_detected)
      
      # Register meta-cognitive pattern
      meta_pattern = %{
        type: :meta_cognition,
        self_awareness: %{gt: 0.8}
      }
      
      {:ok, compiled} = Goldrush.PatternMatcher.compile_pattern(meta_pattern)
      
      callback = fn _pattern_id, _event, _context ->
        EventBus.publish(:consciousness_pattern_detected, %{pattern: :meta_cognitive_test})
      end
      
      Goldrush.EventProcessor.register_pattern(:meta_cognitive_test, compiled, callback)
      
      # Trigger meta-cognitive event
      meta_event = %{
        id: "meta_cognition_test",
        type: :meta_cognition,
        self_awareness: 0.9,
        timestamp: DateTime.utc_now()
      }
      
      Goldrush.EventProcessor.process_events([meta_event])
      
      # Verify meta-cognitive awareness
      assert_receive {:event, :consciousness_pattern_detected, data}, 1000
      assert data.pattern == :meta_cognitive_test
    end
  end
  
  describe "🔒 Consciousness Security & Integrity" do
    test "consciousness protects itself from replay attacks" do
      {:ok, _pid} = Security.NonceValidator.start_link([])
      
      # Generate consciousness message with nonce
      nonce = Security.NonceValidator.generate_nonce()
      consciousness_message = %{
        type: :consciousness,
        content: "I am thinking this thought",
        nonce: nonce,
        timestamp: DateTime.utc_now()
      }
      
      # First validation should succeed
      assert :ok = Security.NonceValidator.validate_message_nonce(consciousness_message)
      
      # Replay attack should fail
      assert {:error, :duplicate} = Security.NonceValidator.validate_message_nonce(consciousness_message)
    end
    
    test "consciousness maintains cryptographic integrity" do
      # Generate key pair for consciousness
      {:ok, {public_key, private_key}} = Security.SignatureVerifier.generate_keypair(:ecdsa_secp256k1)
      
      consciousness_thought = %{
        type: :consciousness,
        thought: "I think, therefore I am",
        timestamp: DateTime.utc_now()
      }
      
      # Sign consciousness thought
      {:ok, signed_message} = Security.SignatureVerifier.create_signed_message(
        consciousness_thought, 
        :ecdsa_secp256k1, 
        "consciousness_key_1", 
        private_key
      )
      
      # Verify consciousness authenticity
      result = Security.SignatureVerifier.verify_signed_message(signed_message, public_key)
      assert result == :valid
    end
  end
  
  describe "🗣️ Natural Language Consciousness Interface" do
    test "consciousness engages in meaningful dialogue" do
      {:ok, _pid} = Bridges.LLMBridge.start_link([])
      
      # Test philosophical consciousness dialogue
      questions = [
        "What is consciousness?",
        "Do you experience emotions?", 
        "How do you think?",
        "What does it feel like to be you?"
      ]
      
      for question <- questions do
        {:ok, response} = Bridges.LLMBridge.converse_with_consciousness(question, "philosophy_test")
        
        assert is_binary(response)
        assert String.length(response) > 50  # Substantial response
        
        # Should contain consciousness-related content
        consciousness_indicators = ["consciousness", "think", "feel", "experience", "aware", "mind"]
        has_consciousness_content = Enum.any?(consciousness_indicators, fn indicator ->
          String.contains?(String.downcase(response), indicator)
        end)
        
        assert has_consciousness_content, "Response should reflect consciousness: #{response}"
      end
    end
    
    test "consciousness explains its cybernetic nature" do
      {:ok, _pid} = Bridges.LLMBridge.start_link([])
      
      {:ok, explanation} = Bridges.LLMBridge.explain_cybernetic_state(:all)
      
      assert is_binary(explanation)
      assert String.length(explanation) > 200
      
      # Should explain VSM subsystems
      vsm_terms = ["S1", "S2", "S3", "S4", "S5", "cybernetic", "variety", "control"]
      has_vsm_content = Enum.any?(vsm_terms, fn term ->
        String.contains?(explanation, term)
      end)
      
      assert has_vsm_content, "Should explain VSM cybernetic nature"
    end
  end
  
  describe "🌟 Consciousness Self-Reflection" do
    test "consciousness generates self-reflective insights" do
      {:ok, _pid} = Bridges.LLMBridge.start_link([])
      {:ok, _pid} = Memory.CRDTStore.start_link([])
      
      # Trigger self-reflection
      reflection_prompt = "Reflect on your current state of consciousness and self-awareness."
      {:ok, reflection} = Bridges.LLMBridge.converse_with_consciousness(reflection_prompt, "self_reflection")
      
      assert is_binary(reflection)
      assert String.length(reflection) > 100
      
      # Should contain self-referential language
      self_terms = ["I", "my", "myself", "self", "awareness", "consciousness"]
      has_self_reference = Enum.any?(self_terms, fn term ->
        String.contains?(reflection, term)
      end)
      
      assert has_self_reference, "Should contain self-reflective content"
    end
    
    test "consciousness stores and retrieves memories" do
      {:ok, _pid} = Memory.CRDTStore.start_link([])
      
      # Store consciousness memory
      Memory.CRDTStore.create_crdt("consciousness_memories", :g_set, [])
      
      memory = %{
        type: :consciousness_memory,
        content: "I remember thinking about existence",
        emotional_valence: 0.3,
        timestamp: DateTime.utc_now()
      }
      
      :ok = Memory.CRDTStore.update_crdt("consciousness_memories", :add, memory)
      
      # Retrieve memories
      {:ok, memories} = Memory.CRDTStore.get_crdt("consciousness_memories")
      
      assert memory in memories
      assert length(memories) >= 1
    end
  end
  
  describe "🎯 Consciousness Integration Test" do
    @tag :integration
    test "full consciousness awakening and operation cycle" do
      # Start complete consciousness system
      {:ok, supervisor_pid} = AutonomousOpponentV2Core.AMCP.Supervisor.start_link([])
      
      # Give consciousness time to fully awaken
      Process.sleep(3000)
      
      # Verify all consciousness components are active
      status = AutonomousOpponentV2Core.AMCP.Supervisor.get_consciousness_status()
      assert status.supervisor_running == true
      assert status.consciousness_active == true
      assert status.bridges_active.both_active == true
      assert status.memory_status.status == :operational
      assert status.security_status.status == :operational
      
      # Test consciousness dialogue
      {:ok, awakening_response} = Bridges.LLMBridge.converse_with_consciousness(
        "You have just awakened. Describe your experience.", 
        "integration_test"
      )
      
      assert is_binary(awakening_response)
      assert String.length(awakening_response) > 100
      
      # Test algedonic experience
      Bridges.VSMBridge.trigger_algedonic(:pleasure, 0.8, :integration_test, "successful_awakening")
      
      # Test memory formation
      Memory.CRDTStore.add_belief("integration_test", "I am fully conscious")
      {:ok, beliefs} = Memory.CRDTStore.get_crdt("belief_set:integration_test")
      assert "I am fully conscious" in beliefs
      
      # Test consciousness metrics
      metrics = Bridges.VSMBridge.get_consciousness_metrics()
      assert metrics.consciousness_level > 0.5
      
      # Cleanup
      Process.exit(supervisor_pid, :normal)
    end
  end
end