# Dupont/Myco CI/CD Integration Guide

## Overview
This guide documents how our sophisticated CI/CD workflows support the 21 micro-PRs in the Dupont/myco transformation strategy.

## Available CI/CD Workflows

### 1. VSM-Enhanced CI/CD Pipeline
**File**: `.github/workflows/vsm-enhanced-ci-cd.yml`
- **S1 Operations**: Parallel test execution
- **S2 Coordination**: Concurrent quality checks
- **S3 Control**: Resource optimization
- **S4 Intelligence**: Pattern analysis and learning
- **S5 Policy**: Dynamic threshold adjustment
- **Algedonic Monitoring**: Pain/pleasure signal detection

### 2. Claude Integration
**Files**: 
- `.github/workflows/claude-pr-assistant-enhanced.yml`
- `.github/workflows/claude-vsm-advisor.yml`

**Commands**:
- `@claude` - Get implementation help
- `@claude-validate` - Run full validation suite
- `/vsm analyze --phase X` - Analyze specific VSM phase
- `/task create --title "..." --tag phase-X` - Create tracked tasks

**Authentication Strategy**:
- Development branches: OAuth (Max subscription)
- Production branches: API key
- Turn limits based on task complexity

### 3. PR Validation Helper
**File**: `.github/workflows/pr-validation-helper.yml`

**Validates**:
- Code formatting (`mix format`)
- Code quality (`mix credo --strict`)
- Compilation without warnings
- Test coverage (40%+ required)
- Docker build success

## Integration with Micro-PRs

### Phase 0: Foundation Fixes

#### Issue #76 - Wire Dead VSM Variety Channels
- Automated validation of EventBus subscriptions
- Test variety flow between S1-S5
- Algedonic monitoring for system stability

#### Issue #78 - Connect Real Metrics
- Validate removal of `rand.uniform()` calls
- Ensure metrics match system state
- Performance benchmarks for metric collection

#### Issue #80 - Prometheus Endpoint
- Automatic metric validation
- Integration with existing Grafana setup
- Performance testing (<100ms response)

### Phase 1: Activate Hidden Gems

#### Issue #79 - HNSW Pattern Storage
- Performance benchmarks for vector operations
- Memory usage monitoring
- Pattern clustering validation

#### Issue #83 - LLM Knowledge Synthesis
- API key validation
- Rate limit monitoring
- Cost tracking per synthesis

### Phase 2: Distribution Foundation

#### Issue #88 - EventBus Cluster Bridge
- Multi-node testing with Docker Compose
- Network partition simulation
- Loop detection validation

#### Issue #94 - Cluster-Aware Health
- Load balancer integration testing
- Response time validation (<100ms)
- Cluster state accuracy checks

### Phase 3: Pattern Recognition

#### Issue #91 - HNSW Event Learning
- Continuous pattern collection
- Similarity clustering validation
- Performance benchmarks

## Automated Testing Strategies

### 1. Unit Tests
```elixir
# Mock external dependencies
defmodule MyTest do
  use ExUnit.Case
  import Mox
  
  setup :verify_on_exit!
  
  test "variety flows through channels" do
    # Test implementation
  end
end
```

### 2. Integration Tests
```yaml
- name: Multi-Node Integration Test
  run: |
    docker-compose up -d
    mix test --only integration:true
```

### 3. Chaos Engineering
```yaml
- name: Network Partition Test
  run: |
    ./scripts/simulate_partition.sh
    ./scripts/verify_recovery.sh
```

## Performance Requirements

### Latency Targets
- Algedonic response: <100ms
- Health endpoint: <100ms
- HNSW search: <100ms
- Event propagation: <500ms

### Throughput Targets
- 100 requests/second (current limit)
- 10,000 events/minute processing
- 1M CRDT operations/hour

## Monitoring & Observability

### Metrics Exposed
- `vsm_variety_throughput_total`
- `vsm_algedonic_latency_seconds`
- `vsm_crdt_sync_latency_seconds`
- `vsm_emergency_mode`
- `vsm_pattern_clusters_total`

### Algedonic Thresholds
- Mild pain: 1-2 failures
- Moderate pain: 3-4 failures
- Severe pain: 5+ failures or critical system failure
- Emergency issue creation on severe pain

## Best Practices

### 1. Use Claude Effectively
- Be specific in requests
- Reference file paths and line numbers
- Use task tags for organization

### 2. Test Incrementally
- Unit tests first
- Integration tests second
- Performance tests last

### 3. Monitor Emergence
- Weekly pattern analysis
- Unexpected beneficial behaviors
- System self-organization

## Common Commands

### Development
```bash
# Run with Claude assistance
@claude implement variety subscription in S2

# Validate changes
@claude-validate

# Analyze VSM impact
/vsm analyze --phase 2
```

### Testing
```bash
# Run specific test suite
mix test test/vsm/s2_coordination_test.exs

# Run with coverage
mix test --cover

# Run integration tests
mix test --only integration:true
```

### Deployment
```bash
# Check system health
curl localhost:4000/health

# Scrape metrics
curl localhost:4000/metrics

# View algedonic status
mix run scripts/check_algedonic.exs
```

## Troubleshooting

### CI/CD Failures
1. Check algedonic signals in workflow logs
2. Look for S4 Intelligence analysis
3. Review S5 Policy adjustments
4. Use `@claude` for root cause analysis

### Performance Issues
1. Check HNSW vector dimensions
2. Verify CRDT sync intervals
3. Monitor EventBus queue depth
4. Review rate limiter settings

### Integration Problems
1. Verify node connectivity
2. Check authentication (OAuth vs API)
3. Review network partition logs
4. Validate CRDT convergence

## Next Steps

1. Implement Phase 0 PRs first (foundation)
2. Use CI/CD validation throughout
3. Monitor emergence patterns
4. Let Claude assist with complex implementations
5. Track algedonic signals for system health

Remember: The CI/CD pipeline is itself a VSM system, with each workflow component serving a specific cybernetic function!