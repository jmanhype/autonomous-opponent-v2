defmodule AutonomousOpponent.Core.RateLimiterTest do
  use ExUnit.Case, async: true
  alias AutonomousOpponent.Core.RateLimiter

  setup do
    # Start a rate limiter for testing
    {:ok, pid} =
      RateLimiter.start_link(
        name: :test_limiter,
        bucket_size: 10,
        refill_rate: 5,
        refill_interval_ms: 100,
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    {:ok, limiter: :test_limiter}
  end

  describe "basic token consumption" do
    test "allows requests when tokens are available", %{limiter: limiter} do
      assert {:ok, 9} = RateLimiter.consume(limiter, 1)
      assert {:ok, 8} = RateLimiter.consume(limiter, 1)
      assert {:ok, 6} = RateLimiter.consume(limiter, 2)
    end

    test "rejects requests when tokens are exhausted", %{limiter: limiter} do
      # Consume all tokens
      assert {:ok, 0} = RateLimiter.consume(limiter, 10)

      # Next request should be rate limited
      assert {:error, :rate_limited} = RateLimiter.consume(limiter, 1)
    end

    test "rejects requests asking for more tokens than bucket size", %{limiter: limiter} do
      assert {:error, :rate_limited} = RateLimiter.consume(limiter, 11)
    end

    test "handles burst requests correctly", %{limiter: limiter} do
      # Burst of 5 requests
      for _ <- 1..5 do
        assert {:ok, _} = RateLimiter.consume(limiter, 1)
      end

      # Should have 5 tokens left
      assert {:ok, 0} = RateLimiter.consume(limiter, 5)

      # Next request should fail
      assert {:error, :rate_limited} = RateLimiter.consume(limiter, 1)
    end
  end

  describe "per-client rate limiting" do
    test "tracks tokens separately for different clients", %{limiter: limiter} do
      # Client A consumes tokens
      assert {:ok, 0} = RateLimiter.consume_for_client(limiter, "client_a", 1)

      # Client B should still have tokens
      assert {:ok, 0} = RateLimiter.consume_for_client(limiter, "client_b", 1)

      # Client A is rate limited
      assert {:error, :rate_limited} = RateLimiter.consume_for_client(limiter, "client_a", 1)

      # But Client B can still make requests
      assert {:error, :rate_limited} = RateLimiter.consume_for_client(limiter, "client_b", 1)
    end

    test "client buckets are smaller than global bucket", %{limiter: limiter} do
      # Client bucket should be 1/10th of global (10/10 = 1)
      assert {:ok, 0} = RateLimiter.consume_for_client(limiter, "client_x", 1)
      assert {:error, :rate_limited} = RateLimiter.consume_for_client(limiter, "client_x", 1)
    end
  end

  describe "VSM subsystem rate limiting" do
    test "S1 subsystem has higher capacity", %{limiter: limiter} do
      # S1 should have 2x bucket size (20 tokens)
      for i <- 1..20 do
        assert {:ok, _} = RateLimiter.consume_for_subsystem(limiter, :s1, 1),
               "Failed on request #{i}"
      end

      assert {:error, :rate_limited} = RateLimiter.consume_for_subsystem(limiter, :s1, 1)
    end

    test "S5 subsystem has lower capacity", %{limiter: limiter} do
      # S5 should have 1/4 bucket size (10/4 = 2.5, so 2 tokens)
      assert {:ok, _} = RateLimiter.consume_for_subsystem(limiter, :s5, 1)
      assert {:ok, _} = RateLimiter.consume_for_subsystem(limiter, :s5, 1)
      assert {:error, :rate_limited} = RateLimiter.consume_for_subsystem(limiter, :s5, 1)
    end

    test "each subsystem has independent buckets", %{limiter: limiter} do
      # Exhaust S1 tokens
      assert {:ok, _} = RateLimiter.consume_for_subsystem(limiter, :s1, 20)
      assert {:error, :rate_limited} = RateLimiter.consume_for_subsystem(limiter, :s1, 1)

      # Other subsystems should still have tokens
      assert {:ok, _} = RateLimiter.consume_for_subsystem(limiter, :s2, 1)
      assert {:ok, _} = RateLimiter.consume_for_subsystem(limiter, :s3, 1)
      assert {:ok, _} = RateLimiter.consume_for_subsystem(limiter, :s4, 1)
      assert {:ok, _} = RateLimiter.consume_for_subsystem(limiter, :s5, 1)
    end
  end

  describe "token refill" do
    test "tokens are refilled at the specified rate", %{limiter: limiter} do
      # Consume all tokens
      assert {:ok, 0} = RateLimiter.consume(limiter, 10)
      assert {:error, :rate_limited} = RateLimiter.consume(limiter, 1)

      # Wait for refill (100ms interval, 5 tokens/sec = 0.5 tokens per interval)
      Process.sleep(150)

      # Should have some tokens refilled
      assert {:ok, _} = RateLimiter.consume(limiter, 1)
    end

    test "tokens don't exceed bucket size after refill", %{limiter: limiter} do
      # Start with full bucket
      state = RateLimiter.get_state(limiter)
      assert state.global_tokens == 10

      # Wait for multiple refill cycles
      Process.sleep(500)

      # Should still be at max capacity
      state = RateLimiter.get_state(limiter)
      assert state.global_tokens == 10
    end
  end

  describe "state and metrics" do
    test "get_state returns current bucket status", %{limiter: limiter} do
      state = RateLimiter.get_state(limiter)

      assert state.global_tokens == 10
      assert state.bucket_size == 10
      assert state.refill_rate == 5
      assert is_map(state.subsystem_tokens)
      assert state.subsystem_tokens.s1 == 20
      assert state.subsystem_tokens.s5 == 2
    end

    test "tracks request metrics", %{limiter: limiter} do
      # Make some successful requests
      RateLimiter.consume(limiter, 1)
      RateLimiter.consume(limiter, 1)

      # Make failed requests
      RateLimiter.consume(limiter, 20)

      state = RateLimiter.get_state(limiter)
      assert state.metrics.total_requests == 3
      assert state.metrics.total_allowed == 2
      assert state.metrics.total_limited == 1
    end

    test "tracks variety flow metrics for subsystems", %{limiter: limiter} do
      # Make requests for different subsystems
      RateLimiter.consume_for_subsystem(limiter, :s1, 1)
      RateLimiter.consume_for_subsystem(limiter, :s2, 1)
      RateLimiter.consume_for_subsystem(limiter, :s1, 1)

      # Exhaust S5 and try again
      RateLimiter.consume_for_subsystem(limiter, :s5, 2)
      RateLimiter.consume_for_subsystem(limiter, :s5, 1)

      variety_metrics = RateLimiter.get_variety_metrics(limiter)
      assert variety_metrics.s1 == 2
      assert variety_metrics.s2 == 1
      assert variety_metrics.s5 == 2
    end
  end

  describe "reset functionality" do
    test "reset restores all buckets to full capacity", %{limiter: limiter} do
      # Consume tokens from various buckets
      RateLimiter.consume(limiter, 5)
      RateLimiter.consume_for_client(limiter, "client_a", 1)
      RateLimiter.consume_for_subsystem(limiter, :s1, 10)

      # Reset
      assert :ok = RateLimiter.reset(limiter)

      # Check all buckets are full
      state = RateLimiter.get_state(limiter)
      assert state.global_tokens == 10
      assert state.subsystem_tokens.s1 == 20

      # Client should be able to consume again
      assert {:ok, _} = RateLimiter.consume_for_client(limiter, "client_a", 1)
    end
  end

  describe "concurrent access" do
    test "handles concurrent requests safely", %{limiter: limiter} do
      # Spawn multiple processes trying to consume tokens
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            RateLimiter.consume(limiter, 1)
          end)
        end

      results = Task.await_many(tasks)

      # Count successes and failures
      {successes, failures} =
        Enum.split_with(results, fn
          {:ok, _} -> true
          {:error, :rate_limited} -> false
        end)

      # Should have exactly 10 successes (bucket size)
      assert length(successes) == 10
      assert length(failures) == 10
    end
  end
end