#\!/bin/bash

echo "🔍 CHECKING SERVER STATE"

# 1. Generate a few events through the API
echo -e "\n📡 Generating events..."
for i in {1..5}; do
  curl -s -X POST http://localhost:4000/api/consciousness/chat \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"Test message $i about consciousness\", \"user_id\": \"debug_user\"}" \
    > /dev/null
  echo -n "."
done
echo " Done\!"

# 2. Check what events were published
echo -e "\n📋 Recent event publications:"
tail -500 server_debug.log | grep "Event published:" | tail -10

# 3. Check EventBus broadcasts
echo -e "\n📢 Recent EventBus broadcasts:"
tail -500 server_debug.log | grep "EventBus" | tail -10

# 4. Check if events are being received
echo -e "\n📨 Events received by analyzers:"
tail -500 server_debug.log | grep -E "(received event:|handle_info.*event_bus)" | tail -10

# 5. Check endpoints
echo -e "\n📊 API Endpoints Status:"
echo -n "Patterns: "
curl -s http://localhost:4000/api/patterns | jq '.patterns | length'

echo -n "Trending Topics: "
curl -s http://localhost:4000/api/events/analyze | jq '.analysis.trending_topics | length'

# 6. Check for LLM calls
echo -e "\n🤖 Recent LLM API calls:"
tail -500 server_debug.log | grep "LLM API call" | tail -5
