# Script to test fallback removal via HTTP API
# Run this after starting the server with: iex -S mix phx.server

# First, make sure HTTPoison is available
case Code.ensure_loaded(HTTPoison) do
  {:module, _} -> :ok
  _ -> 
    IO.puts("Installing HTTPoison...")
    Mix.install([{:httpoison, "~> 2.0"}, {:jason, "~> 1.4"}])
end

defmodule FallbackTest do
  @base_url "http://localhost:4000/api"
  @headers [{"Content-Type", "application/json"}]
  
  def run_tests do
    IO.puts("\n=== Testing Fallback Removal via HTTP API ===\n")
    
    test_consciousness_chat()
    test_consciousness_state()
    test_inner_dialog()
    test_reflection()
    
    IO.puts("\n=== All Tests Complete ===\n")
  end
  
  defp test_consciousness_chat do
    IO.puts("Test 1: Consciousness Chat Endpoint")
    body = Jason.encode!(%{message: "Hello, are you there?"})
    
    case HTTPoison.post("#{@base_url}/consciousness/chat", body, @headers) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        response = Jason.decode!(resp_body)
        if response["note"] || String.contains?(resp_body, "fallback") || String.contains?(resp_body, "Fallback") do
          IO.puts("❌ FAIL: Got fallback response")
          IO.inspect(response, limit: 3)
        else
          IO.puts("❌ FAIL: Got success response when modules not running")
          IO.inspect(response, limit: 3)
        end
        
      {:ok, %{status_code: 503, body: resp_body}} ->
        response = Jason.decode!(resp_body)
        if response["status"] == "error" do
          IO.puts("✅ PASS: Correctly returned error")
          IO.puts("   Error: #{response["message"]}")
        else
          IO.puts("❌ FAIL: Unexpected 503 response")
          IO.inspect(response, limit: 3)
        end
        
      {:ok, %{status_code: code}} ->
        IO.puts("❌ FAIL: Unexpected status code: #{code}")
        
      {:error, reason} ->
        IO.puts("❌ FAIL: HTTP request failed: #{inspect(reason)}")
    end
  end
  
  defp test_consciousness_state do
    IO.puts("\nTest 2: Consciousness State Endpoint")
    
    case HTTPoison.get("#{@base_url}/consciousness/state", @headers) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        response = Jason.decode!(resp_body)
        if response["status"] == "partial" || response["consciousness"]["note"] do
          IO.puts("❌ FAIL: Got partial/fallback state")
          IO.inspect(response, limit: 3)
        else
          IO.puts("❌ FAIL: Got full state when consciousness not running")
          IO.inspect(response, limit: 3)
        end
        
      {:ok, %{status_code: 503, body: resp_body}} ->
        response = Jason.decode!(resp_body)
        if response["status"] == "error" do
          IO.puts("✅ PASS: Correctly returned error")
          IO.puts("   Error: #{response["message"]}")
        else
          IO.puts("❌ FAIL: Unexpected 503 response")
          IO.inspect(response, limit: 3)
        end
        
      {:ok, %{status_code: 504}} ->
        IO.puts("✅ PASS: Correctly returned timeout (504)")
        
      {:ok, %{status_code: code, body: body}} ->
        IO.puts("❌ FAIL: Unexpected status code: #{code}")
        IO.puts("   Body: #{body}")
        
      {:error, reason} ->
        IO.puts("❌ FAIL: HTTP request failed: #{inspect(reason)}")
    end
  end
  
  defp test_inner_dialog do
    IO.puts("\nTest 3: Inner Dialog Endpoint")
    
    case HTTPoison.get("#{@base_url}/consciousness/dialog", @headers) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        response = Jason.decode!(resp_body)
        if response["note"] || response["status"] == "partial" do
          IO.puts("❌ FAIL: Got placeholder dialog")
          IO.inspect(response, limit: 3)
        else
          IO.puts("❌ FAIL: Got dialog when consciousness not running")
          IO.inspect(response, limit: 3)
        end
        
      {:ok, %{status_code: 503, body: resp_body}} ->
        response = Jason.decode!(resp_body)
        if response["status"] == "error" do
          IO.puts("✅ PASS: Correctly returned error")
          IO.puts("   Error: #{response["message"]}")
        else
          IO.puts("❌ FAIL: Unexpected 503 response")
          IO.inspect(response, limit: 3)
        end
        
      {:ok, %{status_code: code}} ->
        IO.puts("❌ FAIL: Unexpected status code: #{code}")
        
      {:error, reason} ->
        IO.puts("❌ FAIL: HTTP request failed: #{inspect(reason)}")
    end
  end
  
  defp test_reflection do
    IO.puts("\nTest 4: Reflection Endpoint")
    body = Jason.encode!(%{aspect: "existence"})
    
    case HTTPoison.post("#{@base_url}/consciousness/reflect", body, @headers) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        response = Jason.decode!(resp_body)
        if response["note"] do
          IO.puts("❌ FAIL: Got fallback reflection")
          IO.inspect(response, limit: 3)
        else
          IO.puts("❌ FAIL: Got reflection when consciousness not running")
          IO.inspect(response, limit: 3)
        end
        
      {:ok, %{status_code: 503, body: resp_body}} ->
        response = Jason.decode!(resp_body)
        if response["status"] == "error" do
          IO.puts("✅ PASS: Correctly returned error")
          IO.puts("   Error: #{response["message"]}")
        else
          IO.puts("❌ FAIL: Unexpected 503 response")
          IO.inspect(response, limit: 3)
        end
        
      {:ok, %{status_code: code}} ->
        IO.puts("❌ FAIL: Unexpected status code: #{code}")
        
      {:error, reason} ->
        IO.puts("❌ FAIL: HTTP request failed: #{inspect(reason)}")
    end
  end
end

# Run the tests
FallbackTest.run_tests()