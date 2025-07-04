defmodule AutonomousOpponentV2Core.AMCP.MessageHandlerTest do
  use ExUnit.Case, async: false

  alias AutonomousOpponentV2Core.AMCP.MessageHandler
  alias AutonomousOpponentV2Core.EventBus

  describe "message handler (stub mode)" do
    setup do
      # Ensure we're running in stub mode for tests
      Application.put_env(:autonomous_opponent_core, :amqp_enabled, false)
      
      # Start EventBus for tests
      {:ok, _} = EventBus.start_link(name: :test_event_bus_handler)
      
      on_exit(fn ->
        Process.sleep(100)
      end)
      
      :ok
    end

    test "starts successfully in stub mode" do
      assert {:ok, pid} = MessageHandler.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "publish routes through EventBus in stub mode" do
      {:ok, pid} = MessageHandler.start_link([])
      
      # Subscribe to EventBus to verify routing
      EventBus.subscribe(:amqp_stub_test_route)
      
      # Publish a message
      assert :ok = MessageHandler.publish("test_exchange", "test_route", %{data: "test"}, [])
      
      # Verify it was routed through EventBus
      assert_receive {:event, :amqp_stub_test_route, %{data: "test"}}, 1000
      
      GenServer.stop(pid)
    end

    test "consume returns EventBus mode info" do
      {:ok, pid} = MessageHandler.start_link([])
      
      handler = fn _payload, _meta -> :ok end
      result = MessageHandler.consume("test_queue", handler, [])
      
      assert {:ok, info} = result
      assert info.consumer_tag == :amqp_stub_test_queue
      assert info.mode == :eventbus
      
      GenServer.stop(pid)
    end

    test "get_stats returns basic stats" do
      {:ok, pid} = MessageHandler.start_link([])
      
      # Publish some messages
      MessageHandler.publish("test", "route1", %{}, [])
      MessageHandler.publish("test", "route2", %{}, [])
      
      stats = MessageHandler.get_stats()
      assert stats.publish == 2
      
      GenServer.stop(pid)
    end

    test "publish_vsm_event routes through EventBus" do
      {:ok, pid} = MessageHandler.start_link([])
      
      EventBus.subscribe(:vsm_s3_state_change)
      
      MessageHandler.publish_vsm_event(:s3, :state_change, %{new_state: :active})
      
      assert_receive {:event, :vsm_s3_state_change, %{new_state: :active}}, 1000
      
      GenServer.stop(pid)
    end

    test "publish_algedonic routes through EventBus" do
      {:ok, pid} = MessageHandler.start_link([])
      
      EventBus.subscribe(:algedonic_signal)
      
      MessageHandler.publish_algedonic(:high, %{message: "System stress"})
      
      assert_receive {:event, :algedonic_signal, data}, 1000
      assert data.severity == :high
      assert data.payload.message == "System stress"
      
      GenServer.stop(pid)
    end
  end

  @tag :integration
  @tag :skip
  describe "message handler (with AMQP)" do
    setup do
      Application.put_env(:autonomous_opponent_core, :amqp_enabled, true)
      :ok
    end

    test "publishes messages with retry logic" do
      # Implementation depends on AMQP availability
    end

    test "handles rate limiting" do
      # Implementation depends on AMQP availability
    end

    test "implements exponential backoff for retries" do
      # Implementation depends on AMQP availability
    end

    test "wraps consumer handlers with error handling" do
      # Implementation depends on AMQP availability
    end

    test "sends failed messages to dead letter queue" do
      # Implementation depends on AMQP availability
    end
  end
end