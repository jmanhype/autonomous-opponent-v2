#\!/bin/bash

echo "🔍 TESTING EVENTBUS DIRECTLY"

# Use the seed endpoint which we know publishes events
echo -e "\n📡 Using seed endpoint to generate events..."
curl -s -X POST http://localhost:4000/api/debug/seed \
  -H "Content-Type: application/json" \
  -d '{}' \
  -w "\nHTTP Status: %{http_code}\n"

# Wait for processing
echo -e "\n⏳ Waiting 10 seconds for processing..."
sleep 10

# Check endpoints
echo -e "\n📊 Checking endpoints:"
echo -n "Patterns: "
curl -s http://localhost:4000/api/patterns | jq '.patterns | length'

echo -n "Topics: "
curl -s http://localhost:4000/api/events/analyze | jq '.analysis.trending_topics | length'

# Check logs for semantic processing
echo -e "\n📋 Checking for semantic analysis in logs:"
tail -500 server_with_logging.log | grep -E "(perform_batch_analysis|analyze_events_with_llm|LLM API call.*analysis)" | tail -5
