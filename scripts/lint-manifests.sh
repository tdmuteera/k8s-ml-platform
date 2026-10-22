#!/usr/bin/env bash
# Lint the inference chart and check rendered manifests against Kubernetes schemas.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="${ROOT}/.tools:${PATH}"

helm lint "${ROOT}/charts/inference" --set apiKey=lint-only

rendered="$(mktemp --suffix=.yaml)"
trap 'rm -f "${rendered}"' EXIT
helm template inference "${ROOT}/charts/inference" \
  --namespace ml-inference \
  --set apiKey=lint-only \
  --set serviceMonitor.enabled=true \
  > "${rendered}"

kubeconform \
  -strict \
  -summary \
  -kubernetes-version 1.35.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "${rendered}"
