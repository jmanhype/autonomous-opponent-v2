# Wait for system to start
IO.puts("Waiting for system to fully start...")
Process.sleep(10_000)

# Check if CRDTStore is running
IO.puts("\nChecking if CRDTStore is running...")
case Process.whereis(AutonomousOpponentV2Core.AMCP.Memory.CRDTStore) do
  nil ->
    IO.puts("❌ CRDTStore is NOT running!")
  pid ->
    IO.puts("✅ CRDTStore is running with PID: #{inspect(pid)}")
end

# Check if HLC is running
IO.puts("\nChecking if HLC is running...")
case Process.whereis(AutonomousOpponentV2Core.Core.HybridLogicalClock) do
  nil ->
    IO.puts("❌ HLC is NOT running!")
  pid ->
    IO.puts("✅ HLC is running with PID: #{inspect(pid)}")
end

# Check if Consciousness is running
IO.puts("\nChecking if Consciousness is running...")
case Process.whereis(AutonomousOpponentV2Core.Consciousness) do
  nil ->
    IO.puts("❌ Consciousness is NOT running!")
  pid ->
    IO.puts("✅ Consciousness is running with PID: #{inspect(pid)}")
end

# Try making API call
IO.puts("\nMaking API call to consciousness chat...")
url = "http://localhost:4000/api/consciousness/chat"
headers = [{"Content-Type", "application/json"}]
body = Jason.encode!(%{message: "Hello, are you working?"})

case :httpc.request(:post, {String.to_charlist(url), headers, 'application/json', body}, [], []) do
  {:ok, {{_, status_code, _}, _, response_body}} ->
    IO.puts("Response status: #{status_code}")
    if status_code == 200 do
      IO.puts("✅ API is working!")
      IO.puts("Response: #{response_body}")
    else
      IO.puts("❌ API returned error status: #{status_code}")
      IO.puts("Response: #{List.to_string(response_body) |> String.slice(0, 200)}...")
    end
  {:error, reason} ->
    IO.puts("❌ API request failed: #{inspect(reason)}")
end