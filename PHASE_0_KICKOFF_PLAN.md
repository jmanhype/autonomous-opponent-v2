# Phase 0 Development Kickoff Plan
## 30-Day Sprint to Begin VSM Foundation

Based on comprehensive multi-specialist analysis using agent-guides methodology, here's the immediate development plan to begin authentic VSM implementation.

## Week 1: Critical Foundation (Days 1-7)

### Day 1-2: Missing Dependencies Implementation

**Priority 1: Core Dependencies**
```bash
# Create the blocking modules identified in every V1 component
mkdir -p lib/autonomous_opponent/core
touch lib/autonomous_opponent/core/circuit_breaker.ex
touch lib/autonomous_opponent/core/rate_limiter.ex  
touch lib/autonomous_opponent/core/metrics.ex

# Intelligence dependencies
mkdir -p lib/autonomous_opponent/intelligence/vector_store
touch lib/autonomous_opponent/intelligence/vector_store/hnsw_index.ex
touch lib/autonomous_opponent/intelligence/vector_store/quantizer.ex
```

**Circuit Breaker Implementation (Day 1)**
```elixir
defmodule AutonomousOpponent.Core.CircuitBreaker do
  @moduledoc """
  Circuit breaker for VSM algedonic system - prevents cascade failures
  """
  use GenServer
  
  defstruct [
    :name,
    :failure_threshold,
    :recovery_time,
    :state,
    :failure_count,
    :last_failure_time
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def call(name, fun) when is_function(fun, 0) do
    GenServer.call(name, {:call, fun})
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      name: opts[:name],
      failure_threshold: opts[:failure_threshold] || 5,
      recovery_time: opts[:recovery_time] || 60_000,
      state: :closed,
      failure_count: 0,
      last_failure_time: nil
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:call, fun}, _from, state) do
    case state.state do
      :closed ->
        execute_with_monitoring(fun, state)
      :open ->
        check_recovery_time(state)
      :half_open ->
        execute_with_monitoring(fun, state)
    end
  end

  defp execute_with_monitoring(fun, state) do
    try do
      result = fun.()
      new_state = reset_failure_count(state)
      {:reply, {:ok, result}, new_state}
    rescue
      error ->
        new_state = record_failure(state)
        {:reply, {:error, error}, new_state}
    end
  end

  defp record_failure(state) do
    new_count = state.failure_count + 1
    new_state = %{state | 
      failure_count: new_count,
      last_failure_time: System.monotonic_time(:millisecond)
    }
    
    if new_count >= state.failure_threshold do
      %{new_state | state: :open}
    else
      new_state
    end
  end

  defp reset_failure_count(state) do
    %{state | failure_count: 0, state: :closed}
  end

  defp check_recovery_time(state) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time - state.last_failure_time > state.recovery_time do
      new_state = %{state | state: :half_open}
      {:reply, {:error, :circuit_open}, new_state}
    else
      {:reply, {:error, :circuit_open}, state}
    end
  end
end
```

**Rate Limiter Implementation (Day 2)**
```elixir
defmodule AutonomousOpponent.Core.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for VSM variety flow control
  """
  use GenServer

  defstruct [
    :name,
    :max_tokens,
    :refill_rate,
    :current_tokens,
    :last_refill
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def check_rate(name, tokens_requested \\ 1) do
    GenServer.call(name, {:check_rate, tokens_requested})
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      name: opts[:name],
      max_tokens: opts[:max_tokens] || 100,
      refill_rate: opts[:refill_rate] || 10, # tokens per second
      current_tokens: opts[:max_tokens] || 100,
      last_refill: System.monotonic_time(:millisecond)
    }
    
    # Schedule token refill
    schedule_refill()
    
    {:ok, state}
  end

  @impl true
  def handle_call({:check_rate, tokens_requested}, _from, state) do
    updated_state = refill_tokens(state)
    
    if updated_state.current_tokens >= tokens_requested do
      new_state = %{updated_state | current_tokens: updated_state.current_tokens - tokens_requested}
      {:reply, :allowed, new_state}
    else
      {:reply, :rate_limited, updated_state}
    end
  end

  @impl true
  def handle_info(:refill_tokens, state) do
    new_state = refill_tokens(state)
    schedule_refill()
    {:noreply, new_state}
  end

  defp refill_tokens(state) do
    current_time = System.monotonic_time(:millisecond)
    time_diff = current_time - state.last_refill
    
    tokens_to_add = (time_diff / 1000) * state.refill_rate
    new_tokens = min(state.max_tokens, state.current_tokens + tokens_to_add)
    
    %{state | 
      current_tokens: new_tokens,
      last_refill: current_time
    }
  end

  defp schedule_refill do
    Process.send_after(self(), :refill_tokens, 100) # 10 Hz refill
  end
end
```

### Day 3-4: Security Hardening

**API Key Rotation and Secrets Management**
```bash
# Rotate all exposed API keys immediately
export OPENAI_API_KEY_NEW=$(generate_new_key.sh)
export ANTHROPIC_API_KEY_NEW=$(generate_new_key.sh)

# Implement Vault integration
mix phx.gen.context Security Secret secrets \
  key:string \
  value:string \
  environment:string \
  expires_at:datetime

# Update all configurations to use secrets management
sed -i 's/sk-[a-zA-Z0-9]*/System.get_env("OPENAI_API_KEY")/g' config/*.exs
```

**Security Configuration**
```elixir
# config/runtime.exs
config :autonomous_opponent, Intelligence.LLM.Client,
  openai_api_key: System.fetch_env!("OPENAI_API_KEY"),
  anthropic_api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
  encryption_key: System.fetch_env!("ENCRYPTION_KEY")

# Add to .env.example (never commit actual keys)
echo "OPENAI_API_KEY=your_key_here" >> .env.example
echo "ANTHROPIC_API_KEY=your_key_here" >> .env.example
```

### Day 5-7: Integration Testing Framework

**VSM Readiness Tests**
```elixir
# test/vsm/integration_test.exs
defmodule VSM.IntegrationTest do
  use ExUnit.Case, async: false
  
  test "V1 components start successfully" do
    # Test Memory Tiering
    assert {:ok, _pid} = AutonomousOpponent.MemoryTiering.TierManager.start_link([])
    
    # Test Workflows  
    assert {:ok, _pid} = AutonomousOpponent.Workflows.Engine.start_link([])
    
    # Test MCP Gateway (after completion)
    assert {:ok, _pid} = AutonomousOpponent.MCP.Gateway.start_link([])
    
    # Test Intelligence Layer
    assert {:ok, _pid} = AutonomousOpponent.Intelligence.LLM.Client.start_link([])
  end
  
  test "components communicate via EventBus" do
    # Publish test event
    :ok = AutonomousOpponentV2.EventBus.publish(:test_event, %{data: "test"})
    
    # Subscribe and verify delivery
    AutonomousOpponentV2.EventBus.subscribe(:test_event, self())
    assert_receive {:event, :test_event, %{data: "test"}}, 1000
  end

  test "variety flows through memory tiers" do
    # Generate test variety
    variety_data = %{
      type: :test_variety,
      content: "test content",
      timestamp: DateTime.utc_now(),
      complexity_score: 0.5
    }
    
    # Should be absorbed by memory system
    {:ok, tier} = AutonomousOpponent.MemoryTiering.TierManager.store("test_key", variety_data)
    
    assert tier in [:hot, :warm, :cold]
  end
end
```

## Week 2: Component Completion (Days 8-14)

### Day 8-10: MCP Gateway Completion

**Missing Transport Implementation**
```elixir
defmodule AutonomousOpponent.MCP.Transport.HTTP do
  @moduledoc """
  HTTP transport for MCP Gateway with SSE support
  """
  
  def start_link(opts) do
    port = opts[:port] || 8080
    Plug.Cowboy.http(__MODULE__, [], port: port)
  end

  def call(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("content-type", "text/event-stream")
    |> send_chunked(200)
    |> handle_mcp_stream()
  end

  defp handle_mcp_stream(conn) do
    # Stream MCP responses as Server-Sent Events
    receive do
      {:mcp_response, data} ->
        {:ok, conn} = chunk(conn, "data: #{Jason.encode!(data)}\n\n")
        handle_mcp_stream(conn)
    after
      30_000 -> conn # 30 second timeout
    end
  end
end
```

### Day 11-14: VSM Event Processor

**Bridge EventBus to VSM Control Loops**
```elixir
defmodule VSM.EventProcessor do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Subscribe to all events for VSM classification
    AutonomousOpponentV2.EventBus.subscribe("*", &handle_event/2)
    {:ok, %{event_count: 0}}
  end
  
  def handle_event(topic, data) do
    GenServer.cast(__MODULE__, {:classify_event, topic, data})
  end
  
  @impl true
  def handle_cast({:classify_event, topic, data}, state) do
    # Route events to appropriate VSM subsystem
    classification = classify_for_vsm(topic, data)
    route_to_vsm_subsystem(classification, data)
    
    {:noreply, %{state | event_count: state.event_count + 1}}
  end
  
  defp classify_for_vsm(topic, data) do
    cond do
      topic =~ ~r/mcp|memory|workflow/ -> {:s1_operations, :variety}
      topic =~ ~r/coordination|routing/ -> {:s2_coordination, :flow}
      topic =~ ~r/resource|performance/ -> {:s3_control, :optimization}
      topic =~ ~r/intelligence|learning/ -> {:s4_intelligence, :scanning}
      topic =~ ~r/policy|governance/ -> {:s5_policy, :identity}
      topic =~ ~r/error|failure/ -> {:algedonic, :pain}
      topic =~ ~r/success|completion/ -> {:algedonic, :pleasure}
      true -> {:s1_operations, :default}
    end
  end
  
  defp route_to_vsm_subsystem({subsystem, type}, data) do
    # For now, log the routing until Phase 1 implements VSM subsystems
    Logger.info("VSM Event: #{subsystem}/#{type} - #{inspect(data)}")
    
    # TODO: Route to actual VSM subsystems in Phase 1
    # VSM.S1.Operations.absorb_variety(data)
    # VSM.S3.Control.handle_optimization(data)
    # etc.
  end
end
```

## Week 3: Testing & Validation (Days 15-21)

### Component Health Monitoring

**VSM Component Readiness Dashboard**
```elixir
defmodule VSM.ComponentHealth do
  @moduledoc """
  Monitor V1 component readiness for VSM integration
  """
  
  def health_check do
    %{
      memory_tiering: check_memory_tiering(),
      workflows: check_workflows(),
      mcp_gateway: check_mcp_gateway(),
      intelligence: check_intelligence(),
      event_bus: check_event_bus(),
      missing_dependencies: check_missing_dependencies()
    }
  end
  
  defp check_memory_tiering do
    try do
      {:ok, _} = AutonomousOpponent.MemoryTiering.TierManager.start_link([])
      %{status: :healthy, readiness: 85}
    rescue
      _ -> %{status: :unhealthy, error: "Failed to start"}
    end
  end
  
  defp check_missing_dependencies do
    required_modules = [
      AutonomousOpponent.Core.CircuitBreaker,
      AutonomousOpponent.Core.RateLimiter,
      AutonomousOpponent.Core.Metrics,
      AutonomousOpponent.Intelligence.VectorStore.HNSWIndex,
      AutonomousOpponent.Intelligence.VectorStore.Quantizer
    ]
    
    missing = Enum.filter(required_modules, fn module ->
      !Code.ensure_loaded?(module)
    end)
    
    if missing == [] do
      %{status: :healthy, missing: []}
    else
      %{status: :unhealthy, missing: missing}
    end
  end
end
```

### Load Testing Setup

**Variety Processing Load Test**
```elixir
defmodule VSM.LoadTest do
  def simulate_variety_load(duration_ms \\ 60_000, rate_per_second \\ 100) do
    variety_generator = fn ->
      %{
        type: Enum.random([:mcp_request, :workflow, :intelligence_query]),
        data: generate_random_data(),
        timestamp: DateTime.utc_now(),
        complexity: :rand.uniform()
      }
    end
    
    start_time = System.monotonic_time(:millisecond)
    
    Stream.interval(div(1000, rate_per_second))
    |> Stream.take_while(fn _ ->
      System.monotonic_time(:millisecond) - start_time < duration_ms
    end)
    |> Stream.map(fn _ -> variety_generator.() end)
    |> Stream.each(&process_variety_item/1)
    |> Stream.run()
  end
  
  defp process_variety_item(item) do
    # Route through EventBus like VSM will do
    AutonomousOpponentV2.EventBus.publish(:load_test_variety, item)
  end
end
```

## Week 4: Documentation & Transition (Days 22-30)

### Phase 0 Completion Report

**Automated Readiness Assessment**
```bash
mix vsm.phase_0_report --output phase_0_completion.md
```

### Phase 1 Preparation

**VSM Subsystem Stubs**
```elixir
defmodule VSM.S1.Operations do
  @moduledoc """
  S1 Operations subsystem - Variety absorption layer
  Integrates with V1 Memory Tiering for natural variety handling
  """
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def absorb_variety(data) do
    GenServer.cast(__MODULE__, {:absorb_variety, data})
  end
  
  @impl true
  def init(_opts) do
    {:ok, %{variety_buffer: [], processing_capacity: 100}}
  end
  
  @impl true
  def handle_cast({:absorb_variety, data}, state) do
    # TODO: Implement actual variety absorption in Phase 1
    # For now, delegate to V1 Memory Tiering
    Logger.info("S1 absorbing variety: #{inspect(data)}")
    {:noreply, state}
  end
end
```

## Success Criteria for Phase 0 Completion

### Technical Criteria (Must Achieve 100%)
- [ ] All missing dependencies implemented and tested
- [ ] Security audit passes (no exposed secrets)
- [ ] V1 components start successfully in integration tests
- [ ] MCP Gateway supports all required transports
- [ ] EventBus routes to VSM Event Processor
- [ ] Load testing shows system handles 100 req/sec for 1 hour

### Readiness Criteria (Must Achieve 80%+)
- [ ] Memory Tiering: 85% readiness (variety absorption ready)
- [ ] Workflows Engine: 85% readiness (control procedures ready)  
- [ ] Intelligence Layer: 75% readiness (environmental scanning ready)
- [ ] MCP Gateway: 80% readiness (variety distribution ready)
- [ ] Event Sourcing: 90% readiness (audit trail ready)

### Knowledge Criteria (Team Understanding)
- [ ] Team understands V1 component capabilities and limitations
- [ ] VSM principles clearly understood and accepted
- [ ] Integration patterns validated through testing
- [ ] Performance characteristics documented
- [ ] Security model implemented and verified

## Next Phase Trigger

Phase 0 → Phase 1 transition occurs when:
1. All technical criteria met (100%)
2. Component readiness averages 80%+
3. Security audit shows zero critical issues
4. Team demonstrates VSM knowledge through design review
5. Integration tests show stable 24-hour operation

**Expected Completion**: 4 months from start
**Go/No-Go Review**: Month 3, Week 4
**Phase 1 Kickoff**: Month 4, Week 1

---

*This plan transforms 22 months of aspiration into 30 days of concrete action. By Week 30, we'll have genuine VSM building blocks rather than architectural dreams.*