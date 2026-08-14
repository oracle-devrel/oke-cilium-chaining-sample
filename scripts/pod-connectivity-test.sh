#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Proves baseline cross-node connectivity before Cilium is installed.

set -euo pipefail

CONTEXT="${1:?usage: pod-connectivity-test.sh <kube-context> [namespace]}"
NS="${2:-pod-connectivity-$(date +%s)}"
SERVER_IMAGE="${SERVER_IMAGE:-registry.k8s.io/e2e-test-images/agnhost:2.45}"
CLIENT_IMAGE="${CLIENT_IMAGE:-registry.k8s.io/e2e-test-images/busybox:1.29-4}"

kube() {
  kubectl --context "$CONTEXT" "$@"
}

NODES=()
while IFS= read -r node; do
  NODES+=("$node")
done < <(kube get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | head -n 2)

if [ "${#NODES[@]}" -lt 2 ]; then
  echo "Need at least two schedulable nodes for cross-node pod validation." >&2
  exit 1
fi

dump_diagnostics() {
  echo
  echo "===== diagnostics for namespace ${NS} ====="
  kube -n "$NS" get pods -o wide || true
  echo
  echo "===== pod descriptions ====="
  kube -n "$NS" describe pod pod-test-client pod-test-server || true
  echo
  echo "===== namespace events ====="
  kube -n "$NS" get events --sort-by='.lastTimestamp' || true
}

kube create namespace "$NS"
kube label namespace "$NS" oke-cilium-sample=true oke-cilium-test=pod-connectivity

kube -n "$NS" run pod-test-server \
  --image="$SERVER_IMAGE" \
  --restart=Never \
  --labels="app=pod-connectivity-test,role=server" \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${NODES[1]}\"}}}" \
  --command -- /agnhost netexec --http-port=8080

kube -n "$NS" run pod-test-client \
  --image="$CLIENT_IMAGE" \
  --restart=Never \
  --labels="app=pod-connectivity-test,role=client" \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${NODES[0]}\"}}}" \
  --command -- sleep 3600

if ! kube -n "$NS" wait --for=condition=Ready pod/pod-test-client --timeout=180s; then
  dump_diagnostics
  exit 1
fi

if ! kube -n "$NS" wait --for=condition=Ready pod/pod-test-server --timeout=180s; then
  dump_diagnostics
  exit 1
fi

kube -n "$NS" get pods -o wide

SERVER_IP="$(kube -n "$NS" get pod pod-test-server -o jsonpath='{.status.podIP}')"
echo "===== cross-node pod HTTP test ====="
kube -n "$NS" exec pod-test-client -- wget -qO- -T 5 "http://${SERVER_IP}:8080/" >/dev/null

echo "Namespace kept for inspection: ${NS}"
echo "POD CONNECTIVITY TEST RESULT: PASS"
