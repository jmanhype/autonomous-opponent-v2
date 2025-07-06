#!/bin/bash
# Load API keys from environment or .env file
# DO NOT commit API keys to version control!

# Check if .env file exists
if [ -f .env ]; then
  echo "Loading environment variables from .env file..."
  export $(cat .env | grep -v '^#' | xargs)
fi

# Verify required API keys are set
if [ -z "$OPENAI_API_KEY" ] && [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$GOOGLE_AI_STUDIO_API_KEY" ]; then
  echo "WARNING: No API keys found in environment!"
  echo "Please set at least one of: OPENAI_API_KEY, ANTHROPIC_API_KEY, or GOOGLE_AI_STUDIO_API_KEY"
  echo ""
  echo "You can:"
  echo "1. Export them in your shell: export OPENAI_API_KEY='your-key'"
  echo "2. Create a .env file with: OPENAI_API_KEY=your-key"
  echo "3. Use mock mode: export LLM_MOCK_MODE=true"
fi

# Start the Phoenix server
mix phx.server