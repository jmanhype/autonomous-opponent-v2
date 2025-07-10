# Simple test script to verify Redis rate limiter is working

# Start the application
{:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)

# Test Redis connection
IO.puts("Testing Redis connection...")
case AutonomousOpponentV2Core.Connections.RedisPool.health_check() do
  :ok -> 
    IO.puts("✓ Redis connection successful")
  error -> 
    IO.puts("✗ Redis connection failed: #{inspect(error)}")
end

# Test distributed rate limiter
IO.puts("\nTesting distributed rate limiter...")

# Make 15 requests to test rate limiting (limit is 10/sec)
results = for i <- 1..15 do
  result = AutonomousOpponentV2Core.Core.DistributedRateLimiter.check_and_track(
    :api_rate_limiter, 
    "test_user", 
    :burst,
    1
  )
  IO.puts("Request #{i}: #{inspect(result)}")
  Process.sleep(50) # Small delay between requests
  result
end

# Count successes and failures
{successes, failures} = Enum.split_with(results, fn
  {:ok, _} -> true
  _ -> false
end)

IO.puts("\nResults:")
IO.puts("Successful requests: #{length(successes)}")
IO.puts("Rate limited requests: #{length(failures)}")

# Check usage
case AutonomousOpponentV2Core.Core.DistributedRateLimiter.get_usage(:api_rate_limiter, "test_user", :burst) do
  {:ok, usage} ->
    IO.puts("\nCurrent usage: #{inspect(usage)}")
  error ->
    IO.puts("\nFailed to get usage: #{inspect(error)}")
end

# Clean up
AutonomousOpponentV2Core.Core.DistributedRateLimiter.clear(:api_rate_limiter, "test_user")
IO.puts("\nTest data cleared")
EOF < /dev/null