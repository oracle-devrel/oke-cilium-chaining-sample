#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Applies the OCI CNI and Cilium generic-veth chained CNI configuration.

set -euo pipefail

CONTEXT="${1:?usage: apply-oci-cilium-chaining-config.sh <kube-context>}"
CONFIG_MAP="${CONFIG_MAP:-cilium-chaining-config}"
CILIUM_NS="${CILIUM_NS:-${cilium_ns:-${NAMESPACE:-kube-system}}}"

kube() {
  kubectl --context "$CONTEXT" "$@"
}

kube get namespace "$CILIUM_NS" >/dev/null 2>&1 || kube create namespace "$CILIUM_NS"

kube -n "$CILIUM_NS" apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CONFIG_MAP}
data:
  cni-config: |-
    {
      "name": "oci",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "cniVersion": "0.3.1",
          "type": "oci-ipvlan",
          "mode": "l2",
          "ipam": {
            "type": "oci-ipam"
          }
        },
        {
          "cniVersion": "0.3.1",
          "type": "oci-ptp",
          "containerInterface": "ptp-veth0",
          "mtu": 9000
        },
        {
          "type": "cilium-cni",
          "chaining-mode": "generic-veth",
          "enable-debug": false,
          "log-file": "/var/run/cilium/cilium-cni.log"
        }
      ]
    }
YAML

echo "Applied ${CILIUM_NS}/${CONFIG_MAP} for OCI CNI + Cilium generic-veth chaining."
