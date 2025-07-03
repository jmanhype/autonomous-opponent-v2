#!/bin/bash
# Fix all module naming to use consistent V2Core/V2Web pattern

echo "🔧 Fixing module naming chaos..."

# Fix in core app
echo "📦 Fixing core app modules..."

# Find all .ex files and fix module declarations
find apps/autonomous_opponent_core -name "*.ex" -type f | while read file; do
    # Skip the compatibility shims
    if [[ "$file" == *"autonomous_opponent/event_bus.ex" ]]; then
        echo "  ⏭️  Skipping shim: $file"
        continue
    fi
    
    # Fix module declarations
    sed -i 's/defmodule AutonomousOpponentCore\./defmodule AutonomousOpponentV2Core./g' "$file"
    sed -i 's/defmodule AutonomousOpponent\./defmodule AutonomousOpponentV2Core./g' "$file"
    
    # Fix alias statements
    sed -i 's/alias AutonomousOpponentCore\./alias AutonomousOpponentV2Core./g' "$file"
    sed -i 's/alias AutonomousOpponent\./alias AutonomousOpponentV2Core./g' "$file"
    
    # Fix module references in code
    sed -i 's/AutonomousOpponentCore\./AutonomousOpponentV2Core./g' "$file"
    # Don't blanket replace AutonomousOpponent. as it might break the shim
    
    # Check if file was modified
    if git diff --quiet "$file" 2>/dev/null; then
        :
    else
        echo "  ✓ Fixed: $file"
    fi
done

# Fix in web app
echo -e "\n📦 Fixing web app modules..."
find apps/autonomous_opponent_web -name "*.ex" -type f | while read file; do
    # Fix module declarations
    sed -i 's/defmodule AutonomousOpponentWeb\./defmodule AutonomousOpponentV2Web./g' "$file"
    sed -i 's/defmodule AutonomousOpponent\./defmodule AutonomousOpponentV2Web./g' "$file"
    
    # Fix alias statements
    sed -i 's/alias AutonomousOpponentWeb\./alias AutonomousOpponentV2Web./g' "$file"
    sed -i 's/alias AutonomousOpponent\./alias AutonomousOpponentV2Web./g' "$file"
    
    # Fix module references
    sed -i 's/AutonomousOpponentWeb\./AutonomousOpponentV2Web./g' "$file"
    
    if git diff --quiet "$file" 2>/dev/null; then
        :
    else
        echo "  ✓ Fixed: $file"
    fi
done

# Fix test files
echo -e "\n🧪 Fixing test modules..."
find test apps/*/test -name "*.exs" -type f | while read file; do
    # Core references
    sed -i 's/AutonomousOpponentCore\./AutonomousOpponentV2Core./g' "$file"
    sed -i 's/alias AutonomousOpponentCore/alias AutonomousOpponentV2Core/g' "$file"
    
    # Web references
    sed -i 's/AutonomousOpponentWeb\./AutonomousOpponentV2Web./g' "$file"
    sed -i 's/alias AutonomousOpponentWeb/alias AutonomousOpponentV2Web/g' "$file"
    
    # Be careful with AutonomousOpponent. replacements
    sed -i 's/defmodule AutonomousOpponent\./defmodule AutonomousOpponentV2Core./g' "$file"
    
    if git diff --quiet "$file" 2>/dev/null; then
        :
    else
        echo "  ✓ Fixed: $file"
    fi
done

# Fix config files
echo -e "\n⚙️  Fixing config files..."
find config -name "*.exs" -type f | while read file; do
    sed -i 's/AutonomousOpponentCore\./AutonomousOpponentV2Core./g' "$file"
    sed -i 's/AutonomousOpponentWeb\./AutonomousOpponentV2Web./g' "$file"
    
    if git diff --quiet "$file" 2>/dev/null; then
        :
    else
        echo "  ✓ Fixed: $file"
    fi
done

# Special handling for Task implementations
echo -e "\n🎯 Ensuring Task modules use V2Core namespace..."
TASK_FILES=(
    "apps/autonomous_opponent_core/lib/autonomous_opponent_core/core/circuit_breaker.ex"
    "apps/autonomous_opponent_core/lib/autonomous_opponent_core/core/rate_limiter.ex"
    "apps/autonomous_opponent_core/lib/autonomous_opponent_core/core/metrics.ex"
    "apps/autonomous_opponent_core/lib/autonomous_opponent/vsm/s4/vector_store/hnsw_index.ex"
    "apps/autonomous_opponent_core/lib/autonomous_opponent_core/vsm/s4/intelligence/vector_store/quantizer.ex"
)

for file in "${TASK_FILES[@]}"; do
    if [ -f "$file" ]; then
        # Extract filename for new module name
        case "$file" in
            *circuit_breaker.ex)
                sed -i 's/defmodule .*/defmodule AutonomousOpponentV2Core.Core.CircuitBreaker do/' "$file"
                ;;
            *rate_limiter.ex)
                sed -i 's/defmodule .*/defmodule AutonomousOpponentV2Core.Core.RateLimiter do/' "$file"
                ;;
            *metrics.ex)
                sed -i 's/defmodule .*/defmodule AutonomousOpponentV2Core.Core.Metrics do/' "$file"
                ;;
            *hnsw_index.ex)
                sed -i 's/defmodule .*/defmodule AutonomousOpponentV2Core.VSM.S4.VectorStore.HNSWIndex do/' "$file"
                ;;
            *quantizer.ex)
                sed -i 's/defmodule .*/defmodule AutonomousOpponentV2Core.VSM.S4.Intelligence.VectorStore.Quantizer do/' "$file"
                ;;
        esac
        echo "  ✓ Fixed Task module: $file"
    fi
done

echo -e "\n✅ Module naming fixed!"
echo -e "\nNext steps:"
echo "1. Run: mix deps.get"
echo "2. Run: mix compile"
echo "3. Fix any remaining compilation errors"