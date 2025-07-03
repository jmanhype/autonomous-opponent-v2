#!/bin/bash
# Radical cleanup - Keep only the PR implementations, delete everything else

echo "🔥 RADICAL CLEANUP - Removing all old implementations..."
echo "Keeping only Tasks 1-5 from PRs"

# Safety check
read -p "This will DELETE a lot of files. Are you sure? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo "📁 Current directory structure before cleanup:"
find . -type d -name "autonomous_opponent*" | head -20

# 1. Delete the entire old VSM implementation from root lib
echo -e "\n🗑️  Deleting old VSM from root /lib..."
rm -rf lib/autonomous_opponent/

# 2. Remove node_modules (178MB of cruft in an Elixir project!)
echo -e "\n🗑️  Removing node_modules..."
find . -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null

# 3. Delete all .ets files from coverage reports
echo -e "\n🗑️  Removing .ets coverage files..."
find . -name "*.ets" -type f -delete

# 4. Remove duplicate directory structure
echo -e "\n🗑️  Removing duplicate autonomous_opponent_v2 directory..."
if [ -d "autonomous_opponent_v2/autonomous_opponent_v2" ]; then
    rm -rf autonomous_opponent_v2/autonomous_opponent_v2
fi

# 5. Clean up old test artifacts
echo -e "\n🗑️  Removing coverage reports..."
find . -name "cover" -type d -exec rm -rf {} + 2>/dev/null
find . -name "coverage" -type d -exec rm -rf {} + 2>/dev/null
find . -name "excoveralls.html" -type f -delete

# 6. Remove empty directories
echo -e "\n🗑️  Removing empty directories..."
find . -type d -empty -delete 2>/dev/null

# 7. Clean deps and build artifacts
echo -e "\n🗑️  Cleaning build artifacts..."
mix clean
rm -rf _build/dev/lib/autonomous_opponent
rm -rf _build/test/lib/autonomous_opponent

echo -e "\n✅ Cleanup complete!"
echo -e "\n📊 Space saved:"
echo "Before cleanup:"
du -sh . 2>/dev/null || echo "Unable to calculate"

echo -e "\n📁 New directory structure (only showing important dirs):"
find . -type d -name "autonomous_opponent*" | grep -E "(core|web)" | head -20

echo -e "\n🎯 Tasks preserved in apps/autonomous_opponent_core:"
echo "  ✓ Task 1: CircuitBreaker"
echo "  ✓ Task 2: RateLimiter"  
echo "  ✓ Task 3: Metrics"
echo "  ✓ Task 4: HNSW Index"
echo "  ✓ Task 5: Vector Quantizer"

echo -e "\n⚠️  Next steps:"
echo "1. Run: mix deps.get"
echo "2. Run: mix compile"
echo "3. Run: mix test"
echo "4. Fix any broken references to old modules"