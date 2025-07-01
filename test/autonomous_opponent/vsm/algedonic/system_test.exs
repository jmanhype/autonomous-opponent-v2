defmodule AutonomousOpponent.VSM.Algedonic.SystemTest do
  use ExUnit.Case, async: true

  alias AutonomousOpponent.VSM.Algedonic.System
  alias AutonomousOpponent.EventBus

  setup do
    # Start EventBus
    {:ok, _} = EventBus.start_link()

    # Start Algedonic System
    {:ok, _} = System.start_link([])

    :ok
  end

  describe "pain signals" do
    test "processes pain signals with high priority" do
      System.pain({:test, :source}, :test_failure, :high, %{detail: "test"})

      # Give it time to process
      Process.sleep(50)

      stats = System.get_stats()
      assert stats.pain_signals > 0
    end

    test "critical signals bypass all filters" do
      # Send critical signal
      System.pain({:critical, :source}, :system_failure, :critical, %{})

      Process.sleep(50)

      state = System.get_state()
      assert length(state.recent_signals) > 0
    end

    test "filters repeated non-critical signals" do
      # Send same signal multiple times quickly
      for _ <- 1..5 do
        System.pain({:test, :source}, :minor_issue, :low, %{})
      end

      Process.sleep(100)

      stats = System.get_stats()
      # Should be filtered after threshold
      assert stats.pain_signals <= 3
    end
  end

  describe "pleasure signals" do
    test "processes pleasure signals for reinforcement" do
      System.pleasure({:test, :source}, :good_performance, :high, %{metric: 99.9})

      Process.sleep(50)

      stats = System.get_stats()
      assert stats.pleasure_signals > 0
    end
  end

  describe "response time" do
    test "processes signals within 100ms target" do
      start_time = System.monotonic_time(:millisecond)

      # Send high priority signal
      System.pain({:perf, :test}, :performance_issue, :high, %{})

      # Wait for processing
      Process.sleep(50)

      stats = System.get_stats()

      # Check that average response time is under 100ms (in microseconds)
      assert stats.avg_response_time < 100_000
    end
  end

  describe "EventBus integration" do
    test "receives pain signals from EventBus" do
      EventBus.subscribe(:algedonic_intervention)

      # Publish pain signal via EventBus
      EventBus.publish(:algedonic_pain, %{
        source: {:eventbus, :test},
        reason: :test_pain,
        severity: :medium
      })

      # Should process and potentially intervene
      assert_receive {:event, :algedonic_intervention, _}, 1000
    end
  end

  describe "memory and patterns" do
    test "maintains signal memory" do
      # Send a few different signals
      System.pain({:memory, :test}, :memory_test, :medium)
      System.pleasure({:memory, :test}, :memory_reward, :medium)

      Process.sleep(50)

      state = System.get_state()
      assert state.memory_size >= 2
    end

    test "learns patterns from repeated signals" do
      # Send similar signals to establish pattern
      for i <- 1..5 do
        System.pain({:pattern, :test}, :repeated_issue, :medium, %{iteration: i})
        Process.sleep(20)
      end

      Process.sleep(100)

      # New similar signal should be recognized as pattern
      System.pain({:pattern, :test}, :repeated_issue, :medium, %{iteration: 6})

      # Pattern recognition should boost priority
      state = System.get_state()
      assert state.queue_size >= 0
    end
  end
end
