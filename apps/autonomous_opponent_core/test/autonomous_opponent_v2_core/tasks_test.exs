defmodule AutonomousOpponentV2Core.TasksTest do
  use ExUnit.Case
  
  describe "Task 1: CircuitBreaker" do
    test "module exists and starts" do
      alias AutonomousOpponentV2Core.Core.CircuitBreaker
      
      {:ok, pid} = CircuitBreaker.start_link(name: :test_breaker, threshold: 5)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
  
  describe "Task 2: RateLimiter" do
    test "module exists and starts" do
      alias AutonomousOpponentV2Core.Core.RateLimiter
      
      {:ok, pid} = RateLimiter.start_link(name: :test_limiter, rate: 10, interval: 1000)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
  
  describe "Task 3: Metrics" do
    test "module exists and starts" do
      alias AutonomousOpponentV2Core.Core.Metrics
      
      {:ok, pid} = Metrics.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
  
  describe "Task 4: HNSW Index" do
    test "module exists and can be initialized" do
      alias AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex
      
      {:ok, index} = HNSWIndex.new(m: 16, ef_construction: 200)
      assert index.m == 16
      assert index.ef_construction == 200
    end
  end
  
  describe "Task 5: Vector Quantizer" do
    test "module exists and starts" do
      alias AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore.Quantizer
      
      {:ok, pid} = Quantizer.start_link(vector_dim: 128, num_subquantizers: 8)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
  
  describe "EventBus" do
    test "EventBus works after cleanup" do
      alias AutonomousOpponentV2Core.EventBus
      
      # Should be able to publish without errors
      EventBus.publish(:test_event, %{data: "test"})
      assert true
    end
  end
end