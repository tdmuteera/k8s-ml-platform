#!/usr/bin/env bash
# Switch kube-proxy to nftables after kind creates the node.
# The iptables mode needs the statistic extension, which some kernels omit.
set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG is required}"

kubectl --kubeconfig "${KUBECONFIG}" -n kube-system get configmap kube-proxy -o yaml \
  | sed 's/mode: iptables/mode: nftables/' \
  | kubectl --kubeconfig "${KUBECONFIG}" apply -f -
kubectl --kubeconfig "${KUBECONFIG}" -n kube-system rollout restart daemonset/kube-proxy
kubectl --kubeconfig "${KUBECONFIG}" -n kube-system rollout status daemonset/kube-proxy --timeout=180s
