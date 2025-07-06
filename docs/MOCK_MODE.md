# LLM Mock Mode

Ultra-fast development mode that provides instant LLM responses without API delays!

## Quick Start

Mock mode is **enabled by default** in development. Just start coding and enjoy instant responses!

```elixir
# In config/dev.exs
config :autonomous_opponent_core,
  llm_mock_mode: true,      # Enable/disable mock mode
  llm_mock_delay: 50        # Milliseconds (set to 0 for instant)
```

## Features

### 1. Instant Responses
- No API calls = no network delays
- Configurable delay (0-1000ms) for realism
- Perfect for rapid UI development

### 2. Intent-Based Responses
MockLLM automatically detects intent from your prompts:
- `combat_analysis` - Fighting analysis responses
- `strategy_generation` - Strategic planning responses  
- `pattern_recognition` - Behavioral pattern responses
- `emotional_state` - Emotional assessment responses
- `weakness_identification` - Vulnerability analysis
- `training_recommendation` - Training suggestions
- `general` - General purpose responses

### 3. Response Variety
Each intent has multiple response variations to prevent monotony.

### 4. Custom Responses
Add custom responses for specific test scenarios:

```elixir
# Add a custom response
MockLLM.add_mock_response("my_intent", "My custom response")

# Use it
MockLLM.chat([%{role: "user", content: "Test"}], intent: "my_intent")
```

## Usage Examples

### Basic Usage
```elixir
# Mock mode automatically intercepts all LLM calls
{:ok, response} = LLMBridge.call_llm_api("Analyze the fight", :combat_analysis)
# Returns instantly with contextual mock response!
```

### Conversational Mode
```elixir
{:ok, response} = LLMBridge.converse_with_consciousness("How are you feeling?")
# Instant consciousness dialogue!
```

### Testing Different Intents
```elixir
# The system auto-detects intent from keywords
LLMBridge.call_llm_api("Show me patterns", :general)  # → pattern_recognition
LLMBridge.call_llm_api("What's your strategy?", :general)  # → strategy_generation
LLMBridge.call_llm_api("How do you feel?", :general)  # → emotional_state
```

## Configuration Options

### Toggle Mock Mode
```elixir
# config/dev.exs
config :autonomous_opponent_core,
  llm_mock_mode: false  # Disable to use real LLMs
```

### Adjust Response Delay
```elixir
# Instant responses (best for development)
config :autonomous_opponent_core,
  llm_mock_delay: 0

# Realistic delay (50-200ms)
config :autonomous_opponent_core,
  llm_mock_delay: 100
```

### Runtime Configuration
```elixir
# Change delay at runtime
Application.put_env(:autonomous_opponent_core, :llm_mock_delay, 0)

# Toggle mock mode at runtime
Application.put_env(:autonomous_opponent_core, :llm_mock_mode, false)
```

## Benefits

1. **Speed**: No waiting for API responses
2. **Cost**: Zero API usage during development
3. **Reliability**: No network issues or rate limits
4. **Consistency**: Predictable responses for testing
5. **Offline**: Works without internet connection

## Testing

Run the test script to verify mock mode:

```bash
mix run test_mock_mode.exs
```

## Best Practices

1. **Development**: Keep mock mode ON for rapid iteration
2. **Integration Testing**: Turn OFF to test real LLM integration  
3. **UI Development**: Use 0ms delay for instant feedback
4. **Demo Mode**: Use 50-100ms delay for realistic feel
5. **Custom Scenarios**: Add specific mock responses for edge cases

## Switching to Production

In production config:
```elixir
# config/prod.exs
config :autonomous_opponent_core,
  llm_mock_mode: false  # Always use real LLMs in production
```

## Troubleshooting

### Mock mode not working?
1. Check config: `Application.get_env(:autonomous_opponent_core, :llm_mock_mode)`
2. Restart the application after config changes
3. Ensure MockLLM module is loaded

### Getting real API responses in dev?
- Mock mode might be disabled in config
- Check for explicit `use_mock: false` in call options

### Want different responses?
- Add custom responses with `MockLLM.add_mock_response/2`
- Modify response arrays in `MockLLM` module
- Adjust intent detection logic

---

Happy coding with instant LLM responses! 🚀