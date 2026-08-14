#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Destroys the OKE VCN-native CNI and Cilium chaining sample in dependency
# order. Prerequisite network destruction is explicit because the sample does
# not normally own the referenced VCN and subnets.

set -euo pipefail

usage() {
  cat <<'USAGE'
usage: destroy-all.sh <kube-context> [options]

Options:
  --plan-only                 Create and show destroy plans without applying.
  --confirm DESTROY           Required for an actual destroy.
  --destroy-network           Also destroy the sample-owned disposable network.
  --network-stack PATH        Network stack override. Default: stacks/00-network.
  --network-tfvars PATH       Network tfvars override. Default: sample network tfvars.

Environment:
  TARGET_CLUSTER_NAME         Key under clusters in the shared tfvars file.
                              Default: kube-context.
  CILIUM_WORKSPACE            Cilium Terraform workspace.
                              Default: target cluster name.
  TFVARS                      Shared sample tfvars file.
  NETWORK_TFVARS              Disposable-network tfvars file.
  KUBECONFIG                  Kubeconfig file. Default: ~/.kube/config.
  RESULTS_DIR                 Cleanup log directory. Default: validation-results.

The network is never destroyed unless --destroy-network is supplied and the
selected network stack contains Terraform state for its VCN.
USAGE
}

CONTEXT="${1:-}"
if [[ -z "$CONTEXT" || "$CONTEXT" == "-h" || "$CONTEXT" == "--help" ]]; then
  usage
  [[ -n "$CONTEXT" ]] && exit 0 || exit 2
fi
shift

PLAN_ONLY=false
DESTROY_NETWORK=false
CONFIRM_VALUE=""
NETWORK_STACK="${NETWORK_STACK:-}"
NETWORK_TFVARS="${NETWORK_TFVARS:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-only) PLAN_ONLY=true ;;
    --confirm)
      [[ $# -ge 2 ]] || { echo "ERROR: --confirm requires a value." >&2; exit 2; }
      CONFIRM_VALUE="$2"
      shift
      ;;
    --destroy-network) DESTROY_NETWORK=true ;;
    --network-stack)
      [[ $# -ge 2 ]] || { echo "ERROR: --network-stack requires a path." >&2; exit 2; }
      NETWORK_STACK="$2"
      shift
      ;;
    --network-tfvars)
      [[ $# -ge 2 ]] || { echo "ERROR: --network-tfvars requires a path." >&2; exit 2; }
      NETWORK_TFVARS="$2"
      shift
      ;;
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

if [[ "$PLAN_ONLY" == "false" && "$CONFIRM_VALUE" != "DESTROY" ]]; then
  echo "ERROR: actual cleanup requires --confirm DESTROY." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OKE_STACK="${REPO_ROOT}/stacks/01-oke"
CILIUM_STACK="${REPO_ROOT}/stacks/03-cilium"
NETWORK_STACK="${NETWORK_STACK:-${REPO_ROOT}/stacks/00-network}"
NETWORK_TFVARS="${NETWORK_TFVARS:-${REPO_ROOT}/envs/oke-vcn-native-cilium-network.tfvars}"
TARGET_CLUSTER_NAME="${TARGET_CLUSTER_NAME:-$CONTEXT}"
CILIUM_WORKSPACE="${CILIUM_WORKSPACE:-$TARGET_CLUSTER_NAME}"
TFVARS="${TFVARS:-${REPO_ROOT}/envs/oke-vcn-native-cilium-chaining.tfvars}"
KUBECONFIG_FILE="${KUBECONFIG:-$HOME/.kube/config}"
RESULTS_DIR="${RESULTS_DIR:-${REPO_ROOT}/validation-results}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${RESULTS_DIR}/destroy-all-${TIMESTAMP}.log"
RESTORE_SCRIPT="${REPO_ROOT}/generated/detach-security-lists.sh"

if [[ "$KUBECONFIG_FILE" == *:* ]]; then
  echo "ERROR: KUBECONFIG must name one file, not a colon-separated list." >&2
  exit 2
fi

[[ -f "$TFVARS" ]] || { echo "ERROR: tfvars file not found: ${TFVARS}" >&2; exit 1; }
if [[ "$DESTROY_NETWORK" == "true" ]]; then
  [[ -d "$NETWORK_STACK" ]] || { echo "ERROR: network stack not found: ${NETWORK_STACK}" >&2; exit 1; }
  [[ -f "$NETWORK_TFVARS" ]] || { echo "ERROR: network tfvars not found: ${NETWORK_TFVARS}" >&2; exit 1; }
fi

mkdir -p "$RESULTS_DIR"

NAMESPACE_STATUS="NOT RUN"
CILIUM_STATUS="NOT RUN"
CONFIG_STATUS="NOT RUN"
RESTORE_STATUS="NOT RUN"
OKE_STATUS="NOT RUN"
NETWORK_STATUS="NOT REQUESTED"

normalize_failed_stage() {
  [[ "$NAMESPACE_STATUS" == "RUNNING" ]] && NAMESPACE_STATUS="FAIL"
  [[ "$CILIUM_STATUS" == "RUNNING" ]] && CILIUM_STATUS="FAIL"
  [[ "$CONFIG_STATUS" == "RUNNING" ]] && CONFIG_STATUS="FAIL"
  [[ "$RESTORE_STATUS" == "RUNNING" ]] && RESTORE_STATUS="FAIL"
  [[ "$OKE_STATUS" == "RUNNING" ]] && OKE_STATUS="FAIL"
  [[ "$NETWORK_STATUS" == "RUNNING" ]] && NETWORK_STATUS="FAIL"
}

print_summary() {
  local exit_status="$1"

  normalize_failed_stage
  echo
  echo "===== DESTROY SUMMARY ====="
  echo "Validation namespaces: ${NAMESPACE_STATUS}"
  echo "Cilium Terraform resources: ${CILIUM_STATUS}"
  echo "Chaining ConfigMap: ${CONFIG_STATUS}"
  echo "Original subnet security lists restored: ${RESTORE_STATUS}"
  echo "OKE cluster, node pool, and OKE security lists: ${OKE_STATUS}"
  echo "Prerequisite network: ${NETWORK_STATUS}"
  if [[ "$exit_status" == "0" ]]; then
    echo "OVERALL DESTROY RESULT: PASS"
  else
    echo "OVERALL DESTROY RESULT: FAIL"
    echo "Exit status: ${exit_status}"
  fi
  echo "Detailed log: ${LOG_FILE}"
}

on_exit() {
  local exit_status=$?
  trap - EXIT
  set +e
  print_summary "$exit_status"
  exit "$exit_status"
}

plan_cilium_destroy() {
  # The release is verified through kubectl before cleanup. Planning from state
  # keeps destruction independent of a local Helm chart cache or repository.
  terraform -chdir="$CILIUM_STACK" plan -destroy -refresh=false \
    -var-file="$TFVARS" \
    -var="kubeconfig_path=${KUBECONFIG_FILE}" \
    -var="kube_context=${CONTEXT}" \
    -var="target_cluster_name=${TARGET_CLUSTER_NAME}" \
    -out=destroy.tfplan
}

plan_oke_destroy() {
  terraform -chdir="$OKE_STACK" plan -destroy \
    -var-file="$TFVARS" \
    -out=destroy.tfplan
}

plan_network_destroy() {
  terraform -chdir="$NETWORK_STACK" plan -destroy \
    -var-file="$NETWORK_TFVARS" \
    -out=destroy.tfplan
}

assert_network_owned() {
  if ! terraform -chdir="$NETWORK_STACK" state show oci_core_vcn.this >/dev/null 2>&1; then
    echo "ERROR: refusing network deletion because the selected stack does not own oci_core_vcn.this in Terraform state." >&2
    return 1
  fi
}

destroy_network_with_retries() {
  local attempt
  for attempt in 1 2 3 4 5; do
    echo "Network destroy attempt ${attempt} of 5"
    if plan_network_destroy && terraform -chdir="$NETWORK_STACK" apply destroy.tfplan; then
      return 0
    fi
    if [[ "$attempt" != "5" ]]; then
      echo "Network dependencies are still releasing; retrying in 30 seconds."
      sleep 30
    fi
  done
  return 1
}

run_destroy() (
set -euo pipefail
trap on_exit EXIT

for command_name in terraform kubectl; do
  command -v "$command_name" >/dev/null || {
    echo "ERROR: required command is not available: ${command_name}" >&2
    exit 1
  }
done
if [[ -f "$RESTORE_SCRIPT" || "$DESTROY_NETWORK" == "true" ]]; then
  command -v oci >/dev/null || {
    echo "ERROR: required command is not available: oci" >&2
    exit 1
  }
fi

echo "===== selected inputs ====="
echo "kube context: ${CONTEXT}"
echo "target cluster: ${TARGET_CLUSTER_NAME}"
echo "Cilium workspace: ${CILIUM_WORKSPACE}"
echo "tfvars: ${TFVARS}"
echo "destroy prerequisite network: ${DESTROY_NETWORK}"
[[ "$DESTROY_NETWORK" == "true" ]] && echo "network stack: ${NETWORK_STACK}"
[[ "$DESTROY_NETWORK" == "true" ]] && echo "network tfvars: ${NETWORK_TFVARS}"
echo "results log: ${LOG_FILE}"

echo
echo "===== initialize Terraform stacks ====="
terraform -chdir="$CILIUM_STACK" init
terraform -chdir="$OKE_STACK" init

CILIUM_WORKSPACE_FOUND=false
if terraform -chdir="$CILIUM_STACK" workspace select "$CILIUM_WORKSPACE" >/dev/null 2>&1; then
  CILIUM_WORKSPACE_FOUND=true
  CILIUM_STATUS="RUNNING"
  plan_cilium_destroy
  if [[ "$PLAN_ONLY" == "true" ]]; then
    CILIUM_STATUS="PLAN PASS"
  else
    CILIUM_STATUS="PLAN READY"
  fi
else
  echo "Cilium workspace not found; skipping Cilium Terraform destroy."
  CILIUM_STATUS="SKIPPED"
fi

OKE_STATUS="RUNNING"
plan_oke_destroy
if [[ "$PLAN_ONLY" == "true" ]]; then
  OKE_STATUS="PLAN PASS"
  NAMESPACE_STATUS="PLAN ONLY"
  CONFIG_STATUS="PLAN ONLY"
  RESTORE_STATUS="PLAN ONLY"
  if [[ "$DESTROY_NETWORK" == "true" ]]; then
    terraform -chdir="$NETWORK_STACK" init
    assert_network_owned
    NETWORK_STATUS="RUNNING"
    plan_network_destroy
    NETWORK_STATUS="PLAN PASS"
  fi
  exit 0
fi

echo
echo "===== stage 1: delete validation namespaces ====="
NAMESPACE_STATUS="RUNNING"
kubectl --context "$CONTEXT" delete namespace \
  -l oke-cilium-sample=true \
  --ignore-not-found \
  --wait=true \
  --timeout=5m
NAMESPACE_STATUS="PASS"

echo
echo "===== stage 2: delete Cilium ====="
if [[ "$CILIUM_WORKSPACE_FOUND" == "true" ]]; then
  CILIUM_STATUS="RUNNING"
  terraform -chdir="$CILIUM_STACK" apply destroy.tfplan
  terraform -chdir="$CILIUM_STACK" workspace select default >/dev/null
  terraform -chdir="$CILIUM_STACK" workspace delete "$CILIUM_WORKSPACE"
  CILIUM_STATUS="PASS"
fi

echo
echo "===== stage 3: delete chaining ConfigMap ====="
CONFIG_STATUS="RUNNING"
kubectl --context "$CONTEXT" -n kube-system delete configmap \
  cilium-chaining-config --ignore-not-found
CONFIG_STATUS="PASS"

echo
echo "===== stage 4: restore original subnet security lists ====="
RESTORE_STATUS="RUNNING"
if [[ -x "$RESTORE_SCRIPT" ]]; then
  "$RESTORE_SCRIPT" <<<"RESTORE"
  RESTORE_STATUS="PASS"
else
  echo "Restore script not found; no generated subnet attachment will be reverted."
  RESTORE_STATUS="SKIPPED"
fi

echo
echo "===== stage 5: destroy OKE resources ====="
terraform -chdir="$OKE_STACK" apply destroy.tfplan
OKE_STATUS="PASS"

if [[ "$DESTROY_NETWORK" == "true" ]]; then
  echo
  echo "===== stage 6: destroy prerequisite network ====="
  NETWORK_STATUS="RUNNING"
  terraform -chdir="$NETWORK_STACK" init
  assert_network_owned
  destroy_network_with_retries
  NETWORK_STATUS="PASS"
fi
)

set +e
run_destroy 2>&1 | tee "$LOG_FILE"
STATUS=${PIPESTATUS[0]}
set -e

exit "$STATUS"
