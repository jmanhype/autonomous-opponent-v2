#!/bin/bash
set -e

# Script to run Docker container with proper configuration

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Set default values
IMAGE_NAME="${IMAGE_NAME:-autonomous-opponent}"
VERSION="${VERSION:-latest}"
CONTAINER_NAME="${CONTAINER_NAME:-autonomous-opponent}"
PORT="${PORT:-4000}"

# Required environment variables
if [ -z "${DATABASE_URL}" ]; then
    echo "ERROR: DATABASE_URL environment variable is required"
    exit 1
fi

if [ -z "${SECRET_KEY_BASE}" ]; then
    echo "ERROR: SECRET_KEY_BASE environment variable is required"
    echo "Generate one with: mix phx.gen.secret"
    exit 1
fi

# Stop existing container if running
if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    echo "Stopping existing container..."
    docker stop ${CONTAINER_NAME}
fi

# Remove existing container if exists
if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
    echo "Removing existing container..."
    docker rm ${CONTAINER_NAME}
fi

# Run the container
echo "Starting container..."
docker run -d \
    --name ${CONTAINER_NAME} \
    -p ${PORT}:4000 \
    -e DATABASE_URL="${DATABASE_URL}" \
    -e AUTONOMOUS_OPPONENT_CORE_DATABASE_URL="${AUTONOMOUS_OPPONENT_CORE_DATABASE_URL:-$DATABASE_URL}" \
    -e AUTONOMOUS_OPPONENT_V2_DATABASE_URL="${AUTONOMOUS_OPPONENT_V2_DATABASE_URL:-$DATABASE_URL}" \
    -e SECRET_KEY_BASE="${SECRET_KEY_BASE}" \
    -e PHX_HOST="${PHX_HOST:-localhost}" \
    -e PORT="4000" \
    -e PHX_SERVER="true" \
    -e POOL_SIZE="${POOL_SIZE:-10}" \
    -e AMQP_ENABLED="${AMQP_ENABLED:-false}" \
    -e AMQP_URL="${AMQP_URL:-}" \
    --restart unless-stopped \
    ${IMAGE_NAME}:${VERSION}

echo "Container started successfully!"
echo "Application available at: http://localhost:${PORT}"
echo ""
echo "View logs with: docker logs -f ${CONTAINER_NAME}"
echo "Stop with: docker stop ${CONTAINER_NAME}"