#!/bin/bash

# Start server with AMQP disabled
export AMQP_ENABLED=false
export MIX_ENV=dev

echo "Starting Phoenix server with AMQP disabled..."
mix phx.server