#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Deploys OKE, configures cluster access, and runs the complete Cilium
# chaining validation workflow while preserving each validation script as a
# standalone entry point.

set -euo pipefail

usage() {
  cat <<'USAGE'
usage: deploy-and-validate.sh [cluster-name] [options]

The cluster name defaults to oke_cilium_chaining and must match a key under
clusters in the shared tfvars file.

Options:
  --plan-only                 Plan the selected first Terraform stage without applying.
  --existing-cluster          Skip OKE apply and kubeconfig generation.
  --provision-network         Create the packaged disposable reference network.
  --network-tfvars PATH       Network tfvars used with --provision-network.
  --attach-security-lists     Run the generated, interactive attachment script.
  --kube-context NAME         Desired kubeconfig context. Default: cluster name.
  --kube-endpoint TYPE        PUBLIC_ENDPOINT or PRIVATE_ENDPOINT.
                              Default: PUBLIC_ENDPOINT.
  --skip-base-test            Skip the pre-Cilium OCI CNI connectivity test.
  --skip-tests                Skip endpoint, Service, Hubble, and policy tests.

Environment:
  TFVARS                      Shared tfvars file.
  NETWORK_TFVARS              Disposable-network tfvars file.
  KUBECONFIG                  Kubeconfig file. Default: ~/.kube/config.
  RESULTS_DIR                 Validation log directory.
  NODE_READY_TIMEOUT          kubectl wait timeout. Default: 20m.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OKE_STACK="${REPO_ROOT}/stacks/01-oke"
NETWORK_STACK="${REPO_ROOT}/stacks/00-network"

CLUSTER_NAME="oke_cilium_chaining"
if [[ $# -gt 0 && "$1" != -* ]]; then
  CLUSTER_NAME="$1"
  shift
fi

PLAN_ONLY=false
EXISTING_CLUSTER=false
PROVISION_NETWORK=false
ATTACH_SECURITY_LISTS=false
NETWORK_TFVARS="${NETWORK_TFVARS:-${REPO_ROOT}/envs/oke-vcn-native-cilium-network.tfvars}"
SKIP_BASE_TEST=false
SKIP_TESTS=false
KUBE_CONTEXT="${KUBE_CONTEXT:-$CLUSTER_NAME}"
KUBE_ENDPOINT="${KUBE_ENDPOINT:-PUBLIC_ENDPOINT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-only) PLAN_ONLY=true ;;
    --existing-cluster) EXISTING_CLUSTER=true ;;
    --provision-network) PROVISION_NETWORK=true ;;
    --network-tfvars)
      [[ $# -ge 2 ]] || { echo "ERROR: --network-tfvars requires a path." >&2; exit 2; }
      NETWORK_TFVARS="$2"
      shift
      ;;
    --attach-security-lists) ATTACH_SECURITY_LISTS=true ;;
    --kube-context)
      [[ $# -ge 2 ]] || { echo "ERROR: --kube-context requires a value." >&2; exit 2; }
      KUBE_CONTEXT="$2"
      shift
      ;;
    --kube-endpoint)
      [[ $# -ge 2 ]] || { echo "ERROR: --kube-endpoint requires a value." >&2; exit 2; }
      KUBE_ENDPOINT="$2"
      shift
      ;;
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

if [[ "$PLAN_ONLY" == "true" && "$EXISTING_CLUSTER" == "true" ]]; then
  echo "ERROR: --plan-only and --existing-cluster cannot be used together." >&2
  exit 2
fi

if [[ "$EXISTING_CLUSTER" == "true" && "$PROVISION_NETWORK" == "true" ]]; then
  echo "ERROR: --existing-cluster and --provision-network cannot be used together." >&2
  exit 2
fi

if [[ "$PROVISION_NETWORK" == "true" && "$ATTACH_SECURITY_LISTS" == "true" ]]; then
  echo "ERROR: disposable-network mode attaches its generated security lists automatically; omit --attach-security-lists." >&2
  exit 2
fi

case "$KUBE_ENDPOINT" in
  PUBLIC_ENDPOINT|PRIVATE_ENDPOINT) ;;
  *)
    echo "ERROR: --kube-endpoint must be PUBLIC_ENDPOINT or PRIVATE_ENDPOINT." >&2
    exit 2
    ;;
esac

TFVARS="${TFVARS:-${REPO_ROOT}/envs/oke-vcn-native-cilium-chaining.tfvars}"
RESULTS_DIR="${RESULTS_DIR:-${REPO_ROOT}/validation-results}"
NODE_READY_TIMEOUT="${NODE_READY_TIMEOUT:-20m}"
KUBECONFIG_FILE="${KUBECONFIG:-$HOME/.kube/config}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${RESULTS_DIR}/deploy-and-validate-${TIMESTAMP}.log"

if [[ "$KUBECONFIG_FILE" == *:* ]]; then
  echo "ERROR: KUBECONFIG must name one file, not a colon-separated list." >&2
  exit 2
fi

if [[ "$PROVISION_NETWORK" == "true" && ! -f "$NETWORK_TFVARS" ]]; then
  echo "ERROR: network tfvars file not found: ${NETWORK_TFVARS}" >&2
  echo "Create it from envs/oke-vcn-native-cilium-network.tfvars.example." >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"
mkdir -p "$(dirname "$KUBECONFIG_FILE")"

OKE_STATUS="NOT RUN"
NETWORK_STATUS="NOT REQUESTED"
ACCESS_STATUS="NOT RUN"
NODE_STATUS="NOT RUN"
CILIUM_STATUS="NOT RUN"
BASE_TEST_STATUS="NOT RUN"
SMOKE_STATUS="NOT RUN"
SERVICE_STATUS="NOT RUN"
SERVICE_TABLE_STATUS="NOT RUN"
HUBBLE_STATUS="NOT RUN"
POLICY_STATUS="NOT RUN"
SECURITY_LIST_STATUS="NOT REQUESTED"

normalize_failed_stage() {
  [[ "$OKE_STATUS" == "RUNNING" ]] && OKE_STATUS="FAIL"
  [[ "$NETWORK_STATUS" == "RUNNING" ]] && NETWORK_STATUS="FAIL"
  [[ "$ACCESS_STATUS" == "RUNNING" ]] && ACCESS_STATUS="FAIL"
  [[ "$NODE_STATUS" == "RUNNING" ]] && NODE_STATUS="FAIL"
  [[ "$CILIUM_STATUS" == "RUNNING" ]] && CILIUM_STATUS="FAIL"
}

print_summary() {
  local exit_status="$1"

  normalize_failed_stage
  echo
  echo "===== END-TO-END SUMMARY ====="
  echo "Prerequisite network: ${NETWORK_STATUS}"
  if [[ "$PLAN_ONLY" == "true" ]]; then
    echo "OKE Terraform plan: ${OKE_STATUS}"
    echo "Resources applied: NO"
  else
    echo "OKE cluster and VCN-native node pool: ${OKE_STATUS}"
    echo "Subnet security-list attachment: ${SECURITY_LIST_STATUS}"
    echo "Kubeconfig and Kubernetes API access: ${ACCESS_STATUS}"
    echo "Worker nodes Ready: ${NODE_STATUS}"
    echo "OCI VCN-native cross-node connectivity: ${BASE_TEST_STATUS}"
    echo "Cilium installation and agent health: ${CILIUM_STATUS}"
    echo "Cilium chained endpoint smoke test: ${SMOKE_STATUS}"
    echo "Cross-node ClusterIP and service DNS connectivity: ${SERVICE_STATUS}"
    echo "Cilium service-table visibility: ${SERVICE_TABLE_STATUS}"
    echo "Hubble forwarded and policy-denied flow visibility: ${HUBBLE_STATUS}"
    echo "Kubernetes NetworkPolicy enforcement: ${POLICY_STATUS}"
  fi

  if [[ "$exit_status" == "0" ]]; then
    echo "OVERALL RESULT: PASS"
  else
    echo "OVERALL RESULT: FAIL"
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

run_workflow() (
set -euo pipefail
trap on_exit EXIT

for command_name in terraform jq kubectl; do
  command -v "$command_name" >/dev/null || {
    echo "ERROR: required command is not available: ${command_name}" >&2
    exit 1
  }
done

if [[ "$PLAN_ONLY" == "false" && "$EXISTING_CLUSTER" == "false" ]]; then
  command -v oci >/dev/null || {
    echo "ERROR: required command is not available: oci" >&2
    exit 1
  }
fi

if [[ ! -f "$TFVARS" ]]; then
  echo "ERROR: tfvars file not found: ${TFVARS}" >&2
  echo "Create it from envs/oke-vcn-native-cilium-chaining.tfvars.example." >&2
  exit 1
fi

echo "===== selected inputs ====="
echo "cluster configuration key: ${CLUSTER_NAME}"
echo "kube context: ${KUBE_CONTEXT}"
echo "kubeconfig: ${KUBECONFIG_FILE}"
echo "API endpoint type: ${KUBE_ENDPOINT}"
echo "tfvars: ${TFVARS}"
echo "provision disposable network: ${PROVISION_NETWORK}"
[[ "$PROVISION_NETWORK" == "true" ]] && echo "network tfvars: ${NETWORK_TFVARS}"
echo "results log: ${LOG_FILE}"

if [[ "$PROVISION_NETWORK" == "true" ]]; then
  echo
  echo "===== stage 0: provision disposable prerequisite network ====="
  NETWORK_STATUS="RUNNING"
  terraform -chdir="$NETWORK_STACK" init
  terraform -chdir="$NETWORK_STACK" validate
  terraform -chdir="$NETWORK_STACK" plan -var-file="$NETWORK_TFVARS" -out=tfplan

  if [[ "$PLAN_ONLY" == "true" ]]; then
    NETWORK_STATUS="PLAN PASS"
    OKE_STATUS="NOT PLANNED (network not applied)"
    exit 0
  fi

  terraform -chdir="$NETWORK_STACK" apply tfplan
  terraform -chdir="$NETWORK_STACK" output vcn_name
  terraform -chdir="$NETWORK_STACK" output service_gateway_id
  terraform -chdir="$NETWORK_STACK" output subnet_ids
  NETWORK_STATUS="PASS (sample owned)"
fi

if [[ "$EXISTING_CLUSTER" == "false" ]]; then
  echo
  echo "===== stage 1: provision OKE and VCN-native node pool ====="
  OKE_STATUS="RUNNING"
  terraform -chdir="$OKE_STACK" init
  terraform -chdir="$OKE_STACK" validate
  terraform -chdir="$OKE_STACK" plan -var-file="$TFVARS" -out=tfplan

  if [[ "$PLAN_ONLY" == "true" ]]; then
    OKE_STATUS="PASS"
    exit 0
  fi

  terraform -chdir="$OKE_STACK" apply tfplan
  terraform -chdir="$OKE_STACK" output cluster_cni_types
  terraform -chdir="$OKE_STACK" output node_pool_cni_types
  terraform -chdir="$OKE_STACK" output resolved_network
  OKE_STATUS="PASS"

  if [[ "$PROVISION_NETWORK" == "true" || "$ATTACH_SECURITY_LISTS" == "true" ]]; then
    echo
    echo "===== stage 2: review and attach generated security lists ====="
    ATTACH_SCRIPT="${REPO_ROOT}/generated/attach-security-lists.sh"
    [[ -x "$ATTACH_SCRIPT" ]] || {
      echo "ERROR: generated attachment script is unavailable: ${ATTACH_SCRIPT}" >&2
      exit 1
    }
    if [[ "$PROVISION_NETWORK" == "true" ]]; then
      OCI_REGION="$(terraform -chdir="$OKE_STACK" output -raw region)" \
        "$ATTACH_SCRIPT" <<<"APPLY"
      SECURITY_LIST_STATUS="PASS (sample-owned network)"
    else
      OCI_REGION="$(terraform -chdir="$OKE_STACK" output -raw region)" \
        "$ATTACH_SCRIPT"
      SECURITY_LIST_STATUS="SCRIPT COMPLETED"
    fi
  fi

  echo
  echo "===== stage 3: generate kubeconfig ====="
  ACCESS_STATUS="RUNNING"
  OCI_REGION="$(terraform -chdir="$OKE_STACK" output -raw region)"
  CLUSTER_ID="$(terraform -chdir="$OKE_STACK" output -json cluster_ids | \
    jq -er --arg cluster "$CLUSTER_NAME" '.[$cluster]')"

  oci ce cluster create-kubeconfig \
    --cluster-id "$CLUSTER_ID" \
    --file "$KUBECONFIG_FILE" \
    --region "$OCI_REGION" \
    --token-version 2.0.0 \
    --kube-endpoint "$KUBE_ENDPOINT"

  GENERATED_CONTEXT="$(KUBECONFIG="$KUBECONFIG_FILE" kubectl config current-context)"
  if [[ "$GENERATED_CONTEXT" != "$KUBE_CONTEXT" ]]; then
    CONFIG_JSON="$(KUBECONFIG="$KUBECONFIG_FILE" kubectl config view -o json)"
    if jq -e --arg context "$KUBE_CONTEXT" \
      'any(.contexts[]?; .name == $context)' <<<"$CONFIG_JSON" >/dev/null; then
      GENERATED_CLUSTER="$(jq -er --arg context "$GENERATED_CONTEXT" \
        '.contexts[] | select(.name == $context) | .context.cluster' <<<"$CONFIG_JSON")"
      DESIRED_CLUSTER="$(jq -er --arg context "$KUBE_CONTEXT" \
        '.contexts[] | select(.name == $context) | .context.cluster' <<<"$CONFIG_JSON")"
      GENERATED_SERVER="$(jq -er --arg cluster "$GENERATED_CLUSTER" \
        '.clusters[] | select(.name == $cluster) | .cluster.server' <<<"$CONFIG_JSON")"
      DESIRED_SERVER="$(jq -er --arg cluster "$DESIRED_CLUSTER" \
        '.clusters[] | select(.name == $cluster) | .cluster.server' <<<"$CONFIG_JSON")"
      if [[ "$GENERATED_SERVER" != "$DESIRED_SERVER" ]]; then
        echo "ERROR: kube context ${KUBE_CONTEXT} already exists for a different API server." >&2
        echo "Choose another name with --kube-context." >&2
        exit 1
      fi
      KUBECONFIG="$KUBECONFIG_FILE" kubectl config use-context "$KUBE_CONTEXT" >/dev/null
    else
      KUBECONFIG="$KUBECONFIG_FILE" kubectl config rename-context \
        "$GENERATED_CONTEXT" "$KUBE_CONTEXT" >/dev/null
    fi
  fi

  KUBECONFIG="$KUBECONFIG_FILE" kubectl --context "$KUBE_CONTEXT" get --raw=/readyz
  ACCESS_STATUS="PASS"
else
  OKE_STATUS="SKIPPED (existing cluster)"
  SECURITY_LIST_STATUS="SKIPPED (existing cluster)"
  ACCESS_STATUS="RUNNING"
  KUBECONFIG="$KUBECONFIG_FILE" kubectl --context "$KUBE_CONTEXT" get --raw=/readyz
  ACCESS_STATUS="PASS"
fi

echo
echo "===== stage 4: wait for worker nodes ====="
NODE_STATUS="RUNNING"
KUBECONFIG="$KUBECONFIG_FILE" kubectl --context "$KUBE_CONTEXT" wait \
  --for=condition=Ready nodes --all --timeout="$NODE_READY_TIMEOUT"
KUBECONFIG="$KUBECONFIG_FILE" kubectl --context "$KUBE_CONTEXT" get nodes -o wide
NODE_STATUS="PASS"

echo
echo "===== stage 5: install Cilium and run network validation ====="
CILIUM_STATUS="RUNNING"
run_cilium_validation() {
  TARGET_CLUSTER_NAME="$CLUSTER_NAME" \
  TFVARS="$TFVARS" \
  KUBECONFIG="$KUBECONFIG_FILE" \
  RESULTS_DIR="$RESULTS_DIR" \
    "${SCRIPT_DIR}/cilium-install-verify.sh" "$KUBE_CONTEXT" "$@"
}

if [[ "$SKIP_BASE_TEST" == "true" && "$SKIP_TESTS" == "true" ]]; then
  run_cilium_validation --skip-base-test --skip-tests
elif [[ "$SKIP_BASE_TEST" == "true" ]]; then
  run_cilium_validation --skip-base-test
elif [[ "$SKIP_TESTS" == "true" ]]; then
  run_cilium_validation --skip-tests
else
  run_cilium_validation
fi

CILIUM_STATUS="PASS"
if [[ "$SKIP_BASE_TEST" == "true" ]]; then
  BASE_TEST_STATUS="SKIPPED"
else
  BASE_TEST_STATUS="PASS"
fi
if [[ "$SKIP_TESTS" == "true" ]]; then
  SMOKE_STATUS="SKIPPED"
  SERVICE_STATUS="SKIPPED"
  SERVICE_TABLE_STATUS="SKIPPED"
  HUBBLE_STATUS="SKIPPED"
  POLICY_STATUS="SKIPPED"
else
  SMOKE_STATUS="PASS"
  SERVICE_STATUS="PASS"
  SERVICE_TABLE_STATUS="PASS"
  HUBBLE_STATUS="PASS"
  POLICY_STATUS="PASS"
fi
)

set +e
run_workflow 2>&1 | tee "$LOG_FILE"
STATUS=${PIPESTATUS[0]}
set -e

exit "$STATUS"
