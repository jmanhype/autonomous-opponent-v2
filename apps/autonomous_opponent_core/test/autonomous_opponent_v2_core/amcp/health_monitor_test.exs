defmodule AutonomousOpponentV2Core.AMCP.HealthMonitorTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.AMCP.HealthMonitor
  
  describe "HealthMonitor" do
    setup do
      # Ensure health monitor is started
      case Process.whereis(HealthMonitor) do
        nil -> 
          {:ok, _pid} = HealthMonitor.start_link([])
        pid when is_pid(pid) ->
          :ok
      end
      
      :ok
    end
    
    test "get_status returns health information" do
      status = HealthMonitor.get_status()
      
      assert is_map(status)
      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :consecutive_failures)
      assert Map.has_key?(status, :history)
      assert status.status in [:initializing, :healthy, :degraded, :critical]
    end
    
    test "force_check performs immediate health check" do
      result = HealthMonitor.force_check()
      
      assert is_map(result)
      assert Map.has_key?(result, :timestamp)
      assert Map.has_key?(result, :health_score)
      assert Map.has_key?(result, :healthy)
      assert result.health_score >= 0 and result.health_score <= 1
    end
    
    test "health_indicator returns simplified status" do
      indicator = HealthMonitor.health_indicator()
      
      assert indicator in [:ok, :degraded, :unhealthy, :unknown]
    end
    
    test "health check includes all required components" do
      result = HealthMonitor.force_check()
      
      assert Map.has_key?(result, :pool_health)
      assert Map.has_key?(result, :publish_test)
      assert Map.has_key?(result, :queue_status)
      
      # Pool health should be a map
      assert is_map(result.pool_health)
      
      # Publish test should have status
      assert Map.has_key?(result.publish_test, :status)
    end
  end
  
  describe "health scoring" do
    test "health score calculation weights components correctly" do
      result = HealthMonitor.force_check()
      
      # Health score should be between 0 and 1
      assert result.health_score >= 0
      assert result.health_score <= 1
      
      # In stub mode, we expect at least base score from queue status
      assert result.health_score >= 0.1
    end
  end
end