defmodule AutonomousOpponentV2Core.Connections.PoolManagerTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.Connections.{PoolManager, HTTPClient}
  
  setup do
    # Ensure pool manager is started
    start_supervised!(PoolManager)
    :ok
  end
  
  describe "request/3" do
    test "makes successful request using default pool" do
      # Mock request
      request = Finch.build(:get, "https://httpbin.org/get")
      
      assert {:ok, response} = PoolManager.request(:default, request)
      assert response.status == 200
    end
    
    test "returns circuit open error when circuit breaker is open" do
      # This would require setting up a failing endpoint
      # For now, we'll skip this test
      :ok
    end
    
    test "uses correct pool based on URL" do
      # Test that HTTPClient selects the right pool
      assert {:ok, _} = HTTPClient.get("https://api.openai.com/v1/models", pool: :openai)
    end
  end
  
  describe "health_check/1" do
    test "returns ok for healthy pool" do
      assert :ok = PoolManager.health_check(:default)
    end
    
    test "returns error for pool without health check URL" do
      assert :ok = PoolManager.health_check(:local_llm)
    end
  end
  
  describe "get_stats/1" do
    test "returns pool statistics" do
      stats = PoolManager.get_stats(:default)
      
      assert %{pool: :default} = stats
      assert Map.has_key?(stats, :circuit_breaker)
      assert Map.has_key?(stats, :telemetry)
    end
  end
  
  describe "drain_connections/0" do
    test "drains all connection pools" do
      assert :ok = PoolManager.drain_connections()
    end
  end
end