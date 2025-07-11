#!/bin/bash

echo "=== Running Full WebSocket Connection Counting Test ==="
echo ""
echo "This script will:"
echo "1. Start the server as a distributed node"
echo "2. Wait for it to initialize"
echo "3. Run comprehensive tests"
echo "4. Automatically shut down after tests complete"
echo ""

# Function to cleanup on exit
cleanup() {
    echo -e "\nCleaning up..."
    # Kill the Phoenix server
    if [ ! -z "$SERVER_PID" ]; then
        echo "Stopping Phoenix server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null
        sleep 2
        # Force kill if still running
        kill -9 $SERVER_PID 2>/dev/null
    fi
    pkill -f "beam.*test@127.0.0.1" 2>/dev/null
    echo "✓ Cleanup complete"
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Start the server in background with reduced logging
echo "Starting Phoenix server as distributed node..."
MIX_ENV=dev elixir --name test@127.0.0.1 -S mix phx.server 2>&1 | grep -E "(Running|Started|Error|Failed)" &
SERVER_PID=$!

# Wait for server to start
echo "Waiting for server to initialize (10 seconds)..."
sleep 10

# Check if server is running
if ! ps -p $SERVER_PID > /dev/null 2>&1; then
    echo "✗ Server failed to start"
    exit 1
fi

echo "✓ Server is running (PID: $SERVER_PID)"

# Check that it's a distributed node
echo ""
echo "Checking distributed node status..."
(elixir --name checker@127.0.0.1 check_pattern_aggregator.exs) &
CHECKER_PID=$!
sleep 5
kill $CHECKER_PID 2>/dev/null || true

# Run the comprehensive test with timeout
echo ""
echo "Running WebSocket tests (max 30 seconds)..."
node test_websocket_100_percent.js &
TEST_PID=$!

# Wait up to 30 seconds for test to complete
COUNTER=0
while [ $COUNTER -lt 30 ] && kill -0 $TEST_PID 2>/dev/null; do
    sleep 1
    COUNTER=$((COUNTER + 1))
done

# If still running, kill it
if kill -0 $TEST_PID 2>/dev/null; then
    echo "Test exceeded 30 seconds, terminating..."
    kill $TEST_PID 2>/dev/null
    wait $TEST_PID 2>/dev/null
    TEST_RESULT=1
else
    wait $TEST_PID
    TEST_RESULT=$?
fi

if [ $TEST_RESULT -eq 0 ]; then
    echo ""
    echo "✓ All tests passed! WebSocket connection counting is working 100%"
else
    echo ""
    echo "✗ Some tests failed. Check the output above for details."
fi

# Explicitly cleanup before exit
cleanup

exit $TEST_RESULT