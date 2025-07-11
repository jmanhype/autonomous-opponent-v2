#!/bin/bash

echo "=== Fast WebSocket Test (10 second max) ==="
echo ""

# Start server
echo "Starting server..."
elixir --name test@127.0.0.1 -S mix phx.server > /tmp/phoenix.log 2>&1 &
SERVER_PID=$!

# Wait for startup
echo "Waiting 5 seconds for server startup..."
sleep 5

# Run quick test
echo "Running quick WebSocket test..."
node test_websocket_quick.js

RESULT=$?

# Kill server
echo "Stopping server..."
kill $SERVER_PID 2>/dev/null
sleep 1
kill -9 $SERVER_PID 2>/dev/null

if [ $RESULT -eq 0 ]; then
    echo ""
    echo "✓ WebSocket connection counting is working!"
else
    echo ""
    echo "✗ Test failed"
    echo "Server logs:"
    tail -20 /tmp/phoenix.log
fi

exit $RESULT