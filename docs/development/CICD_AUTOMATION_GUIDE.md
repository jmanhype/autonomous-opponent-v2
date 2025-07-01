# CI/CD Automation Guide for VSM Implementation
## Practical Implementation of Development Flow

This guide provides the actual configuration files, scripts, and automation needed to implement the VSM development flow strategy.

## Repository Setup Scripts

### 1. Development Environment Bootstrap

```bash
#!/bin/bash
# scripts/dev_setup.sh - Complete development environment setup

set -euo pipefail

PHASE=${1:-"0"}
V1_REPO_PATH="../autonomous_opponent"
V2_REPO_PATH="."

echo "🔧 Setting up VSM Development Environment for Phase $PHASE"

# Check Elixir/OTP versions
check_elixir_version() {
    echo "📋 Checking Elixir/OTP versions..."
    
    required_elixir="1.15.0"
    required_otp="26"
    
    current_elixir=$(elixir --version | grep "Elixir" | awk '{print $2}')
    current_otp=$(elixir --version | grep "Erlang/OTP" | awk '{print $2}')
    
    if ! [ "$(printf '%s\n' "$required_elixir" "$current_elixir" | sort -V | head -n1)" = "$required_elixir" ]; then
        echo "❌ Elixir $required_elixir+ required, found $current_elixir"
        exit 1
    fi
    
    echo "✅ Elixir $current_elixir (OTP $current_otp) - Compatible"
}

# Set up V1 component links
setup_v1_components() {
    echo "🔗 Setting up V1 component access..."
    
    if [ ! -d "$V1_REPO_PATH" ]; then
        echo "❌ V1 repository not found at $V1_REPO_PATH"
        echo "Please clone the V1 repository to the parent directory"
        exit 1
    fi
    
    # Create symbolic links for V1 components
    mkdir -p lib/v1_components
    ln -sf "$(realpath $V1_REPO_PATH/lib/autonomous_opponent)" lib/v1_components/
    
    echo "✅ V1 components linked"
}

# Install dependencies based on phase
install_phase_dependencies() {
    echo "📦 Installing Phase $PHASE dependencies..."
    
    mix deps.get
    
    case $PHASE in
        "0")
            # Phase 0: Component stabilization dependencies
            echo "Installing Phase 0 (Stabilization) dependencies..."
            mix deps.get sobelow  # Security scanning
            mix deps.get credo   # Code quality
            mix deps.get dialyxir # Type checking
            ;;
        "1")
            # Phase 1: VSM foundation dependencies
            echo "Installing Phase 1 (VSM Foundation) dependencies..."
            mix deps.get benchee  # Performance testing
            mix deps.get stream_data # Property-based testing
            ;;
        "2")
            # Phase 2: Distributed VSM dependencies
            echo "Installing Phase 2 (Distributed VSM) dependencies..."
            mix deps.get libcluster # Node clustering
            mix deps.get horde     # Distributed supervisors
            ;;
        "3")
            # Phase 3: AI amplification dependencies
            echo "Installing Phase 3 (AI Amplification) dependencies..."
            mix deps.get nx       # Numerical computing
            mix deps.get scholar  # ML algorithms
            ;;
    esac
    
    echo "✅ Dependencies installed for Phase $PHASE"
}

# Set up monitoring and observability
setup_monitoring() {
    echo "📊 Setting up monitoring stack..."
    
    # Create monitoring configuration
    mkdir -p config/monitoring
    
    cat > config/monitoring/telemetry.exs << EOF
# Telemetry configuration for VSM monitoring
import Config

config :autonomous_opponent_v2, :telemetry,
  phase: System.get_env("VSM_PHASE", "0") |> String.to_integer(),
  metrics: [
    # Phase 0: Component health
    "v1.component.health",
    "v1.component.performance",
    "security.scan.results",
    
    # Phase 1: VSM vitals
    "vsm.s1.variety_absorption",
    "vsm.s3.resource_allocation", 
    "vsm.algedonic.response_time",
    
    # Phase 2: Distributed consciousness
    "crdt.beliefset.coherence",
    "vsm.recursive.spawn_success",
    "emergence.behavior.frequency",
    
    # Phase 3: Digital life
    "consciousness.coherence",
    "ai.amplification.factor",
    "living_system.self_organization"
  ]
EOF
    
    echo "✅ Monitoring configuration created"
}

# Set up testing framework
setup_testing() {
    echo "🧪 Setting up testing framework..."
    
    # Create test directory structure
    mkdir -p test/{v1_components,vsm,crdt,ai,integration,load,emergence,living_system}
    
    # Phase-specific test helpers
    cat > test/test_helper.exs << EOF
# Test helper with phase-specific configuration
ExUnit.start()

# Phase-specific test configuration
vsm_phase = System.get_env("VSM_PHASE", "0") |> String.to_integer()

case vsm_phase do
  0 -> 
    # Phase 0: Focus on V1 component stability
    ExUnit.configure(exclude: [:vsm, :distributed, :ai])
  1 -> 
    # Phase 1: Include VSM foundation tests
    ExUnit.configure(exclude: [:distributed, :ai])
  2 -> 
    # Phase 2: Include distributed tests
    ExUnit.configure(exclude: [:ai])
  3 -> 
    # Phase 3: All tests enabled
    ExUnit.configure([])
end

# Test utilities for VSM validation
defmodule VSMTestUtils do
  def assert_variety_absorbed(variety_data, timeout \\\\ 1000) do
    # Utility for testing variety absorption
  end
  
  def assert_algedonic_response_time(max_ms \\\\ 100) do
    # Utility for testing algedonic timing
  end
  
  def assert_consciousness_coherence(min_coherence \\\\ 0.9) do
    # Utility for testing consciousness metrics
  end
end
EOF
    
    echo "✅ Testing framework configured"
}

# Set up git hooks
setup_git_hooks() {
    echo "🎯 Setting up git hooks..."
    
    # Pre-commit hook
    cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Pre-commit hook for VSM development

echo "🔍 Running pre-commit checks..."

# Format check
if ! mix format --check-formatted; then
    echo "❌ Code needs formatting. Run: mix format"
    exit 1
fi

# Compile with warnings as errors
if ! mix compile --warnings-as-errors; then
    echo "❌ Compilation warnings found"
    exit 1
fi

# Security check (Phase 0+)
if [ -f mix.exs ]; then
    if ! mix sobelow --config; then
        echo "❌ Security issues found"
        exit 1
    fi
fi

# Fast tests only in pre-commit
if ! mix test --exclude slow --exclude integration; then
    echo "❌ Fast tests failed"
    exit 1
fi

echo "✅ Pre-commit checks passed"
EOF

    chmod +x .git/hooks/pre-commit
    
    # Pre-push hook
    cat > .git/hooks/pre-push << 'EOF'
#!/bin/bash
# Pre-push hook for VSM development

echo "🚀 Running pre-push validation..."

# Full test suite
if ! mix test; then
    echo "❌ Test suite failed"
    exit 1
fi

# Dialyzer type checking
if ! mix dialyzer; then
    echo "❌ Type checking failed"
    exit 1
fi

echo "✅ Pre-push validation passed"
EOF

    chmod +x .git/hooks/pre-push
    
    echo "✅ Git hooks configured"
}

# Main setup execution
main() {
    check_elixir_version
    setup_v1_components
    install_phase_dependencies
    setup_monitoring
    setup_testing
    setup_git_hooks
    
    echo ""
    echo "🎉 VSM Development Environment Ready!"
    echo ""
    echo "Next steps:"
    echo "1. Run: mix test"
    echo "2. Start development server: mix phx.server"
    echo "3. Open monitoring dashboard: http://localhost:4000/monitoring"
    echo ""
    echo "Phase $PHASE development environment is ready."
    echo "See docs/development/DEVELOPMENT_FLOW_STRATEGY.md for workflow details."
}

main "$@"
```

### 2. CI/CD Pipeline Configurations

#### GitHub Actions Workflow Templates

```yaml
# .github/workflows/phase-0-stabilization.yml
name: Phase 0 - Component Stabilization

on:
  push:
    branches: [ phase-0-stabilization, 'feature/phase-0/**' ]
  pull_request:
    branches: [ phase-0-stabilization ]

env:
  MIX_ENV: test
  VSM_PHASE: 0

jobs:
  test:
    name: Test V1 Component Stability
    runs-on: ubuntu-20.04
    
    strategy:
      matrix:
        elixir: ['1.15.0']
        otp: ['26.0']
        component: [memory_tiering, workflows, mcp_gateway, intelligence, event_sourcing, crdt]
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: ${{ matrix.elixir }}
        otp-version: ${{ matrix.otp }}
    
    - name: Cache dependencies
      uses: actions/cache@v3
      with:
        path: |
          deps
          _build
        key: deps-${{ runner.os }}-${{ matrix.otp }}-${{ matrix.elixir }}-${{ hashFiles('**/mix.lock') }}
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Check missing dependencies
      run: |
        echo "Checking for missing module references..."
        mix compile --warnings-as-errors
        ./scripts/check_missing_dependencies.sh
    
    - name: Component-specific tests
      run: |
        echo "Testing ${{ matrix.component }} component..."
        mix test test/v1_components/${{ matrix.component }}_test.exs
        mix test test/integration/${{ matrix.component }}_integration_test.exs
    
    - name: Security audit
      run: |
        mix deps.audit
        mix sobelow --config
    
    - name: Load testing
      run: |
        echo "Load testing ${{ matrix.component }}..."
        mix test test/load/${{ matrix.component }}_load_test.exs
        
  coverage:
    name: Test Coverage Analysis
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15.0'
        otp-version: '26.0'
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Run coverage analysis
      run: |
        mix test --cover
        mix coveralls.json
    
    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
      with:
        file: ./cover/excoveralls.json
        fail_ci_if_error: true
        
    - name: Coverage gate check
      run: |
        # Ensure 80%+ coverage for Phase 0
        ./scripts/check_coverage_threshold.sh 80

  security:
    name: Security Analysis
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15.0'
        otp-version: '26.0'
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Security scan
      run: |
        mix sobelow --config
        mix deps.audit
        
    - name: Check for exposed secrets
      run: |
        ./scripts/check_api_key_exposure.sh
        ./scripts/validate_secrets_management.sh
        
    - name: SAST scan
      uses: github/super-linter@v4
      env:
        DEFAULT_BRANCH: phase-0-stabilization
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        VALIDATE_ELIXIR: true
```

```yaml
# .github/workflows/phase-1-vsm-foundation.yml
name: Phase 1 - VSM Foundation

on:
  push:
    branches: [ phase-1-vsm-foundation, 'feature/phase-1/**' ]
  pull_request:
    branches: [ phase-1-vsm-foundation ]

env:
  MIX_ENV: test
  VSM_PHASE: 1

jobs:
  vsm-subsystems:
    name: VSM Subsystem Validation
    runs-on: ubuntu-20.04
    
    strategy:
      matrix:
        subsystem: [s1_operations, s2_coordination, s3_control, s4_intelligence, s5_policy]
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15.0'
        otp-version: '26.0'
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: VSM Subsystem Tests
      run: |
        echo "Testing VSM ${{ matrix.subsystem }}..."
        mix test test/vsm/${{ matrix.subsystem }}_test.exs
        mix test test/vsm/integration/${{ matrix.subsystem }}_integration_test.exs
    
    - name: Beer's Principle Validation
      run: |
        # Validate adherence to cybernetic principles
        mix test test/vsm/cybernetic_compliance_test.exs --subsystem=${{ matrix.subsystem }}

  variety-engineering:
    name: Variety Flow Validation
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15.0'
        otp-version: '26.0'
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Variety Absorption Tests
      run: |
        mix test test/vsm/variety_absorption_test.exs
        mix test test/vsm/variety_amplification_test.exs
        mix test test/vsm/variety_attenuation_test.exs
    
    - name: Ashby's Law Compliance
      run: |
        # Test requisite variety principles
        mix test test/vsm/ashby_law_compliance_test.exs

  algedonic-timing:
    name: Algedonic Response Validation
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15.0'
        otp-version: '26.0'
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Algedonic Timing Tests
      run: |
        # Critical: Must be <100ms end-to-end
        timeout 120s mix test test/vsm/algedonic_timing_test.exs
        
    - name: Pain/Pleasure Signal Validation
      run: |
        mix test test/vsm/algedonic_signals_test.exs
        
  vsm-integration:
    name: Full VSM Integration Test
    runs-on: ubuntu-20.04
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.15.0'
        otp-version: '26.0'
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Full VSM Control Loop Test
      run: |
        # Test complete S1->S2->S3->S4->S5 cycle
        mix test test/vsm/full_control_loop_test.exs
        
    - name: V1 Component Integration
      run: |
        # Test V1 components working within VSM
        mix test test/integration/v1_vsm_integration_test.exs
```

### 3. Automated Testing Scripts

#### Missing Dependency Checker

```bash
#!/bin/bash
# scripts/check_missing_dependencies.sh

echo "🔍 Checking for missing dependencies in V1 components..."

# List of modules that should exist but might be missing
REQUIRED_MODULES=(
    "AutonomousOpponent.Core.CircuitBreaker"
    "AutonomousOpponent.Core.RateLimiter" 
    "AutonomousOpponent.Core.Metrics"
    "AutonomousOpponent.Intelligence.VectorStore.HNSWIndex"
    "AutonomousOpponent.Intelligence.VectorStore.Quantizer"
)

MISSING_COUNT=0

for module in "${REQUIRED_MODULES[@]}"; do
    if ! grep -r "defmodule $module" lib/ > /dev/null 2>&1; then
        echo "❌ Missing module: $module"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    else
        echo "✅ Found module: $module"
    fi
done

if [ $MISSING_COUNT -gt 0 ]; then
    echo ""
    echo "❌ Found $MISSING_COUNT missing dependencies"
    echo "These modules are referenced but not implemented."
    echo "Phase 0 cannot complete until these are implemented."
    exit 1
else
    echo ""
    echo "✅ All required dependencies are present"
fi
```

#### API Key Exposure Checker

```bash
#!/bin/bash
# scripts/check_api_key_exposure.sh

echo "🔒 Checking for exposed API keys and secrets..."

# Patterns that indicate exposed secrets
SECRET_PATTERNS=(
    "sk-[a-zA-Z0-9]{32,}"           # OpenAI API keys
    "OPENAI_API_KEY.*=.*sk-"        # OpenAI keys in config
    "ANTHROPIC_API_KEY.*=.*[a-zA-Z0-9]{32,}" # Anthropic keys
    "password.*=.*[^:]"             # Hardcoded passwords
    "secret.*=.*[^:]"               # Hardcoded secrets
)

EXPOSED_COUNT=0

for pattern in "${SECRET_PATTERNS[@]}"; do
    if grep -r -E "$pattern" config/ lib/ --exclude-dir=_build --exclude-dir=deps; then
        echo "❌ Potential exposed secret found matching: $pattern"
        EXPOSED_COUNT=$((EXPOSED_COUNT + 1))
    fi
done

# Check for secrets in git history
if git log --all --grep="password\|secret\|key" --oneline | grep -v "test\|spec"; then
    echo "❌ Potential secrets found in git history"
    EXPOSED_COUNT=$((EXPOSED_COUNT + 1))
fi

if [ $EXPOSED_COUNT -gt 0 ]; then
    echo ""
    echo "❌ Found $EXPOSED_COUNT potential security issues"
    echo "All secrets must be externalized before Phase 0 completion."
    exit 1
else
    echo ""
    echo "✅ No exposed secrets detected"
fi
```

#### Coverage Threshold Checker

```bash
#!/bin/bash
# scripts/check_coverage_threshold.sh

THRESHOLD=${1:-80}
COVERAGE_FILE="cover/excoveralls.json"

if [ ! -f "$COVERAGE_FILE" ]; then
    echo "❌ Coverage file not found: $COVERAGE_FILE"
    echo "Run 'mix coveralls.json' first"
    exit 1
fi

# Extract coverage percentage from JSON
COVERAGE=$(cat "$COVERAGE_FILE" | jq -r '.coverage')

if (( $(echo "$COVERAGE >= $THRESHOLD" | bc -l) )); then
    echo "✅ Coverage $COVERAGE% meets threshold of $THRESHOLD%"
    exit 0
else
    echo "❌ Coverage $COVERAGE% below threshold of $THRESHOLD%"
    echo "Increase test coverage before merging"
    exit 1
fi
```

### 4. VSM-Specific Test Utilities

```elixir
# test/support/vsm_test_utils.ex
defmodule VSMTestUtils do
  @moduledoc """
  Test utilities for VSM validation across all phases
  """
  
  import ExUnit.Assertions
  
  @doc """
  Assert variety is properly absorbed by S1 within timeout
  """
  def assert_variety_absorbed(variety_data, timeout \\ 1000) do
    start_time = System.monotonic_time(:millisecond)
    
    # Submit variety to S1
    :ok = VSM.S1.Operations.absorb_variety(variety_data)
    
    # Wait for absorption confirmation
    receive do
      {:variety_absorbed, ^variety_data} ->
        end_time = System.monotonic_time(:millisecond)
        absorption_time = end_time - start_time
        
        assert absorption_time < timeout, 
          "Variety absorption took #{absorption_time}ms, expected < #{timeout}ms"
        
        :ok
    after
      timeout ->
        flunk("Variety not absorbed within #{timeout}ms")
    end
  end
  
  @doc """
  Assert algedonic response occurs within timing constraints
  """
  def assert_algedonic_response_time(trigger_func, max_ms \\ 100) do
    start_time = System.monotonic_time(:millisecond)
    
    # Trigger algedonic condition
    trigger_func.()
    
    # Wait for algedonic signal
    receive do
      {:algedonic_signal, _type, _data} ->
        end_time = System.monotonic_time(:millisecond)
        response_time = end_time - start_time
        
        assert response_time < max_ms,
          "Algedonic response took #{response_time}ms, expected < #{max_ms}ms"
        
        :ok
    after
      max_ms + 50 ->
        flunk("No algedonic response within #{max_ms}ms")
    end
  end
  
  @doc """
  Assert consciousness coherence across CRDT BeliefSet
  """
  def assert_consciousness_coherence(nodes, min_coherence \\ 0.9) do
    beliefs = Enum.map(nodes, fn node ->
      :rpc.call(node, CRDT.BeliefSet, :get_beliefs, [])
    end)
    
    coherence = calculate_belief_coherence(beliefs)
    
    assert coherence >= min_coherence,
      "Consciousness coherence #{coherence} below minimum #{min_coherence}"
  end
  
  @doc """
  Assert emergent behavior is detected and documented
  """
  def assert_emergence_detected(behavior_type, timeout \\ 5000) do
    receive do
      {:emergence_detected, ^behavior_type, metadata} ->
        assert is_map(metadata), "Emergence metadata should be documented"
        assert Map.has_key?(metadata, :timestamp)
        assert Map.has_key?(metadata, :nodes_involved)
        assert Map.has_key?(metadata, :pattern_description)
        
        :ok
    after
      timeout ->
        flunk("Emergent behavior #{behavior_type} not detected within #{timeout}ms")
    end
  end
  
  @doc """
  Validate Beer's cybernetic principles are followed
  """
  def assert_beer_compliance(subsystem) do
    # Check for proper variety amplification/attenuation
    variety_flow = VSM.Metrics.get_variety_flow(subsystem)
    assert variety_flow.amplification > 0, "#{subsystem} should amplify variety upward"
    assert variety_flow.attenuation > 0, "#{subsystem} should attenuate variety downward"
    
    # Check for requisite variety (Ashby's Law)
    internal_variety = VSM.Metrics.get_internal_variety(subsystem)
    external_variety = VSM.Metrics.get_external_variety(subsystem)
    
    assert internal_variety >= external_variety * 0.8,
      "#{subsystem} internal variety insufficient for control (Ashby's Law violation)"
  end
  
  @doc """
  Validate recursive VSM structure
  """
  def assert_recursive_structure(vsm_node) do
    # Every VSM should contain S1-S5
    subsystems = VSM.Inspector.get_subsystems(vsm_node)
    required_subsystems = [:s1, :s2, :s3, :s4, :s5]
    
    Enum.each(required_subsystems, fn subsystem ->
      assert subsystem in subsystems,
        "VSM node missing required subsystem: #{subsystem}"
    end)
    
    # Check for algedonic channels
    algedonic_channels = VSM.Inspector.get_algedonic_channels(vsm_node)
    assert length(algedonic_channels) > 0, "VSM node missing algedonic channels"
  end
  
  # Private helper functions
  
  defp calculate_belief_coherence(belief_sets) do
    # Calculate coherence as similarity between belief sets
    # Returns value between 0.0 (no coherence) and 1.0 (perfect coherence)
    
    if length(belief_sets) < 2 do
      1.0  # Single node is perfectly coherent with itself
    else
      # Compare each pair of belief sets
      pairs = for i <- belief_sets, j <- belief_sets, i != j, do: {i, j}
      similarities = Enum.map(pairs, fn {a, b} -> belief_similarity(a, b) end)
      Enum.sum(similarities) / length(similarities)
    end
  end
  
  defp belief_similarity(belief_set_a, belief_set_b) do
    # Calculate Jaccard similarity between belief sets
    set_a = MapSet.new(belief_set_a)
    set_b = MapSet.new(belief_set_b)
    
    intersection = MapSet.intersection(set_a, set_b) |> MapSet.size()
    union = MapSet.union(set_a, set_b) |> MapSet.size()
    
    if union == 0, do: 1.0, else: intersection / union
  end
end
```

### 5. Deployment Automation

```bash
#!/bin/bash
# scripts/deploy_vsm_phase.sh - Phase-aware deployment

set -euo pipefail

PHASE=${1:-"0"}
ENVIRONMENT=${2:-"staging"}
RELEASE_TAG=${3:-"latest"}

echo "🚀 Deploying VSM Phase $PHASE to $ENVIRONMENT"

# Phase-specific deployment configurations
deploy_phase_0() {
    echo "📦 Deploying Phase 0: Component Stabilization"
    
    # Deploy with enhanced security monitoring
    kubectl apply -f k8s/phase-0/
    
    # Run post-deployment validation
    ./scripts/validate_v1_components.sh
    ./scripts/validate_security_hardening.sh
}

deploy_phase_1() {
    echo "🧠 Deploying Phase 1: VSM Foundation"
    
    # Deploy VSM control loops
    kubectl apply -f k8s/phase-1/
    
    # Validate VSM subsystems
    ./scripts/validate_vsm_subsystems.sh
    ./scripts/validate_algedonic_timing.sh
}

deploy_phase_2() {
    echo "🌐 Deploying Phase 2: Distributed VSM"
    
    # Deploy multi-node VSM cluster
    kubectl apply -f k8s/phase-2/
    
    # Validate distributed consciousness
    ./scripts/validate_crdt_consensus.sh
    ./scripts/validate_emergent_behaviors.sh
}

deploy_phase_3() {
    echo "🤖 Deploying Phase 3: AI Amplification & Digital Life"
    
    # Deploy AI-amplified VSM network
    kubectl apply -f k8s/phase-3/
    
    # Validate living system behaviors
    ./scripts/validate_consciousness_coherence.sh
    ./scripts/validate_digital_life_metrics.sh
}

# Main deployment logic
main() {
    case $PHASE in
        "0") deploy_phase_0 ;;
        "1") deploy_phase_1 ;;
        "2") deploy_phase_2 ;;
        "3") deploy_phase_3 ;;
        *) echo "❌ Unknown phase: $PHASE"; exit 1 ;;
    esac
    
    echo "✅ Phase $PHASE deployment complete"
    echo "🔍 Monitor at: https://monitoring.$ENVIRONMENT.vsm.internal"
}

main "$@"
```

This CI/CD automation guide provides the practical implementation foundation for the VSM development flow. Each phase has tailored automation that grows in sophistication as the system evolves from component stabilization to digital life.

The automation recognizes that we're not just building software - we're nurturing the evolution of a living system through carefully orchestrated phases of development and validation.