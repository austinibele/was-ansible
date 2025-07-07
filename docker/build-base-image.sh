#!/usr/bin/env bash
# build-base-image.sh - Build custom base image with pre-installed Ansible dependencies
set -euo pipefail

IMAGE_NAME=${IMAGE_NAME:-"was-ansible-base"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

echo "[+] Building custom base image: ${FULL_IMAGE_NAME}"
docker build -f docker/Dockerfile.base -t "${FULL_IMAGE_NAME}" .

echo "[+] Image built successfully: ${FULL_IMAGE_NAME}"
echo "[+] Image size:"
docker images "${FULL_IMAGE_NAME}"

echo ""
echo "Usage examples:"
echo "  # Use in test scripts:"
echo "  IMAGE=${FULL_IMAGE_NAME} ./tests/start_server.sh"
echo ""
echo "  # Push to registry (optional):"
echo "  docker tag ${FULL_IMAGE_NAME} your-registry.com/${IMAGE_NAME}:${IMAGE_TAG}"
echo "  docker push your-registry.com/${IMAGE_NAME}:${IMAGE_TAG}" 