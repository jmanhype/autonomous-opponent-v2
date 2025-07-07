#!/bin/bash

# Start Phoenix server in background
echo "Starting Phoenix server..."
mix phx.server &
SERVER_PID=$!

# Wait for server to start
echo "Waiting for server to start..."
sleep 10

# Check if server is running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "Server failed to start!"
    exit 1
fi

echo "Server started with PID: $SERVER_PID"

# Test 1: Check server health
echo -e "\n=== Test 1: Server Health ==="
curl -s http://localhost:4000/health | jq . || echo "Failed to get health"

# Test 2: Get consciousness state
echo -e "\n=== Test 2: Consciousness State ==="
curl -s http://localhost:4000/api/consciousness/state | jq . || echo "Failed to get consciousness state"

# Test 3: Check VSM metrics
echo -e "\n=== Test 3: VSM Metrics ==="
curl -s http://localhost:4000/api/vsm/metrics 2>/dev/null | jq . || echo "VSM metrics endpoint not available"

# Test 4: Check algedonic state
echo -e "\n=== Test 4: Algedonic State ==="
curl -s http://localhost:4000/api/vsm/algedonic/state 2>/dev/null | jq . || echo "Algedonic endpoint not available"

# Test 5: Send chat message to trigger VSM activity
echo -e "\n=== Test 5: Send Chat Message ==="
curl -s -X POST http://localhost:4000/api/consciousness/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello VSM, are you processing with real implementations?", "context": {}}' \
  | jq . || echo "Chat endpoint failed"

# Test 6: Check pattern detection
echo -e "\n=== Test 6: Pattern Detection ==="
curl -s "http://localhost:4000/api/consciousness/patterns?time_window=300" | jq . || echo "Pattern detection failed"

# Test 7: Check event analysis
echo -e "\n=== Test 7: Event Analysis ==="
curl -s "http://localhost:4000/api/consciousness/events?time_window=60" | jq . || echo "Event analysis failed"

# Test 8: Generate load to trigger variety management
echo -e "\n=== Test 8: Generate Load for Variety Management ==="
for i in {1..20}; do
    curl -s -X POST http://localhost:4000/api/consciousness/chat \
      -H "Content-Type: application/json" \
      -d "{\"message\": \"Test message $i with variety: $(openssl rand -hex 8)\", \"context\": {}}" \
      > /dev/null 2>&1 &
done

# Wait for requests to complete
sleep 3

# Check VSM state after load
echo -e "\n=== Test 9: VSM State After Load ==="
curl -s http://localhost:4000/api/consciousness/state | jq '.vsm_state' || echo "Failed to get VSM state"

# Test 10: Reflection to see if consciousness is working
echo -e "\n=== Test 10: Consciousness Reflection ==="
curl -s -X POST http://localhost:4000/api/consciousness/reflect \
  -H "Content-Type: application/json" \
  -d '{"prompt": "What is your current operational state and are you using real variety measurement?"}' \
  | jq . || echo "Reflection failed"

# Clean up
echo -e "\n=== Shutting down server ==="
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

echo -e "\n=== Test Complete ==="