#!/usr/bin/env bash
# Build the inference image and load it into the kind node.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-k8s-ml-inference:local}"
CLUSTER_NAME="${CLUSTER_NAME:-k8s-ml-platform}"
KIND_BIN="${KIND_BIN:-kind}"

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not available. Start Docker and run make up again." >&2
  exit 1
fi

echo "Building ${IMAGE}"
docker build --tag "${IMAGE}" "${ROOT}/app"

NODE="${CLUSTER_NAME}-control-plane"
echo "Loading ${IMAGE} into ${NODE}"

load_with_kind() {
  if [[ -x "${KIND_BIN}" ]]; then
    "${KIND_BIN}" load docker-image "${IMAGE}" --name "${CLUSTER_NAME}"
    return
  fi
  if command -v "${KIND_BIN}" >/dev/null 2>&1; then
    "${KIND_BIN}" load docker-image "${IMAGE}" --name "${CLUSTER_NAME}"
    return
  fi
  return 1
}

if load_with_kind; then
  exit 0
fi

echo "kind load did not succeed. Importing the image with containerd." >&2
docker save "${IMAGE}" | docker exec -i "${NODE}" ctr --namespace=k8s.io images import -
