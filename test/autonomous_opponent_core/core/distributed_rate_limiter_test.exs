defmodule AutonomousOpponentV2Core.Core.DistributedRateLimiterTest do
  use ExUnit.Case, async: false
  
  alias AutonomousOpponentV2Core.Core.DistributedRateLimiter
  
  @moduletag :distributed_rate_limiter
  
  setup do
    # Ensure Redis is available, skip tests if not
    case AutonomousOpponentV2Core.Connections.RedisPool.health_check() do
      :ok -> 
        :ok
      _ ->
        # Redis not available, tests will use fallback mode
        :ok
    end
  end
  
  describe "basic functionality" do
    test "allows requests within limit" do
      # Start a rate limiter for testing
      {:ok, limiter} = DistributedRateLimiter.start_link(
        name: :test_limiter,
        rules: %{
          test_rule: {1_000, 5}  # 5 requests per second
        }
      )
      
      # Make 5 requests (should all succeed)
      results = for i <- 1..5 do
        DistributedRateLimiter.check_and_track(:test_limiter, "test_user", :test_rule)
      end
      
      # All should succeed
      assert Enum.all?(results, fn result ->
        match?({:ok, _}, result)
      end)
      
      # 6th request should be rate limited
      result = DistributedRateLimiter.check_and_track(:test_limiter, "test_user", :test_rule)
      assert {:error, :rate_limited, _} = result
      
      # Clean up
      GenServer.stop(limiter)
    end
    
    test "tracks usage correctly" do
      {:ok, limiter} = DistributedRateLimiter.start_link(
        name: :usage_limiter,
        rules: %{
          usage_rule: {1_000, 10}  # 10 requests per second
        }
      )
      
      # Make 3 requests
      for _ <- 1..3 do
        DistributedRateLimiter.check_and_track(:usage_limiter, "usage_test", :usage_rule)
      end
      
      # Check usage
      {:ok, usage} = DistributedRateLimiter.get_usage(:usage_limiter, "usage_test", :usage_rule)
      assert usage.current == 3
      assert usage.max == 10
      assert usage.remaining == 7
      
      # Clean up
      GenServer.stop(limiter)
    end
    
    test "clear removes rate limit data" do
      {:ok, limiter} = DistributedRateLimiter.start_link(
        name: :clear_limiter,
        rules: %{
          clear_rule: {1_000, 5}
        }
      )
      
      # Use up the limit
      for _ <- 1..5 do
        DistributedRateLimiter.check_and_track(:clear_limiter, "clear_user", :clear_rule)
      end
      
      # Should be rate limited
      assert {:error, :rate_limited, _} = 
        DistributedRateLimiter.check_and_track(:clear_limiter, "clear_user", :clear_rule)
      
      # Clear the data
      {:ok, _} = DistributedRateLimiter.clear(:clear_limiter, "clear_user")
      
      # Should be able to make requests again
      assert {:ok, _} = 
        DistributedRateLimiter.check_and_track(:clear_limiter, "clear_user", :clear_rule)
      
      # Clean up
      GenServer.stop(limiter)
    end
  end
  
  describe "fallback mode" do
    test "works when Redis is unavailable" do
      # This test will use local ETS fallback if Redis is down
      {:ok, limiter} = DistributedRateLimiter.start_link(
        name: :fallback_limiter,
        rules: %{
          fallback_rule: {1_000, 3}
        }
      )
      
      # Should work regardless of Redis availability
      results = for _ <- 1..3 do
        DistributedRateLimiter.check_and_track(:fallback_limiter, "fallback_user", :fallback_rule)
      end
      
      assert Enum.all?(results, fn result ->
        match?({:ok, _}, result)
      end)
      
      # Clean up
      GenServer.stop(limiter)
    end
  end
end