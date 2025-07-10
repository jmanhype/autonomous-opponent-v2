#!/usr/bin/env elixir

# Test script to verify CRDTStore fix
IO.puts("Testing CRDTStore availability fix...")

# Start the applications manually
{:ok, _} = Application.ensure_all_started(:autonomous_opponent_core)
{:ok, _} = Application.ensure_all_started(:autonomous_opponent_web)

# Wait a moment for processes to start
Process.sleep(1000)

# Check if CRDTStore is running
case Process.whereis(AutonomousOpponentV2Core.AMCP.Memory.CRDTStore) do
  nil ->
    IO.puts("✗ CRDTStore is NOT running")
  pid ->
    IO.puts("✓ CRDTStore is running with PID: #{inspect(pid)}")
end

# Test the API endpoint using HTTPoison
url = "http://localhost:4000/api/consciousness/chat"
headers = [{"Content-Type", "application/json"}]
body = Jason.encode!(%{message: "test: Hello from test script"})

IO.puts("\nTesting consciousness chat endpoint...")

case HTTPoison.post(url, body, headers) do
  {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
    IO.puts("✓ API call successful!")
    case Jason.decode(response_body) do
      {:ok, json} ->
        IO.puts("Response: #{inspect(json, pretty: true)}")
      {:error, _} ->
        IO.puts("Response body: #{response_body}")
    end
    
  {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
    IO.puts("✗ API returned status #{status}")
    IO.puts("Response: #{body}")
    
  {:error, %HTTPoison.Error{reason: :econnrefused}} ->
    IO.puts("✗ Connection refused - is the Phoenix server running?")
    IO.puts("Start it with: iex -S mix phx.server")
    
  {:error, error} ->
    IO.puts("✗ Request failed: #{inspect(error)}")
end