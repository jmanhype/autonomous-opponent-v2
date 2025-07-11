#!/bin/bash

# Kill any existing server
pkill -f "mix phx.server" || true

# Export database URLs
export AUTONOMOUS_OPPONENT_CORE_DATABASE_URL="postgres://postgres:postgres@localhost/autonomous_opponent_v2_core_dev"
export AUTONOMOUS_OPPONENT_V2_DATABASE_URL="postgres://postgres:postgres@localhost/autonomous_opponent_v2_web_dev"

# Disable AMQP if RabbitMQ is not running
export AMQP_ENABLED=false

# Start server with node name for distributed features
echo "Starting Autonomous Opponent with Metrics Cluster..."
echo "Access endpoints:"
echo "  - http://localhost:4000/metrics"
echo "  - http://localhost:4000/metrics/cluster"
echo "  - http://localhost:4000/metrics/vsm_health"
echo ""

elixir --name ao@localhost -S mix phx.server