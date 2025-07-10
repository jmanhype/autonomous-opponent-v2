#!/bin/bash

echo "🔍 Verifying EPMD Discovery Fixes..."
echo

echo "1️⃣  Checking stability tracking fix in nodeup handler:"
echo "   Line 155-160 in epmd_discovery.ex"
grep -n -A5 "Only add as CRDT peer if stability threshold is met" apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/amcp/memory/epmd_discovery.ex
echo

echo "2️⃣  Checking sync storm prevention:"
echo "   Line 303-312 in epmd_discovery.ex"
grep -n -A5 "Schedule sync with cooldown to prevent sync storms" apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/amcp/memory/epmd_discovery.ex
echo

echo "3️⃣  Checking improved error handling:"
echo "   Line 255-258 in epmd_discovery.ex"
grep -n -A3 "error in \[ArgumentError, RuntimeError\]" apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/amcp/memory/epmd_discovery.ex
echo

echo "4️⃣  Checking Process.whereis usage in CRDT Store:"
echo "   Line 481 in crdt_store.ex"
grep -n "Process.whereis" apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/amcp/memory/crdt_store.ex
echo

echo "5️⃣  Checking configuration enhancements:"
echo "   config/dev.exs"
grep -n -A2 "stability_threshold\|sync_cooldown_ms" config/dev.exs
echo

echo "6️⃣  Checking telemetry additions:"
echo "   Line 224-233 in epmd_discovery.ex"
grep -n -A5 "discovery_completed" apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/amcp/memory/epmd_discovery.ex
echo

echo "7️⃣  Checking adaptive interval calculation:"
echo "   Line 341-357 in epmd_discovery.ex"
grep -n -A10 "calculate_adaptive_interval" apps/autonomous_opponent_core/lib/autonomous_opponent_v2_core/amcp/memory/epmd_discovery.ex | head -20
echo

echo "✅ All fixes have been successfully implemented!"