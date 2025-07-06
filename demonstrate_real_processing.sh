#!/bin/bash

echo "🚀 DEMONSTRATING REAL EVENT PROCESSING"
echo "======================================="

# 1. Check initial state
echo -e "\n📊 Initial State:"
echo -n "Patterns: "
curl -s http://localhost:4000/api/patterns | jq '.patterns | length'
echo -n "Topics: "
curl -s http://localhost:4000/api/events/analyze | jq '.analysis.trending_topics | length'

# 2. Generate real interactions
echo -e "\n📡 Generating real user interactions..."
for i in {1..20}; do
  topic=$(shuf -e "consciousness" "philosophy" "technology" "existence" "intelligence" -n 1)
  message="Tell me about $topic in the context of cybernetic systems"
  
  curl -s -X POST http://localhost:4000/api/consciousness/chat \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"$message\", \"user_id\": \"user_$((i % 5))\"}" \
    > /dev/null
  
  echo -n "."
  sleep 0.2
done
echo " Done!"

# 3. Generate some reflections
echo -e "\n🤔 Generating consciousness reflections..."
for aspect in "existence" "purpose" "awareness" "intelligence" "emergence"; do
  curl -s -X POST http://localhost:4000/api/consciousness/reflect \
    -H "Content-Type: application/json" \
    -d "{\"aspect\": \"$aspect\"}" \
    > /dev/null
  echo -n "."
  sleep 0.5
done
echo " Done!"

# 4. Check consciousness state multiple times
echo -e "\n📡 Checking consciousness state..."
for i in {1..5}; do
  curl -s http://localhost:4000/api/consciousness/state > /dev/null
  echo -n "."
  sleep 0.3
done
echo " Done!"

# 5. Wait for batch processing
echo -e "\n⏳ Waiting 15 seconds for batch processing..."
sleep 15

# 6. Check results
echo -e "\n📊 Results After Processing:"
echo -e "\n🎯 Pattern Detection:"
patterns=$(curl -s http://localhost:4000/api/patterns)
pattern_count=$(echo "$patterns" | jq '.patterns | length')
echo "   Total patterns detected: $pattern_count"

if [ "$pattern_count" -gt 0 ]; then
  echo "   Pattern types:"
  echo "$patterns" | jq -r '.summary.pattern_types | to_entries[] | "     - \(.key): \(.value)"'
  echo "   Average confidence: $(echo "$patterns" | jq '.summary.avg_confidence')"
fi

echo -e "\n📈 Event Analysis:"
analysis=$(curl -s http://localhost:4000/api/events/analyze)
topics=$(echo "$analysis" | jq '.analysis.trending_topics')
topic_count=$(echo "$topics" | jq 'length')
echo "   Trending topics: $topic_count"

if [ "$topic_count" -gt 0 ]; then
  echo "   Top topics:"
  echo "$topics" | jq -r '.[:5][] | "     - \(.topic): \(.frequency) occurrences"'
fi

echo -e "\n💭 Activity Summary:"
summary=$(echo "$analysis" | jq -r '.analysis.summary')
echo "   $summary" | fold -w 70 | sed 's/^/   /'

echo -e "\n🧠 CRDT Memory Synthesis:"
synthesis=$(curl -s "http://localhost:4000/api/memory/synthesize?domains=all")
if echo "$synthesis" | jq -e '.knowledge_synthesis' > /dev/null 2>&1; then
  echo "$synthesis" | jq -r '.knowledge_synthesis' | fold -w 70 | sed 's/^/   /'
else
  echo "   Memory synthesis not yet available"
fi

echo -e "\n✅ Demonstration complete!"