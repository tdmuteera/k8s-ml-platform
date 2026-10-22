#!/usr/bin/env bash
# Pull platform images on the host and import a single platform copy into kind.
# The kind node does not need registry access. A multi-arch index is not always
# runnable after a plain docker save, so crane writes a linux/amd64 manifest.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-k8s-ml-platform}"
CRANE_BIN="${CRANE_BIN:-crane}"
IMAGES_FILE="${IMAGES_FILE:-${ROOT}/infra/images.txt}"
NODE="${CLUSTER_NAME}-control-plane"

if [[ ! -f "${IMAGES_FILE}" ]]; then
  echo "Image list not found: ${IMAGES_FILE}" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not available. Start Docker and run make up again." >&2
  exit 1
fi

if ! docker inspect "${NODE}" >/dev/null 2>&1; then
  echo "Kind node ${NODE} is not running." >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

while IFS= read -r image || [[ -n "${image}" ]]; do
  image="${image%%#*}"
  image="$(echo "${image}" | awk '{$1=$1; print}')"
  if [[ -z "${image}" ]]; then
    continue
  fi
  echo "Importing ${image}"
  archive="${workdir}/image.tar"
  "${CRANE_BIN}" pull --platform linux/amd64 "${image}" "${archive}"
  docker exec -i "${NODE}" ctr --namespace=k8s.io images import - < "${archive}"
  rm -f "${archive}"
done < "${IMAGES_FILE}"

echo "Platform images are present on ${NODE}"
