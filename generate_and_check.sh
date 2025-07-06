#\!/bin/bash

echo "🌊 GENERATING REAL INTERACTIONS 🌊"

# Generate 20 chat interactions
for i in {1..20}; do
  curl -s -X POST http://localhost:4000/api/consciousness/chat \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"Question $i: What is consciousness and how does it emerge?\", \"user_id\": \"user_$((i % 5))\"}" \
    > /dev/null
  
  if [ $((i % 5)) -eq 0 ]; then
    echo "Generated $i chat interactions..."
  fi
done

echo -e "\n✅ Generated 20 chat interactions"

# Check the logs for event processing
echo -e "\n📋 Checking logs for event processing..."
tail -100 server_debug.log | grep -E "(SemanticAnalyzer received|SemanticFusion received|perform_batch_analysis)" | tail -10

# Wait for processing
echo -e "\n⏳ Waiting 10 seconds for semantic analysis..."
sleep 10

# Check endpoints
echo -e "\n=== CHECKING ENDPOINTS ==="

echo -e "\n1. Pattern Detection:"
curl -s "http://localhost:4000/api/patterns?time_window=600" | jq '.patterns | length' | xargs -I {} echo "  Patterns found: {}"

echo -e "\n2. Event Analysis:"
curl -s "http://localhost:4000/api/events/analyze?time_window=600" | jq '.analysis.trending_topics | length' | xargs -I {} echo "  Trending topics: {}"

echo -e "\n3. Memory Synthesis:"
curl -s http://localhost:4000/api/memory/synthesize | jq -r '.knowledge_synthesis' | head -5
