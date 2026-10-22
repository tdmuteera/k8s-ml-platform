#!/usr/bin/env bash
# Download pinned local tools into .tools. A clean machine only needs Docker,
# Bash, curl, and tar. unzip or python3 is used when a release is a zip file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="${ROOT}/.tools"
mkdir -p "${TOOLS}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) ARCH="amd64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac
case "${OS}" in
  linux | darwin) ;;
  *)
    echo "Unsupported operating system: ${OS}" >&2
    exit 1
    ;;
esac

TOFU_VERSION="1.13.2"
KIND_VERSION="0.33.0"
KUBECTL_VERSION="1.35.8"
HELM_VERSION="4.3.1"
TFLINT_VERSION="0.64.0"
KUBECONFORM_VERSION="0.8.0"
CRANE_VERSION="0.20.6"

WANT="tofu=${TOFU_VERSION} kind=${KIND_VERSION} kubectl=${KUBECTL_VERSION} helm=${HELM_VERSION} tflint=${TFLINT_VERSION} kubeconform=${KUBECONFORM_VERSION} crane=${CRANE_VERSION}"
STAMP="${TOOLS}/versions"
if [[ -f "${STAMP}" && "$(cat "${STAMP}")" == "${WANT}" && -x "${TOOLS}/tofu" && -x "${TOOLS}/kind" && -x "${TOOLS}/kubectl" && -x "${TOOLS}/helm" && -x "${TOOLS}/tflint" && -x "${TOOLS}/kubeconform" && -x "${TOOLS}/crane" ]]; then
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to download tools." >&2
  exit 1
fi

sha256_check() {
  local file="$1"
  local expected="$2"
  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${file}" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
  fi
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Checksum mismatch for ${file}." >&2
    echo "Expected ${expected}." >&2
    echo "Received ${actual}." >&2
    exit 1
  fi
}

fetch() {
  local url="$1"
  local dest="$2"
  curl --fail --silent --show-error --location --retry 5 --retry-delay 2 -o "${dest}" "${url}"
}

extract_zip() {
  local zip="$1"
  local dest="$2"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "${zip}" -d "${dest}"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m zipfile -e "${zip}" "${dest}"
  else
    echo "Install unzip or python3 to extract ${zip}." >&2
    exit 1
  fi
}

sum_for() {
  local sumfile="$1"
  local name="$2"
  awk -v name="${name}" '$2 == name || $2 == "*" name {print $1; exit}' "${sumfile}"
}

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

echo "Downloading OpenTofu ${TOFU_VERSION}"
tofu_archive="tofu_${TOFU_VERSION}_${OS}_${ARCH}.tar.gz"
fetch "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/${tofu_archive}" "${workdir}/${tofu_archive}"
fetch "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" "${workdir}/tofu.sums"
sha256_check "${workdir}/${tofu_archive}" "$(sum_for "${workdir}/tofu.sums" "${tofu_archive}")"
tar -xzf "${workdir}/${tofu_archive}" -C "${workdir}"
install -m 0755 "${workdir}/tofu" "${TOOLS}/tofu"

echo "Downloading kind ${KIND_VERSION}"
kind_name="kind-${OS}-${ARCH}"
fetch "https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/${kind_name}" "${workdir}/${kind_name}"
fetch "https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/${kind_name}.sha256sum" "${workdir}/kind.sha256"
sha256_check "${workdir}/${kind_name}" "$(awk '{print $1}' "${workdir}/kind.sha256")"
install -m 0755 "${workdir}/${kind_name}" "${TOOLS}/kind"

echo "Downloading kubectl ${KUBECTL_VERSION}"
fetch "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl" "${workdir}/kubectl"
fetch "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl.sha256" "${workdir}/kubectl.sha256"
sha256_check "${workdir}/kubectl" "$(awk '{print $1}' "${workdir}/kubectl.sha256")"
install -m 0755 "${workdir}/kubectl" "${TOOLS}/kubectl"

echo "Downloading Helm ${HELM_VERSION}"
helm_archive="helm-v${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
fetch "https://get.helm.sh/${helm_archive}" "${workdir}/${helm_archive}"
fetch "https://get.helm.sh/${helm_archive}.sha256sum" "${workdir}/helm.sha256"
sha256_check "${workdir}/${helm_archive}" "$(awk '{print $1}' "${workdir}/helm.sha256")"
tar -xzf "${workdir}/${helm_archive}" -C "${workdir}"
install -m 0755 "${workdir}/${OS}-${ARCH}/helm" "${TOOLS}/helm"

echo "Downloading TFLint ${TFLINT_VERSION}"
tflint_archive="tflint_${OS}_${ARCH}.zip"
fetch "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/${tflint_archive}" "${workdir}/${tflint_archive}"
fetch "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/checksums.txt" "${workdir}/tflint.sums"
sha256_check "${workdir}/${tflint_archive}" "$(sum_for "${workdir}/tflint.sums" "${tflint_archive}")"
extract_zip "${workdir}/${tflint_archive}" "${workdir}/tflint"
install -m 0755 "${workdir}/tflint/tflint" "${TOOLS}/tflint"

echo "Downloading kubeconform ${KUBECONFORM_VERSION}"
kubeconform_archive="kubeconform-${OS}-${ARCH}.tar.gz"
fetch "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/${kubeconform_archive}" "${workdir}/${kubeconform_archive}"
fetch "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/CHECKSUMS" "${workdir}/kubeconform.sums"
sha256_check "${workdir}/${kubeconform_archive}" "$(sum_for "${workdir}/kubeconform.sums" "${kubeconform_archive}")"
tar -xzf "${workdir}/${kubeconform_archive}" -C "${workdir}"
install -m 0755 "${workdir}/kubeconform" "${TOOLS}/kubeconform"

echo "Downloading crane ${CRANE_VERSION}"
if [[ "${OS}" == "darwin" ]]; then
  crane_os="Darwin"
elif [[ "${OS}" == "linux" ]]; then
  crane_os="Linux"
fi
if [[ "${ARCH}" == "amd64" ]]; then
  crane_arch="x86_64"
else
  crane_arch="arm64"
fi
crane_archive="go-containerregistry_${crane_os}_${crane_arch}.tar.gz"
fetch "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/${crane_archive}" "${workdir}/${crane_archive}"
fetch "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/checksums.txt" "${workdir}/crane.sums"
sha256_check "${workdir}/${crane_archive}" "$(sum_for "${workdir}/crane.sums" "${crane_archive}")"
tar -xzf "${workdir}/${crane_archive}" -C "${workdir}" crane
install -m 0755 "${workdir}/crane" "${TOOLS}/crane"

printf '%s\n' "${WANT}" > "${STAMP}"
echo "Tools installed in ${TOOLS}"
