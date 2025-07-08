#!/usr/bin/env elixir

# Test script to verify VSM metrics endpoints are working

# Start the application
IO.puts("Starting application...")
Application.ensure_all_started(:autonomous_opponent_core)
Application.ensure_all_started(:autonomous_opponent_web)

# Give the system a moment to initialize
Process.sleep(2000)

IO.puts("\n=== Testing VSM Metrics Endpoints ===\n")

# Test S1 Operations variety metrics
IO.puts("1. Testing S1.Operations :get_variety_metrics")
try do
  s1_metrics = GenServer.call(AutonomousOpponentV2Core.VSM.S1.Operations, :get_variety_metrics, 5_000)
  IO.puts("   ✓ S1 variety metrics: #{inspect(s1_metrics)}")
catch
  error -> IO.puts("   ✗ S1 error: #{inspect(error)}")
end

# Test S2 Coordination state
IO.puts("\n2. Testing S2.Coordination :get_state")
try do
  s2_state = GenServer.call(AutonomousOpponentV2Core.VSM.S2.Coordination, :get_state, 5_000)
  IO.puts("   ✓ S2 state: #{inspect(s2_state)}")
catch
  error -> IO.puts("   ✗ S2 error: #{inspect(error)}")
end

# Test S3 Control state
IO.puts("\n3. Testing S3.Control :get_state")
try do
  s3_state = GenServer.call(AutonomousOpponentV2Core.VSM.S3.Control, :get_state, 5_000)
  IO.puts("   ✓ S3 state: #{inspect(s3_state)}")
catch
  error -> IO.puts("   ✗ S3 error: #{inspect(error)}")
end

# Test Algedonic Channel metrics
IO.puts("\n4. Testing AlgedonicChannel :get_metrics")
try do
  algedonic_metrics = GenServer.call(AutonomousOpponentV2Core.VSM.Algedonic.Channel, :get_metrics, 5_000)
  IO.puts("   ✓ Algedonic metrics: #{inspect(algedonic_metrics)}")
catch
  error -> IO.puts("   ✗ Algedonic error: #{inspect(error)}")
end

# Test the VSM controller's get_variety_metric function via HTTP API
IO.puts("\n5. Testing VSM Controller API endpoints")

# Test /api/vsm/metrics endpoint
try do
  response = HTTPoison.get!("http://localhost:4000/api/vsm/metrics")
  case Jason.decode(response.body) do
    {:ok, body} ->
      IO.puts("   ✓ VSM metrics API response:")
      IO.puts("     - Variety absorption S1: #{get_in(body, ["metrics", "variety_absorption", "s1"])}")
      IO.puts("     - Variety absorption S2: #{get_in(body, ["metrics", "variety_absorption", "s2"])}")
      IO.puts("     - Variety absorption S3: #{get_in(body, ["metrics", "variety_absorption", "s3"])}")
      IO.puts("     - Algedonic pain level: #{get_in(body, ["metrics", "algedonic_signals", "pain_level"])}")
    error ->
      IO.puts("   ✗ Failed to decode response: #{inspect(error)}")
  end
rescue
  error -> IO.puts("   ✗ API error: #{inspect(error)}")
end

# Test /api/vsm/state endpoint
try do
  response = HTTPoison.get!("http://localhost:4000/api/vsm/state")
  case Jason.decode(response.body) do
    {:ok, body} ->
      IO.puts("\n   ✓ VSM state API response:")
      IO.puts("     - S1 status: #{get_in(body, ["vsm", "s1_operations", "status"])}")
      IO.puts("     - S2 status: #{get_in(body, ["vsm", "s2_coordination", "status"])}")
      IO.puts("     - S3 status: #{get_in(body, ["vsm", "s3_control", "status"])}")
      IO.puts("     - Overall health: #{inspect(get_in(body, ["vsm", "overall_health"]))}")
    error ->
      IO.puts("   ✗ Failed to decode response: #{inspect(error)}")
  end
rescue
  error -> IO.puts("   ✗ API error: #{inspect(error)}")
end

IO.puts("\n=== Test Complete ===")