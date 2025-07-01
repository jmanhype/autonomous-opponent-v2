#!/bin/bash
set -e

# Script to build Docker image with proper tagging

# Set default values
IMAGE_NAME="${IMAGE_NAME:-autonomous-opponent}"
VERSION="${VERSION:-latest}"
REGISTRY="${REGISTRY:-}"

# Build the Docker image
echo "Building Docker image..."
docker build -t ${IMAGE_NAME}:${VERSION} .

# Tag as latest if not already
if [ "${VERSION}" != "latest" ]; then
    docker tag ${IMAGE_NAME}:${VERSION} ${IMAGE_NAME}:latest
fi

# If registry is specified, tag for registry
if [ -n "${REGISTRY}" ]; then
    docker tag ${IMAGE_NAME}:${VERSION} ${REGISTRY}/${IMAGE_NAME}:${VERSION}
    if [ "${VERSION}" != "latest" ]; then
        docker tag ${IMAGE_NAME}:${VERSION} ${REGISTRY}/${IMAGE_NAME}:latest
    fi
fi

echo "Docker image built successfully:"
echo "  - ${IMAGE_NAME}:${VERSION}"
if [ "${VERSION}" != "latest" ]; then
    echo "  - ${IMAGE_NAME}:latest"
fi
if [ -n "${REGISTRY}" ]; then
    echo "  - ${REGISTRY}/${IMAGE_NAME}:${VERSION}"
    if [ "${VERSION}" != "latest" ]; then
        echo "  - ${REGISTRY}/${IMAGE_NAME}:latest"
    fi
fi