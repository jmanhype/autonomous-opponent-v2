#\!/bin/bash
# Send commands to running iex session
echo 'Process.whereis(AutonomousOpponentV2Core.Core.HybridLogicalClock) |> inspect() |> IO.puts()' | nc localhost 4369 2>/dev/null || echo "Can't connect to IEx"

# Alternative: use HTTP endpoint to check
curl -s http://localhost:4000/health | jq . || echo "Health endpoint failed"
