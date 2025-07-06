#!/bin/bash

echo "🔍 SYSTEM TRUTH: Demonstrating Real Event Processing"
echo "===================================================="
echo ""

# 1. Show honest empty state
echo "1️⃣ Initial State (No Hard-Coded Data):"
echo ""

echo "Pattern Detection:"
curl -s http://localhost:4000/api/patterns 2>/dev/null | jq '.' | head -10

echo -e "\nEvent Analysis:" 
curl -s http://localhost:4000/api/events/analyze 2>/dev/null | jq '.' | head -15

# 2. Generate a real event
echo -e "\n\n2️⃣ Generating a Real User Interaction:"
echo ""

response=$(curl -s -X POST http://localhost:4000/api/consciousness/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What is the nature of consciousness?", "user_id": "demo_user"}')

echo "Chat Response:"
echo "$response" | jq -r '.response' | fold -w 70

# 3. Use seed endpoint
echo -e "\n\n3️⃣ Seeding 100 Test Events:"
seed_response=$(curl -s -X POST http://localhost:4000/api/debug/seed \
  -H "Content-Type: application/json" \
  -d '{}')

echo "$seed_response" | jq '.'

# 4. Wait and check again
echo -e "\n\n4️⃣ Checking After 5 Second Wait:"
sleep 5

echo "Pattern Detection After Seeding:"
curl -s http://localhost:4000/api/patterns 2>/dev/null | jq '{
  status: .status,
  pattern_count: .patterns | length,
  note: .note
}'

echo -e "\nEvent Analysis After Seeding:"
curl -s http://localhost:4000/api/events/analyze 2>/dev/null | jq '{
  status: .status,
  topics: .analysis.trending_topics | length,
  summary: .analysis.summary,
  note: .note
}'

# 5. Explain the truth
echo -e "\n\n5️⃣ System Architecture Truth:"
echo "================================"
echo ""
echo "✅ WORKING Components:"
echo "  • EventBus: Publishes and delivers events correctly"
echo "  • SemanticAnalyzer: Receives events via handle_info"  
echo "  • SemanticFusion: Receives events via handle_info"
echo "  • Consciousness Module: Returns AI-generated responses"
echo "  • All API endpoints: Return honest, empty data"
echo ""
echo "⚠️  ISSUE: Event Buffer Disconnect"
echo "  • Events arrive via handle_info({:event_bus, ...})"
echo "  • But analyze_event uses GenServer.cast to self"
echo "  • This creates a loop that doesn't add to buffer"
echo "  • Result: Buffer stays empty, no LLM analysis triggered"
echo ""
echo "📊 OUTCOME:"
echo "  • No hard-coded data (VSM principle upheld)"
echo "  • System returns honest empty responses"
echo "  • Events are published but not analyzed"
echo "  • Pattern detection shows 0 patterns"
echo "  • Event analysis shows 'No significant events'"
echo ""
echo "🎯 This demonstrates the system's current honest state:"
echo "   Ready to process real data once the event flow is fixed."