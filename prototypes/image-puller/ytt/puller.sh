#!/bin/bash

set -euo pipefail

RUNTIME_ENDPOINT="unix://${1:-/run/k3s/containerd/containerd.sock}"
IMAGE_LIST_FILE="${2:-/config/images.txt}"

# 1. INSTALL CRICTL FROM GITHUB
# ----------------------------------------------------
CRICTL_VERSION="v1.33.0"
ARCH="amd64"
DOWNLOAD_URL="https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz"

echo "Downloading crictl from ${DOWNLOAD_URL}..."
curl -fsSL "$DOWNLOAD_URL" \
  | tar -C /usr/local/bin -xzv

crictl --version

# 2. PULL IMAGES USING CRICTL
# ----------------------------------------------------
echo "Starting image puller for k3s node..."
if [ ! -S "$RUNTIME_ENDPOINT" ]; then
  echo "k3s containerd socket not found at $RUNTIME_ENDPOINT. Is this a k3s node?" >&2
  exit 1
fi

if [ ! -f "$IMAGE_LIST_FILE" ]; then
  echo "Image list file not found at $IMAGE_LIST_FILE. Nothing to pull." >&2
  exit 1
fi

while IFS= read -r image || [ -n "$image" ]; do
  if [ -z "$(echo "$image" | tr -d '[:space:]')" ]; then
    continue
  fi
  echo "Pulling image: $image"
  crictl --timeout 5m --runtime-endpoint "$RUNTIME_ENDPOINT" pull "$image"
done <"$IMAGE_LIST_FILE"

echo "Finished pulling all images. Pod will now sleep to prevent restarts."
sleep infinity
