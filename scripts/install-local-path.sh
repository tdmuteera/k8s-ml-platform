#!/usr/bin/env bash
# Install the vendored local-path provisioner and wait until it is ready.
set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${MANIFEST:?MANIFEST is required}"

kubectl --kubeconfig "${KUBECONFIG}" apply -f "${MANIFEST}"
kubectl --kubeconfig "${KUBECONFIG}" rollout status deployment/local-path-provisioner \
  --namespace local-path-storage \
  --timeout=180s
kubectl --kubeconfig "${KUBECONFIG}" get storageclass local-path
