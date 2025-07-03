#!/bin/bash
# Consolidate all lib files into the correct autonomous_opponent_v2_core directory

echo "🔧 Consolidating lib directory structure..."

cd apps/autonomous_opponent_core/lib

# Create the correct directory structure
mkdir -p autonomous_opponent_v2_core/amcp
mkdir -p autonomous_opponent_v2_core/core
mkdir -p autonomous_opponent_v2_core/vsm/s4/intelligence/vector_store
mkdir -p autonomous_opponent_v2_core/vsm/s4/vector_store

echo "📁 Moving files from autonomous_opponent_core/ to autonomous_opponent_v2_core/..."

# Move AMCP files
mv autonomous_opponent_core/amcp/* autonomous_opponent_v2_core/amcp/ 2>/dev/null
# Move core files (Tasks 1-3)
mv autonomous_opponent_core/core/* autonomous_opponent_v2_core/core/ 2>/dev/null
# Move VSM files
mv autonomous_opponent_core/vsm/*.ex autonomous_opponent_v2_core/vsm/ 2>/dev/null
# Move intelligence files (Task 5)
mv autonomous_opponent_core/vsm/s4/intelligence/vector_store/* autonomous_opponent_v2_core/vsm/s4/intelligence/vector_store/ 2>/dev/null
# Move top-level files
mv autonomous_opponent_core/*.ex autonomous_opponent_v2_core/ 2>/dev/null

echo "📁 Moving files from autonomous_opponent/ to autonomous_opponent_v2_core/..."

# Move vector store files (Task 4)
mv autonomous_opponent/vsm/s4/vector_store/* autonomous_opponent_v2_core/vsm/s4/vector_store/ 2>/dev/null

# Clean up empty directories
echo "🗑️  Removing empty directories..."
find autonomous_opponent_core -type d -empty -delete 2>/dev/null
find autonomous_opponent -type d -empty -delete 2>/dev/null
rmdir autonomous_opponent_core 2>/dev/null
rmdir autonomous_opponent 2>/dev/null

echo "✅ Directory structure consolidated!"
echo ""
echo "📊 New structure:"
find autonomous_opponent_v2_core -type f -name "*.ex" | sort | head -20