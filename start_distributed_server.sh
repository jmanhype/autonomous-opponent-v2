#!/bin/bash

echo "Starting Phoenix server as distributed node..."
echo "This will enable PatternAggregator and cluster-wide statistics"
echo ""
echo "Server will be available at:"
echo "  - HTTP: http://localhost:4000"
echo "  - Node: test@127.0.0.1"
echo ""

# Start the server as a distributed node
elixir --name test@127.0.0.1 -S mix phx.server