#!/bin/bash

echo "Testing all Autonomous Opponent endpoints..."
echo "==========================================="

# Consciousness endpoints
echo -e "\n1. CONSCIOUSNESS CHAT"
curl -X POST http://localhost:4000/api/consciousness/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, how are you?", "context": {"user_id": "test"}}' | jq

echo -e "\n2. CONSCIOUSNESS REFLECT"
curl -X POST http://localhost:4000/api/consciousness/reflect \
  -H "Content-Type: application/json" \
  -d '{"aspect": "existence", "topic": "What does it mean to be conscious?", "depth": "deep"}' | jq

echo -e "\n3. CONSCIOUSNESS STATE"
curl -X GET http://localhost:4000/api/consciousness/state 2>/dev/null | head -100

echo -e "\n4. VSM STATE"
curl -X GET http://localhost:4000/api/vsm/state 2>/dev/null | head -100

echo -e "\n5. VSM EVENTS"
curl -X GET "http://localhost:4000/api/vsm/events?subsystem=s1&limit=5" 2>/dev/null | head -100

echo -e "\n6. ALGEDONIC TRIGGER"
curl -X POST http://localhost:4000/api/vsm/algedonic/trigger \
  -H "Content-Type: application/json" \
  -d '{"type": "pain", "intensity": 0.8, "source": "test", "subsystem": "s1"}' 2>/dev/null | head -100

echo -e "\n7. PATTERN DETECTION"
curl -X POST http://localhost:4000/api/intelligence/detect_patterns \
  -H "Content-Type: application/json" \
  -d '{"data": ["A", "B", "A", "B", "A", "B"], "context": {"type": "test"}}' 2>/dev/null | head -100

echo -e "\n8. HEALTH CHECK"
curl -X GET http://localhost:4000/health | jq

echo -e "\n9. METRICS"
curl -X GET http://localhost:4000/api/metrics | jq 2>/dev/null || echo "Metrics endpoint not available"

echo -e "\n10. RATE LIMIT TEST"
for i in {1..10}; do
  echo -n "Request $i: "
  curl -s -X POST http://localhost:4000/api/consciousness/chat \
    -H "Content-Type: application/json" \
    -d '{"message": "test", "context": {"user_id": "rate_test"}}' | jq -r '.status // "error"'
done