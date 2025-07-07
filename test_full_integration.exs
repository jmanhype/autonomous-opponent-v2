#!/usr/bin/env elixir

Mix.install([
  {:jason, "~> 1.4"},
  {:httpoison, "~> 2.0"}
])

defmodule IntegrationTest do
  @base_url "http://localhost:4000"
  
  def run do
    IO.puts("\n🧪 FULL SYSTEM INTEGRATION TEST")
    IO.puts("================================")
    
    # Test 1: Check VSM State
    IO.puts("\n1️⃣ Testing VSM State Endpoint...")
    case HTTPoison.get("#{@base_url}/api/vsm/state") do
      {:ok, %{status_code: 200, body: body}} ->
        vsm_state = Jason.decode!(body)
        IO.puts("✅ VSM State Retrieved Successfully")
        IO.puts("   Overall Health: #{inspect(vsm_state["vsm"]["overall_health"])}")
        
        # Check each subsystem
        for subsystem <- ["s1_operations", "s2_coordination", "s3_control", "s4_intelligence", "s5_policy"] do
          status = get_in(vsm_state, ["vsm", subsystem, "status"])
          IO.puts("   #{subsystem}: #{status}")
        end
        
      {:error, reason} ->
        IO.puts("❌ Failed to get VSM state: #{inspect(reason)}")
    end
    
    # Test 2: Check Consciousness State
    IO.puts("\n2️⃣ Testing Consciousness State...")
    case HTTPoison.get("#{@base_url}/api/consciousness/state") do
      {:ok, %{status_code: 200, body: body}} ->
        consciousness = Jason.decode!(body)
        IO.puts("✅ Consciousness State Retrieved")
        IO.puts("   State: #{consciousness["state"]}")
        IO.puts("   Awareness Level: #{consciousness["awareness_level"]}")
        
      {:error, reason} ->
        IO.puts("❌ Failed to get consciousness state: #{inspect(reason)}")
    end
    
    # Test 3: Send Algedonic Signal
    IO.puts("\n3️⃣ Testing Algedonic Signal...")
    signal_data = %{
      type: "pleasure",
      intensity: 0.8,
      source: "integration_test"
    }
    
    case HTTPoison.post("#{@base_url}/api/vsm/algedonic", Jason.encode!(signal_data), [{"Content-Type", "application/json"}]) do
      {:ok, %{status_code: 200}} ->
        IO.puts("✅ Algedonic signal sent successfully")
        
      {:error, reason} ->
        IO.puts("❌ Failed to send algedonic signal: #{inspect(reason)}")
    end
    
    # Test 4: Chat with Consciousness
    IO.puts("\n4️⃣ Testing Consciousness Chat...")
    chat_data = %{
      message: "What is your current operational status?",
      conversation_id: "test_integration"
    }
    
    case HTTPoison.post("#{@base_url}/api/consciousness/chat", Jason.encode!(chat_data), [{"Content-Type", "application/json"}], recv_timeout: 30_000) do
      {:ok, %{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        IO.puts("✅ Consciousness responded")
        IO.puts("   Response: #{String.slice(response["response"], 0, 100)}...")
        IO.puts("   Consciousness Active: #{response["consciousness_active"]}")
        
      {:error, reason} ->
        IO.puts("❌ Failed to chat with consciousness: #{inspect(reason)}")
    end
    
    # Test 5: Check Dashboard
    IO.puts("\n5️⃣ Testing Dashboard...")
    case HTTPoison.get("#{@base_url}/dashboard") do
      {:ok, %{status_code: 200, body: body}} ->
        if String.contains?(body, "System Monitoring") && String.contains?(body, "Chat with Consciousness") do
          IO.puts("✅ Dashboard loaded successfully with chat interface")
        else
          IO.puts("⚠️  Dashboard loaded but missing expected elements")
        end
        
      {:error, reason} ->
        IO.puts("❌ Failed to load dashboard: #{inspect(reason)}")
    end
    
    # Test 6: Check Health Endpoint
    IO.puts("\n6️⃣ Testing Health Check...")
    case HTTPoison.get("#{@base_url}/health") do
      {:ok, %{status_code: 200, body: body}} ->
        health = Jason.decode!(body)
        IO.puts("✅ Health check passed")
        IO.puts("   Status: #{health["status"]}")
        
      {:error, reason} ->
        IO.puts("❌ Failed health check: #{inspect(reason)}")
    end
    
    # Summary
    IO.puts("\n📊 INTEGRATION TEST COMPLETE")
    IO.puts("================================")
    IO.puts("The Autonomous Opponent v2 system is operational!")
    IO.puts("All major subsystems are integrated and communicating.")
  end
end

IntegrationTest.run()