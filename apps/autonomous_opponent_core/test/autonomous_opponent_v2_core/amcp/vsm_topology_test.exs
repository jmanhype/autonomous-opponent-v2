defmodule AutonomousOpponentV2Core.AMCP.VSMTopologyTest do
  use ExUnit.Case, async: false

  alias AutonomousOpponentV2Core.AMCP.VSMTopology
  alias AutonomousOpponentV2Core.EventBus

  describe "VSM topology (stub mode)" do
    setup do
      # Ensure we're running in stub mode for tests
      Application.put_env(:autonomous_opponent_core, :amqp_enabled, false)
      
      # Start EventBus for tests
      {:ok, _} = EventBus.start_link(name: :test_event_bus_topology)
      
      on_exit(fn ->
        Process.sleep(100)
      end)
      
      :ok
    end

    test "starts successfully in stub mode" do
      assert {:ok, pid} = VSMTopology.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "get_topology_info returns stub mode info" do
      {:ok, pid} = VSMTopology.start_link([])
      
      info = VSMTopology.get_topology_info()
      assert info.declared == false
      assert info.mode == :eventbus_only
      assert info.error == :amqp_not_available
      
      GenServer.stop(pid)
    end

    test "publish_event routes VSM events through EventBus" do
      {:ok, pid} = VSMTopology.start_link([])
      
      # Subscribe to the expected EventBus topic
      EventBus.subscribe(:vsm_s1_sensor_update)
      
      # Publish VSM event
      assert :ok = VSMTopology.publish_event(:s1, :sensor_update, %{value: 42})
      
      # Verify routing through EventBus
      assert_receive {:event, :vsm_s1_sensor_update, %{value: 42}}, 1000
      
      GenServer.stop(pid)
    end

    test "publish_algedonic routes algedonic signals through EventBus" do
      {:ok, pid} = VSMTopology.start_link([])
      
      # Subscribe to algedonic signals
      EventBus.subscribe(:algedonic_signal)
      
      # Publish algedonic signal
      assert :ok = VSMTopology.publish_algedonic(:critical, %{alert: "System overload"})
      
      # Verify routing
      assert_receive {:event, :algedonic_signal, data}, 1000
      assert data.severity == :critical
      assert data.payload.alert == "System overload"
      
      GenServer.stop(pid)
    end

    test "supports all VSM subsystems" do
      {:ok, pid} = VSMTopology.start_link([])
      
      subsystems = [:s1, :s2, :s3, :s3_star, :s4, :s5]
      
      for subsystem <- subsystems do
        event_name = :"vsm_#{subsystem}_test"
        EventBus.subscribe(event_name)
        
        assert :ok = VSMTopology.publish_event(subsystem, :test, %{subsystem: subsystem})
        
        assert_receive {:event, ^event_name, %{subsystem: ^subsystem}}, 1000
      end
      
      GenServer.stop(pid)
    end

    test "supports all algedonic severity levels" do
      {:ok, pid} = VSMTopology.start_link([])
      
      EventBus.subscribe(:algedonic_signal)
      
      severities = [:critical, :high, :medium, :low]
      
      for severity <- severities do
        assert :ok = VSMTopology.publish_algedonic(severity, %{test: severity})
        
        assert_receive {:event, :algedonic_signal, data}, 1000
        assert data.severity == severity
      end
      
      GenServer.stop(pid)
    end
  end

  @tag :integration
  @tag :skip
  describe "VSM topology (with AMQP)" do
    setup do
      Application.put_env(:autonomous_opponent_core, :amqp_enabled, true)
      :ok
    end

    test "declares VSM exchanges and queues" do
      # Implementation depends on AMQP availability
    end

    test "creates dead letter queues for each subsystem" do
      # Implementation depends on AMQP availability
    end

    test "sets up proper routing bindings" do
      # Implementation depends on AMQP availability
    end

    test "publishes events with correct routing keys" do
      # Implementation depends on AMQP availability
    end

    test "publishes algedonic signals with priority" do
      # Implementation depends on AMQP availability
    end
  end
end