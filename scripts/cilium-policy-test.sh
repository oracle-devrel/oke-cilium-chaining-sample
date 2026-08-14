#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Proves Kubernetes NetworkPolicy enforcement and Hubble denial visibility.

set -euo pipefail

CONTEXT="${1:?usage: cilium-policy-test.sh <kube-context> [namespace]}"
NS="${2:-cilium-policy-$(date +%s)}"
SERVER_IMAGE="${SERVER_IMAGE:-registry.k8s.io/e2e-test-images/agnhost:2.45}"
CLIENT_IMAGE="${CLIENT_IMAGE:-registry.k8s.io/e2e-test-images/busybox:1.29-4}"
CILIUM_NS="${CILIUM_NS:-${cilium_ns:-kube-system}}"

kube() {
  kubectl --context "$CONTEXT" "$@"
}

echo "===== namespaces ====="
echo "test namespace: ${NS}"
echo "cilium namespace: ${CILIUM_NS}"

NODES=()
while IFS= read -r node; do
  NODES+=("$node")
done < <(kube get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | head -n 2)

if [ "${#NODES[@]}" -lt 2 ]; then
  echo "Need at least two schedulable nodes for policy validation." >&2
  exit 1
fi

kube create namespace "$NS"
kube label namespace "$NS" oke-cilium-sample=true oke-cilium-test=policy

kube -n "$NS" run policy-server \
  --image="$SERVER_IMAGE" \
  --restart=Never \
  --labels="app=policy-server" \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${NODES[1]}\"}}}" \
  --command -- /agnhost netexec --http-port=8080

kube -n "$NS" run allowed-client \
  --image="$CLIENT_IMAGE" \
  --restart=Never \
  --labels="app=policy-client,access=allowed" \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${NODES[0]}\"}}}" \
  --command -- sleep 3600

kube -n "$NS" run blocked-client \
  --image="$CLIENT_IMAGE" \
  --restart=Never \
  --labels="app=policy-client,access=blocked" \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${NODES[0]}\"}}}" \
  --command -- sleep 3600

kube -n "$NS" wait --for=condition=Ready pod/policy-server --timeout=180s
kube -n "$NS" wait --for=condition=Ready pod/allowed-client --timeout=180s
kube -n "$NS" wait --for=condition=Ready pod/blocked-client --timeout=180s

kube -n "$NS" apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-only-approved-client
spec:
  podSelector:
    matchLabels:
      app: policy-server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              access: allowed
      ports:
        - protocol: TCP
          port: 8080
YAML

kube -n "$NS" get pods -o wide

SERVER_IP="$(kube -n "$NS" get pod policy-server -o jsonpath='{.status.podIP}')"

echo "===== wait for NetworkPolicy enforcement ====="
POLICY_READY=false
for _ in $(seq 1 12); do
  ALLOWED_STATUS=0
  BLOCKED_STATUS=0
  kube -n "$NS" exec allowed-client -- \
    wget -qO- -T 5 "http://${SERVER_IP}:8080/" >/dev/null 2>&1 || ALLOWED_STATUS=$?
  kube -n "$NS" exec blocked-client -- \
    wget -qO- -T 5 "http://${SERVER_IP}:8080/" >/dev/null 2>&1 || BLOCKED_STATUS=$?
  if [[ "$ALLOWED_STATUS" == "0" && "$BLOCKED_STATUS" != "0" ]]; then
    POLICY_READY=true
    break
  fi
  sleep 2
done

if [[ "$POLICY_READY" != "true" ]]; then
  echo "ERROR: NetworkPolicy did not converge to the expected allow/deny behavior." >&2
  echo "allowed-client exit status: ${ALLOWED_STATUS}" >&2
  echo "blocked-client exit status: ${BLOCKED_STATUS}" >&2
  exit 1
fi

echo "===== allowed client should succeed ====="
echo "allowed client: PASS"

echo "===== blocked client should fail ====="
if [[ "$BLOCKED_STATUS" == "0" ]]; then
  echo "ERROR: blocked client reached policy-server; NetworkPolicy was not enforced." >&2
  exit 1
fi
echo "blocked client: PASS"

echo "===== cilium policy endpoints ====="
FOUND_POLICY_ENDPOINT=false
for pod in $(kube -n "$CILIUM_NS" get pods -l k8s-app=cilium -o name); do
  echo "---- ${pod} ----"
  if kube -n "$CILIUM_NS" exec "$pod" -- cilium-dbg endpoint list | grep -E 'policy-server|policy-client|allowed-client|blocked-client'; then
    FOUND_POLICY_ENDPOINT=true
  fi
done

if [[ "$FOUND_POLICY_ENDPOINT" != "true" ]]; then
  echo "ERROR: policy-test pods were not found as Cilium endpoints." >&2
  exit 1
fi

SERVER_NODE="$(kube -n "$NS" get pod policy-server -o jsonpath='{.spec.nodeName}')"
CILIUM_SERVER_POD="$(kube -n "$CILIUM_NS" get pods \
  -l k8s-app=cilium \
  --field-selector="spec.nodeName=${SERVER_NODE}" \
  -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "$CILIUM_SERVER_POD" ]]; then
  echo "ERROR: no Cilium agent pod found on policy-server node ${SERVER_NODE}." >&2
  exit 1
fi

echo "===== Hubble denied flows for blocked client ====="
HUBBLE_DROP_OUTPUT=""
for _ in $(seq 1 10); do
  HUBBLE_DROP_OUTPUT="$(kube -n "$CILIUM_NS" exec "$CILIUM_SERVER_POD" -- \
    hubble observe --since 5m --pod "${NS}/blocked-client" \
    --verdict DROPPED --last 20 2>&1 || true)"
  grep -Eq 'DROPPED|DENIED' <<<"$HUBBLE_DROP_OUTPUT" && break
  sleep 2
done
printf '%s\n' "$HUBBLE_DROP_OUTPUT"

if ! grep -Eq 'DROPPED|DENIED' <<<"$HUBBLE_DROP_OUTPUT"; then
  echo "ERROR: Hubble did not report the blocked-client policy denial." >&2
  exit 1
fi
echo "HUBBLE POLICY DENIAL RESULT: PASS"

echo "Namespace kept for inspection: ${NS}"
echo "CILIUM POLICY TEST RESULT: PASS"
