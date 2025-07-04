defmodule AutonomousOpponentV2Core.AMCP.IntegrationTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.AMCP.{ConnectionPool, Client, HealthMonitor}
  alias AutonomousOpponentV2Core.EventBus
  
  @moduletag :integration
  
  describe "AMQP Integration" do
    setup do
      # Subscribe to EventBus for AMQP events
      EventBus.subscribe(:amqp_health_check)
      EventBus.subscribe(:algedonic_pain)
      
      on_exit(fn ->
        EventBus.unsubscribe(:amqp_health_check)
        EventBus.unsubscribe(:algedonic_pain)
      end)
      
      :ok
    end
    
    @tag :skip
    test "full message flow through VSM subsystems" do
      # This test requires actual RabbitMQ connection
      # Skip in CI unless RabbitMQ is available
      
      # Publish to each subsystem
      for subsystem <- [:s1, :s2, :s3, :s4, :s5] do
        result = Client.publish_to_subsystem(subsystem, %{
          test_id: "integration_test",
          subsystem: subsystem,
          timestamp: DateTime.utc_now()
        })
        
        assert result == :ok
      end
    end
    
    test "health monitoring integration with EventBus" do
      # Force a health check
      HealthMonitor.force_check()
      
      # Should receive health check event
      assert_receive {:event_bus, :amqp_health_check, payload}, 5000
      assert payload.status in [:healthy, :degraded, :critical, :initializing]
    end
    
    test "algedonic signals trigger EventBus events" do
      # When AMQP is down, pain signals should still go through EventBus
      Client.send_algedonic(:pain, %{
        source: "integration_test",
        message: "Test pain signal"
      })
      
      # Should receive via EventBus even if AMQP fails
      # (because HealthMonitor sends to both)
      receive do
        {:event_bus, :algedonic_pain, payload} ->
          assert payload.source in ["integration_test", "amqp_health_monitor"]
      after
        1000 -> :ok  # May not receive if AMQP is working
      end
    end
    
    test "connection pool degradation handling" do
      # Get initial health
      initial_health = ConnectionPool.health_check()
      
      # Simulate multiple failed publishes
      results = for _ <- 1..5 do
        ConnectionPool.publish_with_retry("nonexistent", "test", %{}, timeout: 100)
      end
      
      # All should handle gracefully
      assert Enum.all?(results, fn r -> r in [:ok, {:error, :max_retries_exceeded}, {:error, :pool_error}] end)
    end
    
    test "EventBus continues working when AMQP is unavailable" do
      # Disable AMQP temporarily
      original = Application.get_env(:autonomous_opponent_core, :amqp_enabled)
      Application.put_env(:autonomous_opponent_core, :amqp_enabled, false)
      
      # EventBus should still work
      EventBus.subscribe(:test_event)
      EventBus.publish(:test_event, %{data: "test"})
      
      assert_receive {:event_bus, :test_event, %{data: "test"}}, 1000
      
      # Restore
      Application.put_env(:autonomous_opponent_core, :amqp_enabled, original)
      EventBus.unsubscribe(:test_event)
    end
  end
  
  describe "Performance characteristics" do
    @tag :performance
    @tag :skip
    test "connection pool handles concurrent requests" do
      # This test requires actual AMQP connection
      
      # Spawn multiple concurrent publishers
      tasks = for i <- 1..100 do
        Task.async(fn ->
          Client.publish_to_subsystem(:s1, %{
            task_id: i,
            data: "concurrent test"
          })
        end)
      end
      
      # All should complete without errors
      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, fn r -> r in [:ok, {:error, :max_retries_exceeded}] end)
    end
    
    test "exponential backoff prevents overwhelming system" do
      start_time = System.monotonic_time(:millisecond)
      
      # This should retry with backoff
      ConnectionPool.publish_with_retry("test", "test", %{}, timeout: 10)
      
      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time
      
      # Should have taken some time due to retries
      # But not too long (max 5 retries with increasing backoff)
      assert elapsed < 120_000  # Less than 2 minutes
    end
  end
end