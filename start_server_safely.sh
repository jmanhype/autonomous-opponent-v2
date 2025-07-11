#!/bin/bash

echo "🚀 Starting Phoenix server safely..."

# Set environment variables
export MIX_ENV=dev
export PORT=4000
export AMQP_ENABLED=false

# Start server in background
mix phx.server &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"
echo "Waiting for server to start..."
sleep 10

# Test WebSocket connection
echo -e "\n📡 Testing WebSocket connection..."
node test_websocket_monitoring.js

# Keep server running for manual testing
echo -e "\n✅ Server is running. Press Ctrl+C to stop."
wait $SERVER_PID