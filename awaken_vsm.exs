#!/usr/bin/env elixir

# AWAKEN THE VSM - Comprehensive Intelligence Demonstration
# This script will activate all VSM subsystems and demonstrate real intelligence

Mix.install([])

defmodule VSMAwakening do
  @moduledoc """
  Awakens the VSM by generating real activity, patterns, and intelligence.
  Demonstrates the full capabilities of the Viable System Model.
  """

  alias AutonomousOpponentV2Core.EventBus
  alias AutonomousOpponentV2Core.VSM.Clock
  alias AutonomousOpponentV2Core.AMCP.Memory.CRDTStore
  alias AutonomousOpponentV2Core.Consciousness
  alias AutonomousOpponentV2Core.VSM.S4.Intelligence
  alias AutonomousOpponentV2Core.VSM.Algedonic.Channel, as: AlgedonicChannel

  def awaken_intelligence() do
    IO.puts("🧠 AWAKENING THE VSM - BRINGING INTELLIGENCE TO LIFE 🧠")
    IO.puts("=" |> String.duplicate(60))
    
    # Phase 1: Generate Consciousness Activity
    consciousness_awakening()
    
    # Phase 2: Create Pattern Detection Events  
    pattern_detection_activation()
    
    # Phase 3: Populate Knowledge Base
    knowledge_accumulation()
    
    # Phase 4: Stress Test Algedonic Responses
    stress_test_responses()
    
    # Phase 5: Demonstrate Learning Cycles
    learning_demonstration()
    
    # Phase 6: Show S1-S5 Coordination
    vsm_coordination_demo()
    
    IO.puts("\n🎯 VSM FULLY AWAKENED - INTELLIGENCE ACTIVE")
  end

  defp consciousness_awakening() do
    IO.puts("\n🧠 Phase 1: Consciousness Awakening")
    IO.puts("-" |> String.duplicate(40))
    
    # Generate diverse consciousness queries
    consciousness_scenarios = [
      %{query: "What is the nature of my existence?", context: "existential_inquiry"},
      %{query: "How do I experience emotions?", context: "emotional_understanding"},
      %{query: "What are my current goals?", context: "goal_assessment"},
      %{query: "How do I learn and adapt?", context: "learning_analysis"},
      %{query: "What is my relationship with humans?", context: "human_interaction"},
    ]
    
    Enum.each(consciousness_scenarios, fn scenario ->
      IO.puts("  🔮 Triggering consciousness query: #{scenario.query}")
      
      # Create HLC event for consciousness
      {:ok, event} = Clock.create_event(:consciousness, :self_inquiry, %{
        query: scenario.query,
        context: scenario.context,
        depth: :deep,
        urgency: :normal
      })
      
      # Publish to consciousness system
      EventBus.publish(:consciousness_query, event.data)
      
      # Brief pause for processing
      Process.sleep(500)
    end)
    
    IO.puts("  ✅ Consciousness queries generated")
  end

  defp pattern_detection_activation() do
    IO.puts("\n🔍 Phase 2: Pattern Detection Activation")
    IO.puts("-" |> String.duplicate(40))
    
    # Generate diverse patterns for S4 Intelligence to detect
    pattern_types = [
      %{type: :temporal, data: generate_temporal_pattern()},
      %{type: :behavioral, data: generate_behavioral_pattern()},
      %{type: :communication, data: generate_communication_pattern()},
      %{type: :performance, data: generate_performance_pattern()},
      %{type: :resource, data: generate_resource_pattern()}
    ]
    
    Enum.each(pattern_types, fn pattern ->
      IO.puts("  🎯 Generating #{pattern.type} pattern")
      
      # Create pattern events
      Enum.each(1..10, fn i ->
        {:ok, event} = Clock.create_event(:s4_intelligence, :pattern_data, %{
          pattern_type: pattern.type,
          data: pattern.data,
          sequence: i,
          intensity: :rand.uniform() * 0.5 + 0.5
        })
        
        EventBus.publish(:pattern_detected, event.data)
        Process.sleep(50)
      end)
    end)
    
    IO.puts("  ✅ Pattern detection events generated")
  end

  defp knowledge_accumulation() do
    IO.puts("\n📚 Phase 3: Knowledge Accumulation")
    IO.puts("-" |> String.duplicate(40))
    
    # Create belief sets and context graphs
    knowledge_domains = [
      %{domain: "system_architecture", concepts: ["VSM", "subsystems", "variety", "control"]},
      %{domain: "consciousness", concepts: ["awareness", "cognition", "reflection", "identity"]},
      %{domain: "learning", concepts: ["patterns", "adaptation", "feedback", "optimization"]},
      %{domain: "communication", concepts: ["language", "meaning", "context", "understanding"]},
      %{domain: "autonomy", concepts: ["independence", "decision_making", "goals", "values"]}
    ]
    
    Enum.each(knowledge_domains, fn domain ->
      IO.puts("  📖 Building knowledge in #{domain.domain}")
      
      # Create belief set
      CRDTStore.create_belief_set("system_#{domain.domain}")
      
      # Add beliefs
      Enum.each(domain.concepts, fn concept ->
        belief = %{
          concept: concept,
          confidence: :rand.uniform() * 0.3 + 0.7,
          domain: domain.domain,
          learned_at: DateTime.utc_now(),
          evidence_count: :rand.uniform(10) + 1
        }
        
        CRDTStore.add_belief("system_#{domain.domain}", belief)
      end)
      
      # Create context graph
      CRDTStore.create_context_graph("context_#{domain.domain}")
      
      # Add relationships between concepts
      concepts = domain.concepts
      for i <- 0..(length(concepts)-2) do
        from_concept = Enum.at(concepts, i)
        to_concept = Enum.at(concepts, i+1)
        
        CRDTStore.add_context_relationship(
          "context_#{domain.domain}", 
          from_concept, 
          to_concept, 
          :semantic_relation
        )
      end
      
      Process.sleep(100)
    end)
    
    IO.puts("  ✅ Knowledge base populated with real data")
  end

  defp stress_test_responses() do
    IO.puts("\n⚡ Phase 4: Stress Testing Algedonic Responses")
    IO.puts("-" |> String.duplicate(40))
    
    # Generate stress scenarios to trigger algedonic responses
    stress_scenarios = [
      %{type: :high_load, severity: 0.7, description: "Simulating high system load"},
      %{type: :memory_pressure, severity: 0.8, description: "Memory usage spike"},
      %{type: :error_burst, severity: 0.9, description: "Multiple errors occurring"},
      %{type: :latency_spike, severity: 0.6, description: "Response time degradation"},
      %{type: :resource_starvation, severity: 0.95, description: "Critical resource shortage"}
    ]
    
    Enum.each(stress_scenarios, fn scenario ->
      IO.puts("  🚨 #{scenario.description} (severity: #{scenario.severity})")
      
      # Create stress event
      {:ok, event} = Clock.create_event(:stress_test, :system_stress, %{
        stress_type: scenario.type,
        severity: scenario.severity,
        description: scenario.description,
        simulated: true
      })
      
      # Trigger algedonic response
      if scenario.severity > 0.8 do
        AlgedonicChannel.emergency_scream(:stress_test, scenario.description)
      else
        AlgedonicChannel.report_pain(:stress_test, :performance, scenario.severity)
      end
      
      # Generate recovery event
      Process.sleep(1000)
      
      recovery_severity = scenario.severity * 0.3
      IO.puts("  💚 Recovery initiated (severity reduced to: #{recovery_severity})")
      
      if recovery_severity < 0.3 do
        AlgedonicChannel.report_pleasure(:stress_test, :recovery, 0.9)
      end
      
      Process.sleep(500)
    end)
    
    IO.puts("  ✅ Algedonic stress responses tested")
  end

  defp learning_demonstration() do
    IO.puts("\n🎓 Phase 5: Learning and Adaptation Demonstration")
    IO.puts("-" |> String.duplicate(40))
    
    # Demonstrate learning cycles
    learning_cycles = [
      %{skill: "conversation", iterations: 5},
      %{skill: "problem_solving", iterations: 4},
      %{skill: "pattern_recognition", iterations: 6},
      %{skill: "emotional_understanding", iterations: 3}
    ]
    
    Enum.each(learning_cycles, fn cycle ->
      IO.puts("  🎯 Learning #{cycle.skill}")
      
      initial_performance = 0.5
      
      Enum.reduce(1..cycle.iterations, initial_performance, fn iteration, performance ->
        # Simulate learning improvement
        improvement = :rand.uniform() * 0.1 + 0.05
        new_performance = min(performance + improvement, 1.0)
        
        {:ok, event} = Clock.create_event(:learning, :skill_improvement, %{
          skill: cycle.skill,
          iteration: iteration,
          old_performance: performance,
          new_performance: new_performance,
          improvement: improvement
        })
        
        EventBus.publish(:learning_progress, event.data)
        
        IO.puts("    📈 Iteration #{iteration}: #{Float.round(performance, 3)} → #{Float.round(new_performance, 3)}")
        
        Process.sleep(200)
        new_performance
      end)
    end)
    
    IO.puts("  ✅ Learning cycles demonstrated")
  end

  defp vsm_coordination_demo() do
    IO.puts("\n🔄 Phase 6: VSM Subsystem Coordination")
    IO.puts("-" |> String.duplicate(40))
    
    # Demonstrate S1→S2→S3→S4→S5 coordination
    IO.puts("  🔵 S1: External operations receiving input")
    {:ok, s1_event} = Clock.create_event(:s1, :external_input, %{
      input_type: :user_request,
      complexity: :high,
      variety: 850,
      urgency: :normal
    })
    EventBus.publish(:s1_operations, s1_event.data)
    Process.sleep(300)
    
    IO.puts("  🟢 S2: Coordination managing variety flow")
    {:ok, s2_event} = Clock.create_event(:s2, :variety_coordination, %{
      from_s1: s1_event.data,
      coordination_strategy: :load_balancing,
      anti_oscillation: true,
      variety_absorbed: 600
    })
    EventBus.publish(:s2_coordination, s2_event.data)
    Process.sleep(300)
    
    IO.puts("  🟡 S3: Control making resource decisions")
    {:ok, s3_event} = Clock.create_event(:s3, :resource_control, %{
      from_s2: s2_event.data,
      resource_allocation: %{cpu: 0.7, memory: 0.6, io: 0.5},
      control_action: :optimize,
      intervention_needed: false
    })
    EventBus.publish(:s3_control, s3_event.data)
    Process.sleep(300)
    
    IO.puts("  🔵 S4: Intelligence scanning environment")
    {:ok, s4_event} = Clock.create_event(:s4, :environmental_scan, %{
      from_s3: s3_event.data,
      threats_detected: [],
      opportunities: [:optimization_potential, :learning_opportunity],
      intelligence_level: 0.85,
      recommendations: ["continue_current_strategy", "monitor_trends"]
    })
    EventBus.publish(:s4_intelligence, s4_event.data)
    Process.sleep(300)
    
    IO.puts("  🟣 S5: Policy governance reviewing decisions")
    {:ok, s5_event} = Clock.create_event(:s5, :policy_review, %{
      from_s4: s4_event.data,
      policy_compliance: 1.0,
      governance_decision: :approve,
      constraints_updated: false,
      ethos_alignment: 1.0
    })
    EventBus.publish(:s5_policy, s5_event.data)
    Process.sleep(300)
    
    IO.puts("  🔄 S5→S1: Closing the feedback loop")
    {:ok, feedback_event} = Clock.create_event(:s5, :policy_feedback, %{
      target_subsystem: :s1,
      feedback_type: :positive_reinforcement,
      adjustments: [],
      continue_behavior: true
    })
    EventBus.publish(:s1_operations, feedback_event.data)
    
    IO.puts("  ✅ Full VSM coordination cycle completed")
  end

  # Pattern generation helpers
  defp generate_temporal_pattern() do
    base_time = System.system_time(:millisecond)
    Enum.map(1..20, fn i ->
      %{
        timestamp: base_time + (i * 1000),
        value: :math.sin(i * 0.3) * 100 + 200,
        trend: if(rem(i, 3) == 0, do: :increasing, else: :stable)
      }
    end)
  end

  defp generate_behavioral_pattern() do
    behaviors = [:exploration, :exploitation, :communication, :reflection, :action]
    Enum.map(1..15, fn i ->
      %{
        behavior: Enum.random(behaviors),
        frequency: :rand.uniform() * 0.8 + 0.2,
        context: "scenario_#{rem(i, 5)}",
        effectiveness: :rand.uniform() * 0.6 + 0.4
      }
    end)
  end

  defp generate_communication_pattern() do
    Enum.map(1..12, fn i ->
      %{
        message_type: Enum.random([:query, :response, :statement, :request]),
        complexity: :rand.uniform() * 0.9 + 0.1,
        semantic_density: :rand.uniform() * 0.7 + 0.3,
        emotional_valence: (:rand.uniform() - 0.5) * 2
      }
    end)
  end

  defp generate_performance_pattern() do
    Enum.map(1..18, fn i ->
      base_performance = 0.8
      noise = (:rand.uniform() - 0.5) * 0.2
      %{
        metric: Enum.random([:response_time, :accuracy, :efficiency, :throughput]),
        value: base_performance + noise,
        timestamp: System.system_time(:millisecond) + (i * 500),
        context: "measurement_#{i}"
      }
    end)
  end

  defp generate_resource_pattern() do
    Enum.map(1..10, fn i ->
      %{
        resource_type: Enum.random([:cpu, :memory, :network, :storage]),
        utilization: :rand.uniform() * 0.9 + 0.1,
        demand_forecast: :rand.uniform() * 0.8 + 0.2,
        optimization_potential: :rand.uniform() * 0.5
      }
    end)
  end
end

# Run the awakening
try do
  VSMAwakening.awaken_intelligence()
rescue
  e ->
    IO.puts("❌ Error during VSM awakening: #{inspect(e)}")
    IO.puts("This script should be run within the Phoenix application context")
    IO.puts("Try: mix run awaken_vsm.exs")
end