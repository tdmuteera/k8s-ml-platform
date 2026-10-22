#!/usr/bin/env bash
# Check the inference endpoint, and Grafana when observability is enabled.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOFU="${ROOT}/.tools/tofu"
if [[ ! -x "${TOFU}" ]]; then
  TOFU="tofu"
fi

output() {
  "${TOFU}" -chdir="${ROOT}/infra" output -raw "$1"
}

BASE="$(output inference_url)"
KEY="$(output api_key)"
OBS="$(output observability_enabled)"
GRAFANA="$(output grafana_url)"
GPW="$(output grafana_password)"

echo "Inference URL: ${BASE}"
echo "API key: ${KEY}"
if [[ "${OBS}" == "true" ]]; then
  echo "Grafana URL: ${GRAFANA}"
  echo "Grafana user: admin"
  echo "Grafana password: ${GPW}"
fi

cpu_payload='{"gpu_count":0,"cpu_cores":4,"memory_gb":8,"runtime_hours":1,"priority":"normal","framework":"other"}'
gpu_payload='{"gpu_count":2,"cpu_cores":16,"memory_gb":64,"runtime_hours":2,"priority":"high","framework":"pytorch"}'
preempt_payload='{"gpu_count":4,"cpu_cores":8,"memory_gb":32,"runtime_hours":24,"priority":"low","framework":"jax"}'

# The ingress controller answers /healthz itself. /readyz is the application.
echo "Waiting for ${BASE}/readyz"
ready=0
for _ in $(seq 1 60); do
  if curl --fail --silent --show-error "${BASE}/readyz" | grep -q '"status"'; then
    ready=1
    break
  fi
  sleep 5
done
if [[ "${ready}" != "1" ]]; then
  echo "Timed out waiting for the inference service." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

code="$(curl --silent --show-error -o "${tmpdir}/unauth.json" -w '%{http_code}' \
  -X POST "${BASE}/predict" \
  -H 'Content-Type: application/json' \
  -d "${cpu_payload}")"
if [[ "${code}" != "401" ]]; then
  echo "Expected HTTP 401 without an API key, received ${code}." >&2
  cat "${tmpdir}/unauth.json" >&2
  exit 1
fi

predict() {
  local payload="$1"
  local dest="$2"
  curl --fail --silent --show-error -o "${dest}" \
    -X POST "${BASE}/predict" \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: ${KEY}" \
    -d "${payload}"
}

predict "${cpu_payload}" "${tmpdir}/cpu.json"
grep -Eq '"queue"[[:space:]]*:[[:space:]]*"cpu"' "${tmpdir}/cpu.json"

predict "${gpu_payload}" "${tmpdir}/gpu.json"
grep -Eq '"queue"[[:space:]]*:[[:space:]]*"gpu"' "${tmpdir}/gpu.json"

predict "${preempt_payload}" "${tmpdir}/preempt.json"
grep -Eq '"queue"[[:space:]]*:[[:space:]]*"gpu-preemptible"' "${tmpdir}/preempt.json"

curl --fail --silent --show-error "${BASE}/metrics" | grep -q 'inference_requests_total'

if [[ "${OBS}" == "true" ]]; then
  echo "Waiting for Grafana at ${GRAFANA}"
  gok=0
  for _ in $(seq 1 36); do
    code="$(curl --silent --show-error -o /dev/null -w '%{http_code}' "${GRAFANA}/login" || true)"
    if [[ "${code}" == "200" || "${code}" == "302" ]]; then
      gok=1
      break
    fi
    sleep 5
  done
  if [[ "${gok}" != "1" ]]; then
    echo "Timed out waiting for Grafana." >&2
    exit 1
  fi
fi

echo "Smoke test passed."
