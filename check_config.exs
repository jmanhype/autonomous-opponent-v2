# Check if rate limiting is disabled
skip_rate_limiting = Application.get_env(:autonomous_opponent_core, :skip_rate_limiting, false)
IO.puts("skip_rate_limiting config: #{inspect(skip_rate_limiting)}")

# Check if RateLimiter is running
case Process.whereis(AutonomousOpponentV2Core.Core.RateLimiter) do
  nil -> IO.puts("RateLimiter is NOT running")
  pid -> IO.puts("RateLimiter is running at #{inspect(pid)}")
end

# Try to consume a token
case AutonomousOpponentV2Core.Core.RateLimiter.consume(AutonomousOpponentV2Core.Core.RateLimiter, 1) do
  {:ok, tokens} -> IO.puts("Rate limiter allowed request, tokens remaining: #{tokens}")
  {:error, :rate_limited} -> IO.puts("Rate limiter blocked request")
  error -> IO.puts("Rate limiter error: #{inspect(error)}")
end