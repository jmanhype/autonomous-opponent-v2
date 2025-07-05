defmodule AutonomousOpponentV2Core.WebGateway.Pool.ConnectionPoolTest do
  @moduledoc """
  Tests for the Web Gateway connection pool using poolboy.
  """
  
  use ExUnit.Case, async: false  # Not async due to pool limitations
  
  alias AutonomousOpponentV2Core.WebGateway.Pool.ConnectionPool
  alias AutonomousOpponentV2Core.EventBus
  
  setup do
    # Subscribe to pool events
    EventBus.subscribe(:mcp_pool_health)
    EventBus.subscribe(:vsm_algedonic)
    
    # Ensure pool is started
    unless Process.whereis(ConnectionPool) do
      {:ok, _} = ConnectionPool.start_link(pool_size: 5, overflow: 2)
    end
    
    :ok
  end
  
  describe "connection checkout/checkin" do
    test "checks out connection from pool" do
      assert {:ok, worker} = ConnectionPool.checkout("test_conn_1", "client_1")
      assert is_pid(worker)
      
      # Verify worker state
      state = GenServer.call(worker, :get_state)
      assert state.connection_id == "test_conn_1"
      assert state.client_id == "client_1"
      assert state.checked_out_at != nil
      
      # Return to pool
      assert ConnectionPool.checkin(worker) == :ok
    end
    
    test "checks out with metadata" do
      metadata = %{transport: :websocket, region: "us-east"}
      assert {:ok, worker} = ConnectionPool.checkout("test_conn_2", "client_2", metadata)
      
      state = GenServer.call(worker, :get_state)
      assert state.metadata == metadata
      
      ConnectionPool.checkin(worker)
    end
    
    test "handles pool exhaustion with timeout" do
      # Check out all connections
      workers = for i <- 1..7 do  # pool_size + overflow
        {:ok, worker} = ConnectionPool.checkout("conn_#{i}", "client_#{i}")
        worker
      end
      
      # Next checkout should timeout
      assert {:error, :pool_timeout} = ConnectionPool.checkout("overflow", "overflow_client")
      
      # Should trigger algedonic signal
      assert_receive {:event_bus, :vsm_algedonic, event}
      assert event.severity == :high
      assert event.reason == :connection_pool_exhausted
      
      # Return workers
      Enum.each(workers, &ConnectionPool.checkin/1)
    end
    
    test "checks in by connection ID" do
      {:ok, worker} = ConnectionPool.checkout("checkin_test", "client")
      
      # Checkin by connection ID
      assert ConnectionPool.checkin("checkin_test") == :ok
      
      # Worker should be back in pool
      {:ok, new_worker} = ConnectionPool.checkout("new_conn", "new_client")
      assert is_pid(new_worker)  # Pool not exhausted
      ConnectionPool.checkin(new_worker)
    end
  end
  
  describe "pool statistics" do
    test "provides pool statistics" do
      # Get initial stats
      stats = ConnectionPool.get_stats()
      
      assert is_integer(stats.pool_size)
      assert is_integer(stats.overflow)
      assert is_integer(stats.checked_out)
      assert is_integer(stats.available)
      assert is_integer(stats.overflow_active)
      
      # Check out a connection
      {:ok, worker} = ConnectionPool.checkout("stats_conn", "stats_client")
      
      new_stats = ConnectionPool.get_stats()
      assert new_stats.checked_out == stats.checked_out + 1
      
      ConnectionPool.checkin(worker)
    end
  end
  
  describe "metadata updates" do
    test "updates connection metadata" do
      {:ok, worker} = ConnectionPool.checkout("meta_conn", "meta_client")
      
      # Update metadata
      new_metadata = %{status: "active", last_message: DateTime.utc_now()}
      ConnectionPool.update_metadata(worker, new_metadata)
      
      # Verify update
      state = GenServer.call(worker, :get_state)
      assert state.metadata == new_metadata
      assert state.last_used_at != nil
      
      ConnectionPool.checkin(worker)
    end
  end
  
  describe "health monitoring" do
    test "performs health check on pool" do
      # Check health with low utilization
      health = ConnectionPool.health_check()
      assert health == :healthy
      
      # Should publish health event
      assert_receive {:event_bus, :mcp_pool_health, event}
      assert event.status == :healthy
      assert is_map(event.stats)
      assert is_float(event.utilization)
    end
    
    test "detects critical pool utilization" do
      # Check out most connections
      workers = for i <- 1..6 do  # > 90% of pool+overflow
        {:ok, worker} = ConnectionPool.checkout("util_#{i}", "client_#{i}")
        worker
      end
      
      # Health check should show critical
      health = ConnectionPool.health_check()
      assert health == :critical
      
      # Should trigger algedonic signal
      assert_receive {:event_bus, :vsm_algedonic, event}
      assert event.severity == :high
      assert event.source == :web_gateway
      assert match?({:pool_critical, _}, event.reason)
      
      # Return workers
      Enum.each(workers, &ConnectionPool.checkin/1)
    end
    
    test "detects warning pool utilization" do
      # Check out ~75% of pool
      workers = for i <- 1..5 do
        {:ok, worker} = ConnectionPool.checkout("warn_#{i}", "client_#{i}")
        worker
      end
      
      health = ConnectionPool.health_check()
      assert health == :warning
      
      # Return workers
      Enum.each(workers, &ConnectionPool.checkin/1)
    end
  end
  
  describe "worker lifecycle" do
    test "worker maintains connection state" do
      {:ok, worker} = ConnectionPool.checkout("lifecycle_conn", "lifecycle_client")
      
      # Initial state
      state1 = GenServer.call(worker, :get_state)
      assert state1.connection_id == "lifecycle_conn"
      
      # Checkin
      ConnectionPool.checkin(worker)
      
      # State should be cleared
      state2 = GenServer.call(worker, :get_state)
      assert state2.connection_id == nil
      assert state2.client_id == nil
      assert state2.checked_out_at == nil
    end
    
    test "worker tracks last used timestamp" do
      {:ok, worker} = ConnectionPool.checkout("timestamp_conn", "timestamp_client")
      
      initial_time = GenServer.call(worker, :get_state).last_used_at
      
      :timer.sleep(10)
      
      # Update metadata to trigger timestamp update
      ConnectionPool.update_metadata(worker, %{touched: true})
      
      new_time = GenServer.call(worker, :get_state).last_used_at
      assert DateTime.compare(new_time, initial_time) == :gt
      
      ConnectionPool.checkin(worker)
    end
  end
  
  describe "concurrent access" do
    test "handles concurrent checkouts" do
      # Spawn multiple processes to checkout connections
      parent = self()
      
      tasks = for i <- 1..5 do
        Task.async(fn ->
          case ConnectionPool.checkout("concurrent_#{i}", "client_#{i}") do
            {:ok, worker} ->
              :timer.sleep(10)
              ConnectionPool.checkin(worker)
              send(parent, {:checkout_success, i})
            {:error, reason} ->
              send(parent, {:checkout_error, i, reason})
          end
        end)
      end
      
      # Wait for all tasks
      Task.await_many(tasks)
      
      # All should succeed
      for i <- 1..5 do
        assert_receive {:checkout_success, ^i}
      end
    end
  end
end