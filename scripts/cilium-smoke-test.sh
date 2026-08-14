#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Proves chained endpoint, Service, DNS, and Hubble forwarding behavior.

set -euo pipefail

CONTEXT="${1:?usage: cilium-smoke-test.sh <kube-context> [namespace]}"
NS="${2:-cilium-smoke-$(date +%s)}"
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
  echo "Need at least two schedulable nodes for cross-node validation." >&2
  exit 1
fi

kube create namespace "$NS"
kube label namespace "$NS" oke-cilium-sample=true oke-cilium-test=smoke

kube -n "$NS" run cilium-smoke-server \
  --image="$SERVER_IMAGE" \
  --restart=Never \
  --labels="app=cilium-smoke-test,role=server" \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${NODES[1]}\"}}}" \
  --command -- /agnhost netexec --http-port=8080

kube -n "$NS" run cilium-smoke-client \
  --image="$CLIENT_IMAGE" \
  --restart=Never \
  --labels="app=cilium-smoke-test,role=client" \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${NODES[0]}\"}}}" \
  --command -- sleep 3600

kube -n "$NS" apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: cilium-smoke-service
spec:
  selector:
    app: cilium-smoke-test
    role: server
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 8080
YAML

kube -n "$NS" wait --for=condition=Ready pod/cilium-smoke-client --timeout=180s
kube -n "$NS" wait --for=condition=Ready pod/cilium-smoke-server --timeout=180s

kube -n "$NS" get pods -o wide
kube -n "$NS" get service cilium-smoke-service -o wide

SERVICE_ENDPOINT=""
for _ in $(seq 1 60); do
  SERVICE_ENDPOINT="$(kube -n "$NS" get endpoints cilium-smoke-service \
    -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)"
  [[ -n "$SERVICE_ENDPOINT" ]] && break
  sleep 2
done

if [[ -z "$SERVICE_ENDPOINT" ]]; then
  echo "ERROR: cilium-smoke-service did not receive a ready backend within 120 seconds." >&2
  kube -n "$NS" get service,endpoints,endpointslice -o wide >&2 || true
  exit 1
fi

kube -n "$NS" get endpointslice \
  -l kubernetes.io/service-name=cilium-smoke-service -o wide

http_get() {
  local label="$1"
  local url="$2"
  local output
  local status=0

  echo "===== ${label} ====="
  output="$(kube -n "$NS" exec cilium-smoke-client -- \
    wget -qO- -T 5 "$url" 2>&1)" || status=$?
  printf '%s\n' "$output"
  if [[ "$status" != "0" ]]; then
    echo "ERROR: ${label} failed with exit status ${status}: ${url}" >&2
    exit "$status"
  fi
}

B_IP="$(kube -n "$NS" get pod cilium-smoke-server -o jsonpath='{.status.podIP}')"
SERVICE_IP="$(kube -n "$NS" get service cilium-smoke-service \
  -o jsonpath='{.spec.clusterIP}')"
SERVICE_DNS="cilium-smoke-service.${NS}.svc.cluster.local"

http_get "cross-node pod-IP HTTP test" "http://${B_IP}:8080/"
echo "CROSS-NODE POD-IP CONNECTIVITY RESULT: PASS"

http_get "cross-node ClusterIP service test" "http://${SERVICE_IP}:80/"
echo "CLUSTERIP SERVICE CONNECTIVITY RESULT: PASS"

http_get "cross-node service DNS test" "http://${SERVICE_DNS}:80/"
echo "SERVICE DNS CONNECTIVITY RESULT: PASS"

echo "===== cilium status ====="
kube -n "$CILIUM_NS" exec ds/cilium -- cilium-dbg status --verbose || \
kube -n "$CILIUM_NS" exec ds/cilium -- cilium status --verbose

echo "===== cilium endpoints for smoke pods ====="
FOUND_ENDPOINT=false
for pod in $(kube -n "$CILIUM_NS" get pods -l k8s-app=cilium -o name); do
  echo "---- ${pod} ----"
  if kube -n "$CILIUM_NS" exec "$pod" -- cilium-dbg endpoint list | grep -E 'cilium-smoke-test|cilium-smoke'; then
    FOUND_ENDPOINT=true
  fi
done

if [[ "$FOUND_ENDPOINT" != "true" ]]; then
  echo "ERROR: smoke-test pods were not found as Cilium endpoints." >&2
  exit 1
fi

echo "===== Cilium service table for ${SERVICE_IP}:80 ====="
FOUND_SERVICE=false
for pod in $(kube -n "$CILIUM_NS" get pods -l k8s-app=cilium -o name); do
  echo "---- ${pod} ----"
  SERVICE_OUTPUT="$(kube -n "$CILIUM_NS" exec "$pod" -- \
    cilium-dbg service list 2>&1)"
  printf '%s\n' "$SERVICE_OUTPUT"
  if grep -Fq "${SERVICE_IP}:80" <<<"$SERVICE_OUTPUT"; then
    FOUND_SERVICE=true
  fi
done

if [[ "$FOUND_SERVICE" != "true" ]]; then
  echo "ERROR: ClusterIP ${SERVICE_IP}:80 was not found in any Cilium service table." >&2
  exit 1
fi
echo "CILIUM SERVICE TABLE RESULT: PASS"

CLIENT_NODE="$(kube -n "$NS" get pod cilium-smoke-client \
  -o jsonpath='{.spec.nodeName}')"
CILIUM_CLIENT_POD="$(kube -n "$CILIUM_NS" get pods \
  -l k8s-app=cilium \
  --field-selector="spec.nodeName=${CLIENT_NODE}" \
  -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "$CILIUM_CLIENT_POD" ]]; then
  echo "ERROR: no Cilium agent pod found on client node ${CLIENT_NODE}." >&2
  exit 1
fi

echo "===== Hubble health on client node ${CLIENT_NODE} ====="
kube -n "$CILIUM_NS" exec "$CILIUM_CLIENT_POD" -- hubble status

echo "===== Hubble forwarded flows for smoke client ====="
HUBBLE_OUTPUT=""
for _ in $(seq 1 10); do
  HUBBLE_OUTPUT="$(kube -n "$CILIUM_NS" exec "$CILIUM_CLIENT_POD" -- \
    hubble observe --since 5m --pod "${NS}/cilium-smoke-client" --last 20 2>&1 || true)"
  grep -q 'FORWARDED' <<<"$HUBBLE_OUTPUT" && break
  sleep 2
done
printf '%s\n' "$HUBBLE_OUTPUT"

if ! grep -q 'FORWARDED' <<<"$HUBBLE_OUTPUT"; then
  echo "ERROR: Hubble did not report a forwarded flow for cilium-smoke-client." >&2
  exit 1
fi
echo "HUBBLE FORWARDED FLOW RESULT: PASS"

echo "Namespace kept for inspection: ${NS}"
echo "SMOKE TEST RESULT: PASS"
