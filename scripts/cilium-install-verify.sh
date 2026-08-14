#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Installs and validates OCI VCN-native CNI with Cilium generic-veth chaining.

set -euo pipefail

usage() {
  cat <<'USAGE'
usage: cilium-install-verify.sh <kube-context> [options]

Options:
  --plan-only       Run the Cilium Terraform plan without applying it.
  --verify-only     Skip ConfigMap and Terraform apply; verify an existing install.
  --skip-base-test  Skip the cross-node OCI VCN-native connectivity test.
  --skip-tests      Skip endpoint, Service, Hubble, and policy tests.

Environment:
  TARGET_CLUSTER_NAME  Key under clusters in the tfvars file. Default: kube-context.
  TFVARS               Shared tfvars file. Default: envs/oke-vcn-native-cilium-chaining.tfvars.
  CILIUM_NS            Cilium namespace. Default: kube-system.
  CILIUM_WORKSPACE     Terraform workspace. Default: target cluster name.
  KUBECONFIG           Optional kubeconfig path passed to Terraform.
  HELM_RUNTIME_DIR     Writable Helm cache/config root. Default: .helm.
  RESULTS_DIR          Validation log directory. Default: validation-results.
USAGE
}

CONTEXT="${1:-}"
if [[ -z "$CONTEXT" || "$CONTEXT" == "-h" || "$CONTEXT" == "--help" ]]; then
  usage
  [[ -n "$CONTEXT" ]] && exit 0 || exit 2
fi
shift

PLAN_ONLY=false
VERIFY_ONLY=false
SKIP_BASE_TEST=false
SKIP_TESTS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-only) PLAN_ONLY=true ;;
    --verify-only) VERIFY_ONLY=true ;;
    --skip-base-test) SKIP_BASE_TEST=true ;;
    --skip-tests) SKIP_TESTS=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$PLAN_ONLY" == "true" && "$VERIFY_ONLY" == "true" ]]; then
  echo "ERROR: --plan-only and --verify-only cannot be used together." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CILIUM_STACK="${REPO_ROOT}/stacks/03-cilium"
TARGET_CLUSTER_NAME="${TARGET_CLUSTER_NAME:-$CONTEXT}"
TFVARS="${TFVARS:-${REPO_ROOT}/envs/oke-vcn-native-cilium-chaining.tfvars}"
CILIUM_NS="${CILIUM_NS:-kube-system}"
CILIUM_WORKSPACE="${CILIUM_WORKSPACE:-$TARGET_CLUSTER_NAME}"
RESULTS_DIR="${RESULTS_DIR:-${REPO_ROOT}/validation-results}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${RESULTS_DIR}/cilium-chaining-${TIMESTAMP}.log"
KUBECONFIG_FILE="${KUBECONFIG:-$HOME/.kube/config}"
HELM_RUNTIME_DIR="${HELM_RUNTIME_DIR:-${REPO_ROOT}/.helm}"
HELM_CACHE_HOME="${HELM_CACHE_HOME:-${HELM_RUNTIME_DIR}/cache}"
HELM_CONFIG_HOME="${HELM_CONFIG_HOME:-${HELM_RUNTIME_DIR}/config}"
HELM_DATA_HOME="${HELM_DATA_HOME:-${HELM_RUNTIME_DIR}/data}"
HELM_REPOSITORY_CACHE="${HELM_REPOSITORY_CACHE:-${HELM_CACHE_HOME}/repository}"
HELM_REPOSITORY_CONFIG="${HELM_REPOSITORY_CONFIG:-${HELM_CONFIG_HOME}/repositories.yaml}"
HELM_REGISTRY_CONFIG="${HELM_REGISTRY_CONFIG:-${HELM_CONFIG_HOME}/registry.json}"

mkdir -p "$RESULTS_DIR"
mkdir -p "$HELM_REPOSITORY_CACHE" "$HELM_CONFIG_HOME" "$HELM_DATA_HOME"

export HELM_CACHE_HOME
export HELM_CONFIG_HOME
export HELM_DATA_HOME
export HELM_REPOSITORY_CACHE
export HELM_REPOSITORY_CONFIG
export HELM_REGISTRY_CONFIG

if [[ ! -f "$TFVARS" ]]; then
  echo "ERROR: tfvars file not found: ${TFVARS}" >&2
  exit 1
fi

run_workflow() (
  set -euo pipefail

  echo "===== selected inputs ====="
  echo "kube context: ${CONTEXT}"
  echo "target cluster: ${TARGET_CLUSTER_NAME}"
  echo "tfvars: ${TFVARS}"
  echo "Cilium namespace: ${CILIUM_NS}"
  echo "Terraform workspace: ${CILIUM_WORKSPACE}"
  echo "results log: ${LOG_FILE}"

  echo
  echo "===== cluster preflight ====="
  kubectl --context "$CONTEXT" get nodes -o wide
  kubectl --context "$CONTEXT" -n kube-system get ds vcn-native-ip-cni kube-proxy

  if [[ "$PLAN_ONLY" == "true" ]]; then
    terraform -chdir="$CILIUM_STACK" init
    terraform -chdir="$CILIUM_STACK" workspace select "$CILIUM_WORKSPACE" >/dev/null 2>&1 || \
      terraform -chdir="$CILIUM_STACK" workspace new "$CILIUM_WORKSPACE"
    terraform -chdir="$CILIUM_STACK" plan \
      -var-file="$TFVARS" \
      -var="kubeconfig_path=${KUBECONFIG_FILE}" \
      -var="kube_context=${CONTEXT}" \
      -var="target_cluster_name=${TARGET_CLUSTER_NAME}"
    echo "PLAN RESULT: PASS"
    return
  fi

  if [[ "$VERIFY_ONLY" == "false" ]]; then
    if [[ "$SKIP_BASE_TEST" == "false" ]]; then
      echo
      echo "===== stage 1: OCI VCN-native cross-node connectivity ====="
      "${SCRIPT_DIR}/pod-connectivity-test.sh" "$CONTEXT"
    fi

    echo
    echo "===== stage 2: apply chained CNI configuration ====="
    CILIUM_NS="$CILIUM_NS" \
      "${SCRIPT_DIR}/apply-oci-cilium-chaining-config.sh" "$CONTEXT"

    echo
    echo "===== stage 3: install Cilium with Terraform ====="
    terraform -chdir="$CILIUM_STACK" init
    terraform -chdir="$CILIUM_STACK" workspace select "$CILIUM_WORKSPACE" >/dev/null 2>&1 || \
      terraform -chdir="$CILIUM_STACK" workspace new "$CILIUM_WORKSPACE"
    terraform -chdir="$CILIUM_STACK" plan \
      -var-file="$TFVARS" \
      -var="kubeconfig_path=${KUBECONFIG_FILE}" \
      -var="kube_context=${CONTEXT}" \
      -var="target_cluster_name=${TARGET_CLUSTER_NAME}" \
      -out=tfplan
    terraform -chdir="$CILIUM_STACK" apply tfplan
  fi

  echo
  echo "===== stage 4: Cilium and OCI CNI health ====="
  kubectl --context "$CONTEXT" -n "$CILIUM_NS" rollout status ds/cilium --timeout=10m
  kubectl --context "$CONTEXT" -n kube-system get ds cilium vcn-native-ip-cni kube-proxy
  kubectl --context "$CONTEXT" -n "$CILIUM_NS" exec ds/cilium -- cilium-dbg status --verbose || \
    kubectl --context "$CONTEXT" -n "$CILIUM_NS" exec ds/cilium -- cilium status --verbose

  if [[ "$SKIP_TESTS" == "false" ]]; then
    echo
    echo "===== stage 5: chained endpoint smoke test ====="
    CILIUM_NS="$CILIUM_NS" "${SCRIPT_DIR}/cilium-smoke-test.sh" "$CONTEXT"

    echo
    echo "===== stage 6: Kubernetes NetworkPolicy test ====="
    CILIUM_NS="$CILIUM_NS" "${SCRIPT_DIR}/cilium-policy-test.sh" "$CONTEXT"
  fi

  echo
  echo "===== VALIDATION SUMMARY ====="
  [[ "$SKIP_BASE_TEST" == "false" && "$VERIFY_ONLY" == "false" ]] && \
    echo "OCI VCN-native cross-node connectivity: PASS"
  echo "Cilium DaemonSet and agent health: PASS"
  if [[ "$SKIP_TESTS" == "false" ]]; then
    echo "Cilium chained endpoint smoke test: PASS"
    echo "Cross-node ClusterIP and service DNS connectivity: PASS"
    echo "Cilium service-table visibility: PASS"
    echo "Hubble forwarded and policy-denied flow visibility: PASS"
    echo "Kubernetes NetworkPolicy enforcement: PASS"
  fi
  echo "OVERALL RESULT: PASS"
  echo "Detailed log: ${LOG_FILE}"
)

set +e
run_workflow 2>&1 | tee "$LOG_FILE"
STATUS=${PIPESTATUS[0]}
set -e

if [[ "$STATUS" != "0" ]]; then
  {
    echo
    echo "===== VALIDATION SUMMARY ====="
    echo "OVERALL RESULT: FAIL"
    echo "Exit status: ${STATUS}"
    echo "Detailed log: ${LOG_FILE}"
  } | tee -a "$LOG_FILE"
fi

exit "$STATUS"
