# Multi-stage Dockerfile for Elixir umbrella application
# Stage 1: Build dependencies and compile
FROM elixir:1.16-alpine AS build

# Install build dependencies
RUN apk add --no-cache build-base git python3 curl bash openssl-dev

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Create app directory
WORKDIR /app

# Install mix dependencies
COPY mix.exs mix.lock ./
COPY apps/autonomous_opponent_core/mix.exs ./apps/autonomous_opponent_core/
COPY apps/autonomous_opponent_web/mix.exs ./apps/autonomous_opponent_web/
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy compile-time config
COPY config config/
COPY apps/autonomous_opponent_core/config ./apps/autonomous_opponent_core/config
COPY apps/autonomous_opponent_web/config ./apps/autonomous_opponent_web/config

# Copy application source code
COPY apps apps/
COPY priv priv/

# Compile the project
RUN mix compile

# Build assets (if using esbuild/tailwind)
# Check if assets directory exists before building
RUN if [ -d "apps/autonomous_opponent_web/assets" ]; then \
      cd apps/autonomous_opponent_web && \
      mix assets.setup && \
      mix assets.deploy; \
    fi

# Generate release
COPY rel rel/
RUN mix release autonomous_opponent

# Stage 2: Create the runtime image
FROM alpine:3.19 AS runtime

# Install runtime dependencies
RUN apk add --no-cache openssl ncurses-libs libgcc libstdc++ bash

# Create non-root user for security
RUN adduser -D -h /app app

# Set runtime ENV
ENV MIX_ENV=prod
ENV PHX_SERVER=true

# Copy release from build stage
WORKDIR /app
COPY --from=build --chown=app:app /app/_build/prod/rel/autonomous_opponent ./

# Copy runtime scripts from release (they are already in the release)

# Switch to non-root user
USER app

# Expose Phoenix port
EXPOSE 4000

# Set up health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD /app/bin/autonomous_opponent eval "AutonomousOpponentV2Web.HealthCheck.check()" || exit 1

# Start the Phoenix server
CMD ["./bin/autonomous_opponent", "start"]