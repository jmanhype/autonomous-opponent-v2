defmodule AutonomousOpponentV2Core.AMCP.HealthMonitorTest do
  use ExUnit.Case, async: false

  alias AutonomousOpponentV2Core.AMCP.HealthMonitor
  alias AutonomousOpponentV2Core.EventBus

  describe "health monitor (stub mode)" do
    setup do
      # Ensure we're running in stub mode for tests
      Application.put_env(:autonomous_opponent_core, :amqp_enabled, false)
      
      # Start EventBus for tests
      {:ok, _} = EventBus.start_link(name: :test_event_bus)
      
      on_exit(fn ->
        Process.sleep(100)
      end)
      
      :ok
    end

    test "starts successfully in stub mode" do
      assert {:ok, pid} = HealthMonitor.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "get_health returns unavailable status in stub mode" do
      {:ok, pid} = HealthMonitor.start_link([])
      
      health = HealthMonitor.get_health()
      assert health.status == :unavailable
      assert health.healthy_connections == 0
      assert health.total_connections == 0
      assert health.error == :amqp_not_available
      
      GenServer.stop(pid)
    end

    test "healthy? returns false in stub mode" do
      {:ok, pid} = HealthMonitor.start_link([])
      
      refute HealthMonitor.healthy?()
      
      GenServer.stop(pid)
    end

    test "responds to health check requests via EventBus" do
      {:ok, pid} = HealthMonitor.start_link([])
      
      # Subscribe to health check responses
      EventBus.subscribe(:health_check_response)
      
      # Send health check request
      EventBus.publish(:health_check_request, %{})
      
      # Wait for response
      assert_receive {:event, :health_check_response, data}, 1000
      assert data.component == :amqp
      assert data.status == :unavailable
      
      GenServer.stop(pid)
    end
  end

  @tag :integration
  @tag :skip
  describe "health monitor (with AMQP)" do
    setup do
      Application.put_env(:autonomous_opponent_core, :amqp_enabled, true)
      :ok
    end

    test "monitors connection health" do
      # Implementation depends on AMQP availability
    end

    test "triggers algedonic signals for prolonged unhealthy state" do
      # Implementation depends on AMQP availability
    end

    test "publishes health change events" do
      # Implementation depends on AMQP availability
    end
  end
end