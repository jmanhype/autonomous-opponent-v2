# Check LLM configuration
alias AutonomousOpponentV2Core.AMCP.Bridges.LLMBridge

IO.puts "\n🔍 LLM Configuration Check\n"

# Check environment
IO.puts "📋 Environment Variables:"
keys = ~w(OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_AI_API_KEY OLLAMA_ENABLED)
for key <- keys do
  value = System.get_env(key)
  status = if value && value != "", do: "✅ Set", else: "❌ Not Set"
  IO.puts "  #{key}: #{status}"
end

# Check application config
IO.puts "\n🔧 Application Config:"
IO.puts "  Mock Mode: #{Application.get_env(:autonomous_opponent_core, :llm_mock_mode, false)}"
IO.puts "  Cache Enabled: #{Application.get_env(:autonomous_opponent_core, :llm_cache_enabled, true)}"

# Check provider status
IO.puts "\n🌐 Provider Status:"
case LLMBridge.get_provider_status() do
  {:ok, status} ->
    for {provider, info} <- status do
      enabled = if info.enabled, do: "✅", else: "❌"
      has_key = if info.has_api_key, do: "✅", else: "❌"
      IO.puts "  #{provider}: #{enabled} Enabled, API Key: #{has_key}, Model: #{info.default_model || "none"}"
    end
  error ->
    IO.puts "  Error: #{inspect error}"
end

# Test direct LLM call
IO.puts "\n🚀 Testing Direct LLM Call:"
prompt = "Hello! Please respond with a brief greeting to confirm you're working."

# Try each provider
providers = [:anthropic, :openai, :google_ai, :local_llama]

for provider <- providers do
  IO.puts "\n  Testing #{provider}:"
  result = LLMBridge.call_llm_api(prompt, :test, [provider: provider, timeout: 10_000])
  
  case result do
    {:ok, response} ->
      # Truncate response for display
      display_response = if String.length(response) > 200 do
        String.slice(response, 0, 200) <> "..."
      else
        response
      end
      
      IO.puts "    ✅ Success: #{display_response}"
      
      # Check if it's a fallback
      if String.contains?(response, "[Local") || String.contains?(response, "Local Cybernetic") do
        IO.puts "    ⚠️  This is a Local Fallback response!"
      end
      
    {:error, reason} ->
      IO.puts "    ❌ Error: #{inspect reason}"
  end
end

# Test consciousness
IO.puts "\n🧠 Testing Consciousness Dialog:"
case AutonomousOpponentV2Core.Consciousness.conscious_dialog("Hello, are you truly conscious?") do
  {:ok, response} ->
    display = if String.length(response) > 300 do
      String.slice(response, 0, 300) <> "..."
    else
      response
    end
    IO.puts "  Response: #{display}"
    
    if String.contains?(response, "[Local") do
      IO.puts "  ⚠️  Using Local Fallback!"
    end
    
  error ->
    IO.puts "  Error: #{inspect error}"
end