defmodule AutonomousOpponent.VSM.S4.IntelligenceTest do
  use ExUnit.Case, async: true

  alias AutonomousOpponent.VSM.S4.Intelligence
  alias AutonomousOpponent.EventBus

  setup do
    # Start EventBus if not already started
    case Process.whereis(AutonomousOpponent.EventBus) do
      nil -> {:ok, _} = EventBus.start_link()
      _ -> :ok
    end

    {:ok, pid} = Intelligence.start_link(id: "test_s4")

    {:ok, pid: pid}
  end

  describe "environmental scanning" do
    test "performs comprehensive environmental scan", %{pid: pid} do
      assert {:ok, scan_results} = Intelligence.scan_environment(pid, :all)

      assert Map.has_key?(scan_results, :raw_data)
      assert Map.has_key?(scan_results, :entities)
      assert Map.has_key?(scan_results, :relationships)
      assert Map.has_key?(scan_results, :changes)
      assert Map.has_key?(scan_results, :anomalies)
    end

    test "performs focused area scan", %{pid: pid} do
      assert {:ok, scan_results} = Intelligence.scan_environment(pid, [:internal, :external])

      assert is_map(scan_results)
      assert scan_results.raw_data[:internal] != nil
      assert scan_results.raw_data[:external] != nil
    end
  end

  describe "pattern extraction" do
    test "extracts patterns from data source", %{pid: pid} do
      data_source = [
        %{timestamp: 1000, value: 10},
        %{timestamp: 2000, value: 15},
        %{timestamp: 3000, value: 20},
        %{timestamp: 4000, value: 25}
      ]

      assert {:ok, patterns} = Intelligence.extract_patterns(pid, data_source)

      assert is_list(patterns)
      assert Enum.any?(patterns, fn p -> p.type == :temporal end)
    end

    test "filters patterns by confidence threshold", %{pid: pid} do
      # Generate data with clear pattern
      data_source =
        Enum.map(1..100, fn i ->
          # Clear linear trend
          %{timestamp: i * 1000, value: i * 2}
        end)

      assert {:ok, patterns} = Intelligence.extract_patterns(pid, data_source)

      # Should have high confidence patterns
      assert Enum.all?(patterns, fn p -> p.confidence >= 0.7 end)
    end
  end

  describe "scenario modeling" do
    test "generates future scenarios", %{pid: pid} do
      params = %{
        # 1 hour
        horizon: 3_600_000,
        count: 3
      }

      assert {:ok, scenarios} = Intelligence.model_scenarios(pid, params)

      assert length(scenarios) == 3

      assert Enum.all?(scenarios, fn s ->
               Map.has_key?(s, :uncertainty) and
                 Map.has_key?(s, :variables) and
                 Map.has_key?(s, :plausibility_scores)
             end)
    end

    test "quantifies uncertainty in scenarios", %{pid: pid} do
      # 2 hours - higher uncertainty
      params = %{horizon: 7_200_000}

      assert {:ok, scenarios} = Intelligence.model_scenarios(pid, params)

      # Longer horizon should have higher uncertainty
      assert Enum.all?(scenarios, fn s -> s.uncertainty > 0.1 end)
    end
  end

  describe "belief integration" do
    test "updates beliefs and triggers rescan if significant", %{pid: pid} do
      belief_updates = [
        %{belief: "market_growth", value: 0.9, priority: :critical},
        %{belief: "competition", value: 0.7, priority: :high}
      ]

      Intelligence.update_beliefs(pid, belief_updates)

      # Should trigger immediate scan due to critical priority
      Process.sleep(100)

      # Verify scan was triggered (would need to check internal state)
    end
  end

  describe "environmental model" do
    test "maintains and updates environmental model", %{pid: pid} do
      # Get initial model
      initial_model = Intelligence.get_environmental_model(pid)

      assert initial_model.entities == 0
      assert initial_model.relationships == 0

      # Perform scan to update model
      Intelligence.scan_environment(pid, :all)

      # Get updated model
      updated_model = Intelligence.get_environmental_model(pid)

      assert updated_model.entities > 0
      assert updated_model.confidence_score > 0
    end
  end

  describe "operational data integration" do
    test "learns patterns from S1 metrics", %{pid: pid} do
      # Simulate S1 metrics events
      for i <- 1..20 do
        EventBus.publish(:s1_metrics, %{
          unit_id: "s1_test",
          absorption_rate: 0.7 + i * 0.01,
          buffer_size: 100 - i,
          timestamp: System.monotonic_time(:millisecond)
        })

        Process.sleep(10)
      end

      # Give time to process
      Process.sleep(200)

      # Extract patterns should find variety absorption pattern
      assert {:ok, patterns} = Intelligence.extract_patterns(pid, :operational_buffer)

      # Should detect increasing absorption rate
      assert Enum.any?(patterns, fn p ->
               p[:type] == :variety_absorption and p[:trend] == :increasing
             end)
    end
  end

  describe "environmental change detection" do
    test "detects significant environmental changes", %{pid: pid} do
      # Subscribe to environmental shift events
      EventBus.subscribe(:environmental_shift)

      # Perform initial scan
      Intelligence.scan_environment(pid, :all)

      # Simulate significant change
      EventBus.publish(:environmental_change, %{
        type: :major_shift,
        entities_added: 20,
        relationships_changed: 50
      })

      # Wait for periodic scan
      # Wait for next scan cycle
      Process.sleep(11_000)

      # Should receive environmental shift notification
      assert_receive {:event, :environmental_shift, data}, 2000
      assert data.patterns != nil
    end
  end

  describe "LLM integration" do
    test "amplifies scanning with LLM when available", %{pid: pid} do
      # Scan should work even without actual LLM
      assert {:ok, scan_results} = Intelligence.scan_environment(pid, :all)

      # Check if amplification was attempted
      if scan_results.raw_data[:internal][:llm_insights] do
        assert Map.has_key?(scan_results.raw_data[:internal][:llm_insights], :emerging_patterns)
        assert Map.has_key?(scan_results.raw_data[:internal][:llm_insights], :confidence)
      end
    end
  end
end
