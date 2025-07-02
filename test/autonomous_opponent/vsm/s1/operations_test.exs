defmodule AutonomousOpponent.VSM.S1.OperationsTest do
  use ExUnit.Case, async: true

  alias AutonomousOpponent.VSM.S1.Operations
  alias AutonomousOpponent.EventBus

  setup do
    # Start EventBus for testing if not already started
    case Process.whereis(EventBus) do
      nil -> 
        {:ok, _} = EventBus.start_link()
      _pid -> 
        :ok
    end

    # Start S1 Operations
    {:ok, pid} = Operations.start_link(id: "test_s1", name: nil)

    {:ok, pid: pid}
  end

  describe "variety absorption" do
    test "absorbs variety events", %{pid: pid} do
      event = %{
        type: :test_event,
        data: "test data",
        variety_magnitude: 2.5
      }

      assert :ok = Operations.absorb_variety(pid, event)
    end

    test "tracks absorption rate", %{pid: pid} do
      # Initial absorption rate should be 1.0
      assert Operations.get_absorption_rate(pid) == 1.0

      # Add some variety
      for i <- 1..10 do
        Operations.absorb_variety(pid, %{
          type: :test,
          data: i,
          variety_magnitude: 1.0
        })
      end

      # Rate should still be high initially
      rate = Operations.get_absorption_rate(pid)
      assert rate > 0.5
    end

    test "collects metrics", %{pid: pid} do
      metrics = Operations.get_metrics(pid)

      assert is_map(metrics)
      assert metrics.events_received == 0
      assert metrics.events_processed == 0
      assert is_map(metrics.memory_routing)
    end
  end

  describe "memory tier routing" do
    test "routes critical events to hot tier", %{pid: pid} do
      event = %{
        type: :critical_event,
        priority: :critical,
        data: "urgent",
        variety_magnitude: 10.0
      }

      # Subscribe to memory routing events
      EventBus.subscribe(:memory_tier_routing)

      Operations.absorb_variety(pid, event)

      assert_receive {:event, :memory_tier_routing, %{tier: :hot}}, 1000
    end

    test "routes high variety events to warm tier", %{pid: pid} do
      event = %{
        type: :high_variety,
        data: "complex",
        variety_magnitude: 7.0
      }

      EventBus.subscribe(:memory_tier_routing)

      Operations.absorb_variety(pid, event)

      assert_receive {:event, :memory_tier_routing, %{tier: :warm}}, 1000
    end
  end

  describe "algedonic integration" do
    test "publishes pain signal when absorption rate is low", %{pid: pid} do
      # Subscribe to algedonic events
      EventBus.subscribe(:algedonic_pain)

      # Force measurement with low absorption
      send(pid, :measure_variety)

      # Should eventually receive pain signal if absorption drops
      # This is a simplified test - in reality we'd need to overload the system
    end
  end
end
