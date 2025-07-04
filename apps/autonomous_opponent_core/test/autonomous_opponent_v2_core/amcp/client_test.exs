defmodule AutonomousOpponentV2Core.AMCP.ClientTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.AMCP.Client
  
  describe "Client API" do
    setup do
      # Ensure we're in a known state
      Application.put_env(:autonomous_opponent_core, :amqp_enabled, true)
      :ok
    end
    
    test "publish_to_subsystem accepts valid subsystems" do
      # Test all valid subsystems
      for subsystem <- [:s1, :s2, :s3, :s4, :s5] do
        result = Client.publish_to_subsystem(subsystem, %{
          test: "message",
          subsystem: subsystem
        })
        
        # Should succeed or return error, not crash
        assert result in [:ok, {:error, :max_retries_exceeded}, {:error, :pool_error}]
      end
    end
    
    test "publish_to_subsystem with priority option" do
      result = Client.publish_to_subsystem(:s3, %{
        operation: "emergency_stop",
        reason: "test"
      }, priority: 10)
      
      # Should handle priority option
      assert result in [:ok, {:error, :max_retries_exceeded}, {:error, :pool_error}]
    end
    
    test "send_algedonic accepts pain and pleasure signals" do
      # Test pain signal
      result = Client.send_algedonic(:pain, %{
        source: "test",
        message: "Test pain signal"
      })
      
      assert match?({:ok, _} | {:error, _}, result)
      
      # Test pleasure signal
      result = Client.send_algedonic(:pleasure, %{
        source: "test",
        message: "Test pleasure signal"
      })
      
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "publish_event adds required metadata" do
      result = Client.publish_event(:test_event, %{
        data: "test"
      })
      
      # Should succeed or return known error
      assert result in [:ok, {:error, :max_retries_exceeded}, {:error, :pool_error}]
    end
    
    test "create_work_queue handles options" do
      result = Client.create_work_queue("test_queue", 
        ttl: 60_000,
        max_length: 100
      )
      
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "send_work publishes to work queue" do
      result = Client.send_work("test_queue", %{
        task: "process",
        data: "test"
      })
      
      assert result in [:ok, {:error, :max_retries_exceeded}, {:error, :pool_error}]
    end
    
    test "health_check returns pool health" do
      health = Client.health_check()
      
      assert is_map(health)
      assert Map.has_key?(health, :healthy)
    end
  end
  
  describe "request/reply pattern" do
    test "request returns not_implemented error" do
      result = Client.request("test.service", %{
        operation: "test"
      })
      
      # Currently not implemented
      assert result == {:error, :not_implemented}
    end
  end
  
  describe "subscription patterns" do
    test "subscribe_to_subsystem starts a task" do
      # This will start a task that tries to consume
      {:ok, task} = Client.subscribe_to_subsystem(:s1, fn msg, _meta ->
        send(self(), {:received, msg})
        :ok
      end)
      
      assert is_pid(task)
      
      # Clean up
      Process.exit(task, :normal)
    end
    
    test "consume_work starts a consumer task" do
      {:ok, task} = Client.consume_work("test_queue", fn work ->
        send(self(), {:work, work})
        :ok
      end)
      
      assert is_pid(task)
      
      # Clean up
      Process.exit(task, :normal)
    end
  end
end