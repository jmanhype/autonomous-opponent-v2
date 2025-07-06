defmodule AutonomousOpponent.Benchmarks.Consciousness do
  @moduledoc """
  Performance benchmarks for consciousness operations.
  Measures the speed of state transitions, inner dialog processing, and decision making.
  """

  alias AutonomousOpponentV2Core.Consciousness
  alias AutonomousOpponentV2Core.Consciousness.{State, InnerDialog, DecisionMaker}

  def run do
    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)

    # Configure benchmarking scenarios
    scenarios = %{
      "get_current_state" => &benchmark_get_current_state/0,
      "state_transition" => &benchmark_state_transition/0,
      "inner_dialog_simple" => &benchmark_inner_dialog_simple/0,
      "inner_dialog_complex" => &benchmark_inner_dialog_complex/0,
      "decision_making_fast" => &benchmark_decision_making_fast/0,
      "decision_making_complex" => &benchmark_decision_making_complex/0,
      "full_consciousness_cycle" => &benchmark_full_consciousness_cycle/0,
      "parallel_thoughts" => &benchmark_parallel_thoughts/0
    }

    Benchee.run(
      scenarios,
      time: 10,
      memory_time: 2,
      warmup: 2,
      parallel: 1,
      formatters: [
        Benchee.Formatters.Console,
        {Benchee.Formatters.HTML, file: "benchmarks/output/consciousness.html"},
        {Benchee.Formatters.JSON, file: "benchmarks/output/consciousness.json"}
      ],
      print: %{
        fast_warning: false,
        benchmarking: true,
        configuration: true
      }
    )
  end

  # Benchmark functions
  defp benchmark_get_current_state do
    Consciousness.get_state()
  end

  defp benchmark_state_transition do
    # Simulate state transition
    current_state = Consciousness.get_state()
    
    new_state = %{
      state: advance_state(current_state.state),
      timestamp: DateTime.utc_now(),
      confidence: :rand.uniform(),
      inner_dialog: []
    }
    
    Consciousness.update_state(new_state)
  end

  defp benchmark_inner_dialog_simple do
    # Simple inner dialog processing
    InnerDialog.process_thought("What is the meaning of this input?")
  end

  defp benchmark_inner_dialog_complex do
    # Complex inner dialog with multiple thoughts
    thoughts = [
      "Analyzing current system state...",
      "Detecting patterns in recent events...",
      "Considering multiple action paths...",
      "Evaluating risk vs reward...",
      "Synthesizing optimal response..."
    ]
    
    Enum.map(thoughts, &InnerDialog.process_thought/1)
  end

  defp benchmark_decision_making_fast do
    # Fast decision with minimal context
    DecisionMaker.decide(%{
      options: ["yes", "no"],
      context: %{urgency: :high}
    })
  end

  defp benchmark_decision_making_complex do
    # Complex decision with rich context
    DecisionMaker.decide(%{
      options: [
        %{action: "engage", risk: 0.3, reward: 0.8},
        %{action: "observe", risk: 0.1, reward: 0.4},
        %{action: "retreat", risk: 0.05, reward: 0.2},
        %{action: "delegate", risk: 0.2, reward: 0.6}
      ],
      context: %{
        current_state: Consciousness.get_state(),
        environmental_factors: generate_environment_data(),
        historical_outcomes: generate_historical_data(),
        constraints: %{
          time_limit: 1000,
          resource_budget: 0.7,
          risk_tolerance: 0.4
        }
      }
    })
  end

  defp benchmark_full_consciousness_cycle do
    # Complete consciousness processing cycle
    
    # 1. Perceive
    input = %{
      sensory_data: generate_sensory_data(),
      timestamp: DateTime.utc_now()
    }
    
    # 2. Process
    thoughts = InnerDialog.process_thought("Processing input: #{inspect(input)}")
    
    # 3. Decide
    decision = DecisionMaker.decide(%{
      options: ["act", "wait", "delegate"],
      context: %{input: input, thoughts: thoughts}
    })
    
    # 4. Update state
    new_state = %{
      state: "active",
      last_decision: decision,
      timestamp: DateTime.utc_now()
    }
    
    Consciousness.update_state(new_state)
  end

  defp benchmark_parallel_thoughts do
    # Simulate parallel thought processing
    thought_streams = [
      "Stream 1: Analyzing immediate threats",
      "Stream 2: Planning long-term strategy",
      "Stream 3: Monitoring system resources",
      "Stream 4: Learning from recent patterns"
    ]
    
    # Process thoughts in parallel
    thought_streams
    |> Task.async_stream(&InnerDialog.process_thought/1, 
        max_concurrency: 4,
        timeout: 5000)
    |> Enum.to_list()
  end

  # Helper functions
  defp advance_state("nascent"), do: "emerging"
  defp advance_state("emerging"), do: "aware"
  defp advance_state("aware"), do: "conscious"
  defp advance_state("conscious"), do: "transcendent"
  defp advance_state(_), do: "nascent"

  defp generate_environment_data do
    %{
      temperature: :rand.uniform() * 100,
      pressure: :rand.uniform() * 50,
      noise_level: :rand.uniform(),
      threat_level: Enum.random([:low, :medium, :high]),
      resource_availability: :rand.uniform(),
      timestamp: DateTime.utc_now()
    }
  end

  defp generate_historical_data do
    1..10
    |> Enum.map(fn i ->
      %{
        decision_id: i,
        action_taken: Enum.random(["engage", "observe", "retreat"]),
        outcome: :rand.uniform(),
        timestamp: DateTime.add(DateTime.utc_now(), -i * 3600, :second)
      }
    end)
  end

  defp generate_sensory_data do
    %{
      visual: Enum.map(1..100, fn _ -> :rand.uniform(255) end),
      auditory: Enum.map(1..50, fn _ -> :rand.uniform() end),
      tactile: %{pressure: :rand.uniform(), temperature: :rand.uniform() * 40},
      temporal: DateTime.utc_now(),
      metadata: %{
        quality: :rand.uniform(),
        confidence: :rand.uniform()
      }
    }
  end
end

# Run the benchmark if this file is executed directly
if System.get_env("RUN_BENCHMARK") == "true" do
  AutonomousOpponent.Benchmarks.Consciousness.run()
end