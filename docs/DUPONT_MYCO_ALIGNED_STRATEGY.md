# Dupont/Myco Aligned Strategy - Ground Truth Edition

Based on forensic code archaeology, here are 21 micro-PRs that build on ACTUAL code:

## 🗂 Slice · 🔀 Branch · 🌱 Flow · 🎯 Objective · 👣 Scope · ✅ Acceptance · ⚡ Why

### Phase 0: Foundation Fixes (Build on What Works)

**1. Wire Dead Channels**
- **Branch**: `myco/wire-vsm-subscribers`
- **Objective**: Connect S2-S5 as subscribers to variety channels that currently publish to nobody
- **Scope**: Add EventBus.subscribe calls in each VSM subsystem's init
- **Acceptance**: `grep -r "subscribe.*variety" apps/` shows 5+ results; integration test shows S2 receives S1 variety
- **Why**: Channels exist and work but nobody listens - easy win

**2. Enable CRDT Peer Sync**
- **Branch**: `myco/crdt-peersync-eventbus`
- **Objective**: Activate existing CRDT peer synchronization using EventBus transport (fallback already there)
- **Scope**: Uncomment sync timer in CRDTStore, fix handle_info clause
- **Acceptance**: Two iex nodes show merged CRDT state after 5 seconds
- **Why**: Code exists at lines 620-703, just needs activation

**3. Connect Real Metrics**
- **Branch**: `myco/dashboard-real-metrics`
- **Objective**: Replace rand.uniform() with actual metrics from Core.Metrics
- **Scope**: Update dashboard_live.ex to call Metrics.get_vsm_metrics()
- **Acceptance**: Dashboard shows non-random CPU/memory from :erlang.statistics
- **Why**: Metrics system works (lines 91-134), dashboard doesn't use it

### Phase 1: Activate Hidden Gems

**4. HNSW Pattern Storage**
- **Branch**: `myco/hnsw-pattern-activation`
- **Objective**: Wire pattern matcher results into HNSW vector store for similarity search
- **Scope**: Add EventBus handler in HNSW that stores matched patterns
- **Acceptance**: After 10 events, HNSW.search returns similar patterns
- **Why**: Complete HNSW implementation (963 lines!) sits unused

**5. Prometheus Export Route**
- **Branch**: `myco/metrics-prometheus-endpoint`
- **Objective**: Expose existing Prometheus format via /metrics endpoint
- **Scope**: Add route in router.ex calling Metrics.export_prometheus()
- **Acceptance**: curl /metrics returns text/plain Prometheus format
- **Why**: Metrics.export_prometheus exists (lines 295-308) but no route

**6. Algedonic Response Chain**
- **Branch**: `myco/algedonic-circuit-breaker`
- **Objective**: Connect health monitor pain signals to circuit breaker trips
- **Scope**: Add handler in CircuitBreaker for :algedonic_pain events
- **Acceptance**: Pain signal > 0.8 trips circuit breaker in test
- **Why**: Both systems exist independently, natural connection

### Phase 2: Distribution Foundation

**7. HLC Event Ordering**
- **Branch**: `myco/eventbus-hlc-ordering`
- **Objective**: Use HLC.compare_events in EventBus to order event processing
- **Scope**: Modify EventBus.handle_event to sort by HLC timestamp
- **Acceptance**: Out-of-order events process in causal order
- **Why**: HLC comparison exists, EventBus doesn't use it

**8. CRDT Knowledge Synthesis**
- **Branch**: `myco/crdt-llm-knowledge`
- **Objective**: Activate unused LLM synthesis in CRDTStore (lines 855-1088)
- **Scope**: Enable synthesis timer, add API key check
- **Acceptance**: After 50 belief updates, synthesis creates insight
- **Why**: Sophisticated code for knowledge synthesis sits dormant

**9. Distributed Rate Limit Redis**
- **Branch**: `myco/rate-limit-redis-wire`
- **Objective**: Connect distributed rate limiter to actual Redis
- **Scope**: Add Redix dependency, replace mock with real calls
- **Acceptance**: Two nodes share rate limit state via Redis
- **Why**: Lua scripts ready (lines 21-42), just needs connection

### Phase 3: Pattern Recognition Network

**10. Pattern Matcher Temporal**
- **Branch**: `myco/pattern-temporal-impl`
- **Objective**: Implement stubbed temporal patterns in pattern matcher
- **Scope**: Fill in match_temporal function with time-window logic
- **Acceptance**: "3 errors in 5 minutes" pattern triggers correctly
- **Why**: Structure exists, implementation is TODO

**11. VSM Pattern Library**
- **Branch**: `myco/vsm-pattern-presets`
- **Objective**: Expand pre-built VSM patterns (currently 3 basic ones)
- **Scope**: Add 10 operational patterns (overload, cascade, oscillation)
- **Acceptance**: New patterns detect known VSM failure modes
- **Why**: Pattern infrastructure works, needs domain patterns

**12. HNSW Persistence Active**
- **Branch**: `myco/hnsw-persistence-ets`
- **Objective**: Enable HNSW persistence to ETS (code exists, not wired)
- **Scope**: Add periodic dump timer, load on init
- **Acceptance**: HNSW survives restart with patterns intact
- **Why**: Persistence code complete but not activated

### Phase 4: Mesh Formation

**13. EventBus Cluster Bridge**
- **Branch**: `myco/eventbus-node-bridge`
- **Objective**: Forward EventBus events between nodes using :rpc
- **Scope**: Add node list config, cross-node publish
- **Acceptance**: Event on node A appears on node B EventBus
- **Why**: Simplest path to distributed events, no new deps

**14. CRDT Node Discovery**
- **Branch**: `myco/crdt-epmd-peers`
- **Objective**: Use Erlang's epmd for CRDT peer discovery
- **Scope**: Replace hardcoded peers with Node.list()
- **Acceptance**: New node auto-joins CRDT sync within 10s
- **Why**: CRDT sync protocol exists, needs peer discovery

**15. Metrics Aggregation Mesh**
- **Branch**: `myco/metrics-cross-node`
- **Objective**: Aggregate metrics across all nodes
- **Scope**: Add RPC calls in metrics to sum across Node.list()
- **Acceptance**: /metrics shows cluster-wide totals
- **Why**: Per-node metrics exist, aggregation is natural

### Phase 5: Intelligence Evolution

**16. Vector Store Event Stream**
- **Branch**: `myco/hnsw-event-learning`
- **Objective**: Stream all events through HNSW for pattern learning
- **Scope**: Subscribe HNSW to EventBus, vectorize events
- **Acceptance**: Similar events cluster in vector space
- **Why**: HNSW handles updates efficiently with pruning

**17. Pattern Feedback to S4**
- **Branch**: `myco/pattern-s4-intelligence`
- **Objective**: Send detected patterns from matcher to S4 Intelligence
- **Scope**: Add EventBus publish in pattern matcher
- **Acceptance**: S4 logs received patterns, updates strategy
- **Why**: S4 exists for environmental scanning, perfect fit

**18. CRDT Belief Convergence**
- **Branch**: `myco/crdt-belief-consensus`
- **Objective**: Use OR-Set CRDT for distributed belief agreement
- **Scope**: Implement belief voting using CRDT operations
- **Acceptance**: 3 nodes converge on shared belief set
- **Why**: OR-Set perfect for consensus without coordination

### Phase 6: Production Readiness

**19. Health Check Mesh Status**
- **Branch**: `myco/health-mesh-aware`
- **Objective**: Enhance /health to include cluster status
- **Scope**: Add node count, CRDT sync status, mesh health
- **Acceptance**: /health shows {"cluster_size": 3, "in_sync": true}
- **Why**: Health endpoint exists, make it mesh-aware

**20. Chaos Partition Recovery**
- **Branch**: `myco/crdt-partition-heal`
- **Objective**: Test and fix CRDT behavior during network splits
- **Scope**: Add partition detection, aggressive sync on heal
- **Acceptance**: Split nodes for 30s, state converges in <5s after
- **Why**: CRDT handles it theoretically, needs practical testing

**21. Metrics Compaction**
- **Branch**: `myco/metrics-prune-history`
- **Objective**: Implement time-based pruning for metrics ETS
- **Scope**: Add cleanup timer, configure retention period
- **Acceptance**: Metrics older than 24h auto-removed
- **Why**: Metrics persist to disk, will grow unbounded

## Why This Strategy Works

1. **Builds on Working Code**: Every PR enhances something that already exists
2. **No New Dependencies First**: Initial PRs use only what's in the codebase
3. **Natural Progression**: Foundation → Activation → Distribution → Intelligence
4. **Testable Increments**: Each PR has clear, measurable acceptance criteria
5. **Respects Architecture**: Follows existing patterns (EventBus, GenServer, ETS)

## Key Insights from Archaeology

- **CRDT system is production-ready** but needs transport layer
- **HNSW vector index is sophisticated** but completely disconnected  
- **Metrics infrastructure is comprehensive** but dashboard ignores it
- **Pattern matching exists** but temporal/statistical patterns are TODOs
- **VSM channels work perfectly** but have no subscribers

This isn't building new features - it's connecting the excellent code that already exists but was never wired together.