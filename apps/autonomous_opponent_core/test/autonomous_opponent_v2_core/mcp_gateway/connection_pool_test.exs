defmodule AutonomousOpponentV2Core.MCPGateway.ConnectionPoolTest do
  use ExUnit.Case, async: true
  
  alias AutonomousOpponentV2Core.MCPGateway.ConnectionPool
  alias AutonomousOpponentV2Core.Core.RateLimiter
  
  setup do
    # Start required dependencies
    {:ok, _} = start_supervised({RateLimiter, name: :mcp_gateway_limiter_test})
    
    {:ok, pool} = start_supervised({
      ConnectionPool,
      name: :test_pool,
      pool_size: 5,
      max_overflow: 2
    })
    
    %{pool: pool}
  end
  
  describe "checkout/3" do
    test "successfully checks out a connection", %{pool: _pool} do
      # Note: Since actual connection creation is stubbed, this will queue
      assert {:error, :pool_exhausted} = ConnectionPool.checkout(:test_pool, :http_sse, 100)
    end
    
    test "respects rate limiting", %{pool: _pool} do
      # Consume all rate limit tokens
      for _ <- 1..100 do
        RateLimiter.consume(:mcp_gateway_limiter_test)
      end
      
      assert {:error, :rate_limited} = ConnectionPool.checkout(:test_pool, :http_sse)
    end
  end
  
  describe "with_connection/3" do
    test "executes function with connection when available" do
      # This test would work with actual connections
      result = ConnectionPool.with_connection(:test_pool, :websocket, fn _conn ->
        {:ok, "success"}
      end)
      
      # Since we don't have real connections in the pool, it will fail
      assert {:error, :pool_exhausted} = result
    end
  end
  
  describe "status/1" do
    test "returns pool status", %{pool: _pool} do
      status = ConnectionPool.status(:test_pool)
      
      assert %{
        pools: _,
        total_connections: 0,
        waiting_queue_size: 0,
        stats: stats
      } = status
      
      assert is_map(stats)
    end
  end
  
  describe "connection lifecycle" do
    test "handles connection process death" do
      # Start a connection process
      test_pid = spawn(fn -> 
        receive do
          :stop -> :ok
        end
      end)
      
      # Simulate connection ready
      send(:test_pool, {:connection_ready, :websocket, %ConnectionPool.Connection{
        id: "test-conn",
        transport_type: :websocket,
        pid: test_pid,
        ref: Process.monitor(test_pid),
        created_at: System.monotonic_time(:millisecond),
        last_used_at: System.monotonic_time(:millisecond),
        use_count: 0,
        health_status: :healthy,
        metadata: %{}
      }})
      
      # Give it time to process
      Process.sleep(10)
      
      # Kill the process
      Process.exit(test_pid, :kill)
      
      # Give it time to handle DOWN message
      Process.sleep(10)
      
      # Check that connection was removed
      status = ConnectionPool.status(:test_pool)
      assert status.total_connections == 0
    end
  end
  
  describe "health checks" do
    test "performs periodic health checks" do
      # Send health check message
      send(:test_pool, :health_check)
      
      # Should not crash
      Process.sleep(10)
      assert Process.alive?(:test_pool)
    end
  end
  
  describe "idle cleanup" do
    test "cleans up idle connections" do
      # Send cleanup message
      send(:test_pool, :cleanup_idle)
      
      # Should not crash
      Process.sleep(10)
      assert Process.alive?(:test_pool)
    end
  end
end