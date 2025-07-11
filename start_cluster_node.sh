#\!/bin/bash
# Start a distributed Erlang node for testing cluster metrics

NODE_NAME=${1:-node1}
COOKIE=${2:-autonomous_opponent_secret}
PORT_OFFSET=${3:-0}

# Calculate ports
HTTP_PORT=$((4000 + PORT_OFFSET))
EPMD_PORT=$((4369 + PORT_OFFSET))

echo "🚀 Starting distributed node: ${NODE_NAME}@127.0.0.1"
echo "   HTTP Port: ${HTTP_PORT}"
echo "   Cookie: ${COOKIE}"

# Set environment variables
export PORT=${HTTP_PORT}
export MIX_ENV=dev
export RELEASE_NODE="${NODE_NAME}@127.0.0.1"
export RELEASE_COOKIE="${COOKIE}"

# Start the node
iex --name "${NODE_NAME}@127.0.0.1" \
    --cookie "${COOKIE}" \
    --erl "-kernel inet_dist_listen_min 9100 inet_dist_listen_max 9199" \
    -S mix phx.server
