#\!/bin/bash

echo "🌊 GENERATING REAL INTERACTIONS THROUGH CHAT API 🌊"

# Generate 100 real chat interactions
for i in {1..100}; do
  MESSAGE="Question $i: What is consciousness? Can AI systems like you truly be conscious?"
  
  curl -s -X POST http://localhost:4000/api/consciousness/chat \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"$MESSAGE\", \"user_id\": \"user_$((i % 10))\"}" \
    > /dev/null
  
  if [ $((i % 10)) -eq 0 ]; then
    echo "Generated $i chat interactions..."
  fi
  
  sleep 0.1
done

echo "✓ Generated 100 chat interactions"

# Wait for processing
echo "Waiting 10 seconds for semantic analysis..."
sleep 10

# Check endpoints
echo -e "\n=== CHECKING ENDPOINTS ==="

echo -e "\n1. Pattern Detection:"
curl -s "http://localhost:4000/api/patterns?time_window=600" | jq '.patterns | length' | xargs -I {} echo "  Patterns found: {}"

echo -e "\n2. Event Analysis:"
curl -s "http://localhost:4000/api/events/analyze?time_window=600" | jq '.analysis.trending_topics | length' | xargs -I {} echo "  Trending topics: {}"

echo -e "\n3. Memory Synthesis:"
# First restart the CRDT Store by using the seed endpoint
curl -s -X POST http://localhost:4000/api/debug/seed -H "Content-Type: application/json" -d '{}' > /dev/null
sleep 2
curl -s http://localhost:4000/api/memory/synthesize 2>&1 | head -c 200
