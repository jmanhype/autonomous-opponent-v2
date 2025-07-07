#!/usr/bin/env elixir

# Direct test of LLM functionality

IO.puts "\n🔍 Direct LLM Test\n"

# Start necessary applications
{:ok, _} = Application.ensure_all_started(:httpoison)
{:ok, _} = Application.ensure_all_started(:jason)

# Connect to running node
node_name = :"autonomous_opponent@127.0.0.1"
IO.puts "Connecting to node: #{node_name}"

case Node.connect(node_name) do
  true ->
    IO.puts "✅ Connected to node"
    
    # Check environment variables
    IO.puts "\n📋 Environment Check:"
    api_keys = [
      {"OPENAI_API_KEY", System.get_env("OPENAI_API_KEY")},
      {"ANTHROPIC_API_KEY", System.get_env("ANTHROPIC_API_KEY")},
      {"GOOGLE_AI_API_KEY", System.get_env("GOOGLE_AI_API_KEY")},
      {"OLLAMA_ENABLED", System.get_env("OLLAMA_ENABLED")}
    ]
    
    for {key, value} <- api_keys do
      status = if value && value != "", do: "✅ Set", else: "❌ Not Set"
      IO.puts "  #{key}: #{status}"
    end
    
    # Check LLM configuration
    IO.puts "\n🔧 LLM Configuration:"
    mock_mode = :rpc.call(node_name, Application, :get_env, [:autonomous_opponent_core, :llm_mock_mode, false])
    cache_enabled = :rpc.call(node_name, Application, :get_env, [:autonomous_opponent_core, :llm_cache_enabled, true])
    IO.puts "  Mock Mode: #{mock_mode}"
    IO.puts "  Cache Enabled: #{cache_enabled}"
    
    # Check provider status
    IO.puts "\n🌐 Provider Status:"
    case :rpc.call(node_name, AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge, :get_provider_status, []) do
      {:ok, status} ->
        for {provider, info} <- status do
          IO.puts "  #{provider}: #{if info.enabled, do: "✅", else: "❌"} Enabled, API Key: #{if info.has_api_key, do: "✅", else: "❌"}, Model: #{info.default_model}"
        end
      error ->
        IO.puts "  Error getting status: #{inspect error}"
    end
    
    # Test direct LLM call
    IO.puts "\n🚀 Testing Direct LLM Call:"
    prompt = "Hello, I am testing the LLM integration. Please respond with a brief greeting."
    
    result = :rpc.call(
      node_name, 
      AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge,
      :call_llm_api,
      [prompt, :test, []]
    )
    
    case result do
      {:ok, response} ->
        IO.puts "✅ LLM Response:"
        IO.puts response
        
        # Check if it's a fallback response
        if String.contains?(response, "[") && String.contains?(response, "Local") do
          IO.puts "\n⚠️  Response appears to be from Local Fallback!"
        else
          IO.puts "\n✅ Response appears to be from real LLM!"
        end
        
      {:error, reason} ->
        IO.puts "❌ Error: #{inspect reason}"
    end
    
    # Test consciousness dialog
    IO.puts "\n🧠 Testing Consciousness Dialog:"
    
    case :rpc.call(node_name, AutonomousOpponentV2Core.Consciousness, :conscious_dialog, ["What are you experiencing right now?"]) do
      {:ok, response} ->
        IO.puts "✅ Consciousness Response:"
        IO.puts response
        
        # Check response type
        if String.contains?(response, "[Local") || String.contains?(response, "Local Cybernetic") do
          IO.puts "\n⚠️  Using Local Fallback!"
        end
        
      error ->
        IO.puts "❌ Error: #{inspect error}"
    end
    
  false ->
    IO.puts "❌ Failed to connect to node"
    IO.puts "Make sure the server is running with: iex --name autonomous_opponent@127.0.0.1 -S mix phx.server"
end