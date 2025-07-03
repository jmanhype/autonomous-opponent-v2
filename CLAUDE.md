# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

The Autonomous Opponent is an ambitious AI system with a significant gap between its vision and implementation. The codebase is approximately 20-30% implemented compared to its documented claims. It's built as an Elixir umbrella application with Phoenix LiveView frontend.

**Key Reality Check**: The "consciousness", "VSM", and "million-request handling" are mostly marketing. The actual system is a well-structured Phoenix app with AMQP messaging and many stub implementations.

## Essential Commands

### Development Setup
```bash
# Install dependencies and setup database
mix setup

# Start Phoenix server with IEx
iex -S mix phx.server

# Run with specific environment
MIX_ENV=dev mix phx.server

# Install Claude Code dependency (if needed)
npm install

# Setup assets (Tailwind + esbuild)
mix assets.setup
```

### Testing
```bash
# Run all tests
mix test

# Run specific test file
mix test test/autonomous_opponent_web/controllers/page_controller_test.exs

# Run with coverage
mix test --cover

# Run integration tests only
mix test --only integration:true
```

### Database Operations
```bash
# Create and migrate database
mix ecto.create
mix ecto.migrate

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Run specific migration
mix ecto.migrate --step 1

# Rollback migration
mix ecto.rollback
```

### Code Quality
```bash
# Format code
mix format

# Run linter (Credo)
mix credo --strict

# Run dialyzer for type checking
mix dialyxir

# Security audit
mix deps.audit

# Dependency audit
mix deps.audit

# Run all quality checks together
mix format && mix credo --strict && mix dialyxir
```

### Asset Management
```bash
# Build assets
mix assets.build

# Deploy assets (production)
mix assets.deploy

# Watch assets in development
mix assets.watch

# Clean assets
mix assets.clean

# Validate assets
mix assets.validate
```

### Deployment
```bash
# Build release
MIX_ENV=prod mix release

# Run with Docker
docker-compose up

# Deploy to production
./scripts/deployment/deploy.sh

# Run production console
_build/prod/rel/autonomous_opponent/bin/autonomous_opponent remote
```

## Architecture & Key Patterns

### Umbrella Structure
```
apps/
├── autonomous_opponent_core/    # Business logic, VSM, consciousness (mostly stubs)
└── autonomous_opponent_web/     # Phoenix web interface
```

### Critical Architectural Context

1. **The Facade Pattern Plague**: Most "advanced" modules (`Consciousness`, `SystemGovernor`) are facades that delegate to non-existent implementations. When you see:
   ```elixir
   defdelegate some_function(args), to: SomeInternal.Module
   ```
   The internal module likely doesn't exist or returns hardcoded values.

2. **VSM (Viable System Model)**: Despite extensive documentation, VSM is 95% unimplemented. Only database schemas and supervisors exist - no actual S1-S5 workers or Kalman filters. However, according to recent commits, S1-S5 subsystems and Algedonic system are now implemented (40% of Phase 1).

3. **Event Bus**: One of the few fully functional components. All modules communicate through:
   ```elixir
   EventBus.publish(:event_name, data)
   EventBus.subscribe(:event_name)
   ```

4. **AMQP Integration**: Functional but often disabled. Check `AMQP_ENABLED` env var. Uses 200-connection pool when enabled.

5. **"Wisdom Preservation"**: Comments throughout the code explain architectural decisions. These are aspirational guidance, not implemented patterns.

### Key Modules That Actually Work

- `AutonomousOpponentWeb.Router` - Standard Phoenix routing
- `AutonomousOpponent.EventBus` - Functional pub/sub system
- `AutonomousOpponent.CircuitBreaker` - Basic implementation
- `AutonomousOpponent.RateLimiter` - Token bucket algorithm
- `AutonomousOpponent.AMQP.*` - When enabled, this works
- Phoenix LiveView components - The UI layer is solid

### Modules That Are Mostly Empty

- `AutonomousOpponent.Consciousness` - Returns hardcoded values
- `AutonomousOpponent.SystemGovernor` - TODO comment says it all
- `AutonomousOpponent.VSM.*` - Database schemas only, no logic
- `AutonomousOpponent.ChaosEngine` - Just a GenServer skeleton
- `AutonomousOpponent.Metrics` - Returns fake benchmark data

### The C4 Model Vision

The C4_MODEL.md describes an ambitious architecture:
- Level 1: System Context ✓ (80% implemented)
- Level 2: Containers ⚠️ (60% implemented)
- Level 3: Components ✗ (20% implemented)
- Level 4: Code ✗ (10% implemented)

### Database Schema

Key tables that exist:
- `vsm_systems` - VSM hierarchy (unused)
- `consciousness_states` - State storage (basic usage)
- `mcp_tools` - Tool definitions (partial implementation)
- `events` - Event log (functional)

### Environment Variables

Critical for operation:
```bash
# Database
DATABASE_URL=postgres://user:pass@localhost:5432/autonomous_opponent_dev

# AMQP (often disabled)
AMQP_ENABLED=true
AMQP_URL=amqp://localhost:5672

# Phoenix
SECRET_KEY_BASE=<64-char-key>
PHX_HOST=localhost
PORT=4000

# AI Integration
OPENAI_API_KEY=<your-key>
```

## Common Issues & Solutions

### JSON Encoding Errors
The system often fails encoding Erlang datetime tuples:
```elixir
# Instead of {date, time} tuples, use:
DateTime.utc_now() |> DateTime.to_iso8601()
```

### AMQP Connection Failures
AMQP is often disabled. Check:
1. Is RabbitMQ running?
2. Is `AMQP_ENABLED=true`?
3. Check connection pool health

### Consciousness Returns Empty
This is normal - consciousness is mostly unimplemented. The facade returns:
```elixir
%{
  state: "nascent",
  timestamp: DateTime.utc_now(),
  inner_dialog: []
}
```

### Performance Benchmarks Are Fake
`Metrics.get_performance/0` returns hardcoded values. Don't trust any performance claims in the documentation.

## Development Workflow

1. **Check Implementation Status First**: Before working on a feature, verify if it's actually implemented or just a stub.

2. **Follow the Event Bus**: Most real functionality flows through the EventBus. Trace events to understand actual behavior.

3. **Ignore Marketing Claims**: Documentation claims about "consciousness", "self-awareness", and "million-request handling" are aspirational.

4. **Focus on What Works**: Phoenix web, EventBus, AMQP (when enabled), and basic CRUD operations are solid.

5. **Database Migrations**: Always check migration status - many tables exist but aren't used.

6. **Run Tests Early**: Use `mix test` before making changes to establish baseline. Many tests may fail due to unimplemented features.

7. **Use IEx for Exploration**: `iex -S mix phx.server` gives you a REPL to test modules interactively.

## Testing Approach

```bash
# Unit tests for real implementations
mix test test/autonomous_opponent/event_bus_test.exs

# Integration tests (many test non-existent features)
mix test test/integration/

# Skip consciousness tests (mostly stubs)
mix test --exclude consciousness:true
```

## Deployment Notes

1. **Docker**: Multi-stage Dockerfile is well-configured
2. **Releases**: Use `mix release` for production builds
3. **Health Checks**: `/health` endpoint returns system status
4. **Scaling**: Despite claims, single-instance only (no distributed consensus)

## Archaeological Findings

From V1 to V2 evolution:
- V1: Monolithic Phoenix app with basic functionality
- V2: Ambitious umbrella rewrite, mostly unfinished
- Many modules exist solely to match documentation claims
- Real value in AMQP integration and event-driven patterns

## Critical Files to Understand

1. `lib/autonomous_opponent/application.ex` - Supervision tree (what actually starts)
2. `lib/autonomous_opponent/event_bus.ex` - Core communication mechanism
3. `lib/autonomous_opponent_web/live/chat_live.ex` - Main UI component
4. `C4_MODEL.md` - The ambitious vision (vs reality)
5. `docs/ARCHAEOLOGICAL_VALIDATION_REPORT.md` - Honest assessment of implementation gaps

## Final Wisdom

This codebase is a "beautifully architected skeleton" - excellent structure with minimal implementation. When working here:
- Implement rather than architect more
- Update documentation to reflect reality
- Focus on making claimed features actually work
- Don't add new facades - complete existing ones
- Remember: consciousness here is just a variable name, not AGI

## Important Dependencies

- **Elixir**: ~> 1.16 (required)
- **PostgreSQL**: 16+ recommended (Alpine in Docker)
- **RabbitMQ**: Optional but recommended for AMQP features
- **Node.js**: Required for asset compilation and Claude Code integration

## Useful IEx Commands

```elixir
# Check EventBus subscriptions
AutonomousOpponent.EventBus.list_subscribers()

# Trigger a health check
AutonomousOpponent.HealthCheck.check_all()

# See running processes
:observer.start()

# Check VSM supervisor tree
Supervisor.which_children(AutonomousOpponent.VSM.Supervisor)
```