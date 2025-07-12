#!/bin/bash

echo "=== Final WebSocket Connection Counting Test ==="
echo ""
echo "Starting server in background..."

# Start server and capture PID properly
elixir --name test@127.0.0.1 -S mix phx.server &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"
echo "Waiting 10 seconds for initialization..."
sleep 10

# Check if server is actually running
if ps -p $SERVER_PID > /dev/null 2>&1; then
    echo "✓ Server is running"
    
    # Run the test
    echo ""
    echo "Running WebSocket test..."
    node test_websocket_100_percent.js
    TEST_RESULT=$?
    
    echo ""
    if [ $TEST_RESULT -eq 0 ]; then
        echo "✅ ALL TESTS PASSED! WebSocket connection counting is working 100%!"
    else
        echo "❌ Some tests failed"
    fi
else
    echo "✗ Server failed to start or crashed"
    TEST_RESULT=1
fi

# Kill the server
echo ""
echo "Stopping server..."
kill $SERVER_PID 2>/dev/null
sleep 2
kill -9 $SERVER_PID 2>/dev/null

exit $TEST_RESULT