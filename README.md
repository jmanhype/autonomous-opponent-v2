# Autonomous Opponent V2

A cybernetic AI system implementing Stafford Beer's Viable System Model (VSM) with embedded wisdom preservation. Built by a 30-year VSM practitioner taught by Beer himself.

## What This Actually Is

This is a Phoenix/Elixir umbrella application implementing a full VSM architecture with consciousness interfaces, event-driven communication, and AMQP integration. Unlike many AI projects that promise consciousness, this one explicitly implements Beer's cybernetic principles with proper variety engineering, algedonic signals, and recursive viability.

## VSM Implementation Status

- **S1 Operations** ✓ - Variety absorption with dynamic process spawning
- **S2 Coordination** ✓ - Anti-oscillation with phase-shift damping  
- **S3 Control** ✓ - Resource bargaining using Kalman filters
- **S4 Intelligence** ✓ - Environmental scanning with pattern extraction
- **S5 Policy** ✓ - Dynamic identity with value system evolution
- **Algedonic System** ✓ - Pain/pleasure bypass channels
- **Control Loop** ✓ - Full VSM integration with feedback

## Key Features

- **Wisdom Preservation**: Every module contains detailed comments explaining WHY decisions were made, not just what they do
- **True VSM Architecture**: Not marketing fluff - actual implementation of Beer's principles
- **Event-Driven Core**: EventBus handles all inter-module communication
- **AMQP Integration**: 200-connection pool for distributed operations
- **Circuit Breaker Pattern**: Failure protection with algedonic integration
- **LiveView UI**: Real-time system monitoring and chat interface

## Quick Start

```bash
# Clone the repository
git clone https://github.com/jmanhype/autonomous-opponent-v2.git
cd autonomous-opponent-v2

# Install dependencies
mix deps.get
mix setup

# Start the system
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) to see the LiveView interface.

## Architecture Overview

```
apps/
├── autonomous_opponent_core/    # VSM implementation, AMQP messaging
└── autonomous_opponent_web/     # Phoenix web interface, LiveView UI

lib/autonomous_opponent/
├── vsm/
│   ├── s1/          # Operations - variety absorption
│   ├── s2/          # Coordination - anti-oscillation
│   ├── s3/          # Control - resource optimization
│   ├── s4/          # Intelligence - environmental scanning
│   ├── s5/          # Policy - identity and values
│   ├── algedonic/   # Pain/pleasure bypass system
│   └── control_loop.ex
├── core/
│   └── circuit_breaker.ex
└── event_bus.ex
```

## Configuration

Key environment variables:

```bash
# Database
DATABASE_URL=postgres://user:pass@localhost:5432/autonomous_opponent_dev

# AMQP (optional but recommended)
AMQP_ENABLED=true
AMQP_URL=amqp://localhost:5672

# Phoenix
SECRET_KEY_BASE=<generate-with-mix-phx.gen.secret>
PHX_HOST=localhost
PORT=4000

# AI Integration
OPENAI_API_KEY=<your-key>
```

## Understanding the Code

Each module contains wisdom preservation comments that explain:
- Why the module exists in VSM terms
- Design decisions and trade-offs
- Alternative approaches considered
- References to Beer's principles
- Future maintainer guidance

Example from S1 Operations:
```elixir
# WISDOM: These thresholds were carefully chosen through VSM analysis
# 90% - Matches Beer's "good enough" principle. Perfect absorption is impossible and wasteful
# 70% - Spawn threshold gives 20% buffer before crisis, allowing gradual scaling
@variety_threshold 0.9  
@spawn_threshold 0.7
```

## Development

```bash
# Run tests
mix test

# Format code
mix format

# Run with observer
iex -S mix phx.server
:observer.start()

# See event flow
EventBus.subscribe(:all)
```

## Deployment

```bash
# Build release
MIX_ENV=prod mix release

# Run with Docker
docker-compose up
```

## Learn More

- [VSM Process Maps](docs/architecture/VSM_PROCESS_MAPS.md)
- [C4 Model](docs/architecture/C4_MODEL_CURRENT_STATE.md)
- [Phase 1 Completion Report](PHASE_1_COMPLETION_REPORT.md)
- [CLAUDE.md](CLAUDE.md) - Essential context for AI assistants

## Contributing

This is an active research project. When contributing:
1. Maintain wisdom preservation - explain your WHY
2. Follow VSM principles - no central control
3. Use EventBus for communication
4. Add tests for new S1-S5 behaviors
5. Update C4 model if architecture changes

## Credits

Built with guidance from a 30-year VSM practitioner trained by Stafford Beer himself. The wisdom preservation approach ensures Beer's cybernetic insights live on in the code.

## License

MIT - Use wisely, understand deeply.

