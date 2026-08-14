<!-- Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved. -->
<!-- Author: Ulaganathan N -->

# OKE VCN-native CNI with Cilium chaining sample

This repository accompanies the OKE VCN-native CNI with Cilium chaining technical blog.

It contains only the generic files needed for the article:

- `stacks/00-network`: Optional disposable VCN, subnets, Internet Gateway, NAT Gateway, Service Gateway, and route prerequisites.
- `stacks/01-oke`: OKE cluster, node pool, and optional security-list resources.
- `stacks/03-cilium`: Cilium Helm installation for the chaining model.
- `modules/`: Terraform modules used by the OKE and Cilium stacks.
- `scripts/`: Validation helpers used by the blog.
- `examples/gateway-api`: Optional Cilium Gateway API extension manifests.
- `envs/oke-vcn-native-cilium-chaining.tfvars.example`: Generic tfvars template.
- `envs/oke-vcn-native-cilium-network.tfvars.example`: Optional disposable-network template.

## Prerequisites

- An OCI compartment and either an existing VCN with endpoint, worker, private pod, and optional load balancer subnets, or permission to create the optional disposable reference network.
- OCI permissions to create OKE clusters, node pools, NSGs or security lists, and to inspect the referenced network resources.
- `bash`, `oci`, `terraform`, `kubectl`, and `jq` installed on an authenticated workstation or private runner. Terraform installs Cilium through the Helm provider; the Helm CLI is not required by the orchestration scripts.
- Network access from that workstation or runner to the OKE Kubernetes API endpoint.
- DNS and outbound access from worker nodes to the required container registries, or equivalent private mirrors.

Existing-network mode creates only the OKE and Cilium resources in the referenced VCN. Optional disposable-network mode creates a minimal reference VCN, subnets, and gateway routes for reproducing the blog from an empty compartment. Private subnets route regional Oracle Services Network traffic through the Service Gateway and other outbound traffic through the NAT Gateway. It is not a production landing-zone design. For the required OCI network design, see:

- [Network Resource Configuration for Cluster Creation and Deployment](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengnetworkconfig.htm)
- [Creating an Enhanced Cluster](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingenhancedclusters.htm)
- [Using the OCI VCN-Native Pod Networking CNI plugin](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengpodnetworking_topic-OCI_CNI_plugin.htm)

## Get the sample

Clone the repository and run all subsequent commands from its root directory:

```bash
git clone https://github.com/oracle-devrel/oke-cilium-chaining-sample.git
cd oke-cilium-chaining-sample
```

## Choose a deployment path

| Path | Use when | Configuration | Deployment command |
| --- | --- | --- | --- |
| Existing VCN | An approved VCN and OKE subnets already exist. | Copy and edit `envs/oke-vcn-native-cilium-chaining.tfvars.example`. | `scripts/deploy-and-validate.sh` |
| Disposable reference network | You want the sample to create an isolated VCN and the required subnets and gateways. | Copy and edit both example tfvars files under `envs/`. | `scripts/deploy-and-validate.sh --provision-network` |

Both paths create the OKE cluster and VCN-native node pool, install Cilium,
run the complete validation suite, and print a final PASS or FAIL summary.
The disposable path owns its network resources and can delete them with the
`--destroy-network` cleanup option. The existing-VCN path leaves the
prerequisite network untouched.

## Prepare configuration

```bash
cp envs/oke-vcn-native-cilium-chaining.tfvars.example \
  envs/oke-vcn-native-cilium-chaining.tfvars
```

For an existing VCN, edit the copied tfvars file with its compartment, VCN, subnet, optional NSG, approved source CIDR, Kubernetes version, compute shape, and region values.

For a disposable from-scratch environment, also prepare the optional network configuration. Keep its VCN and subnet names aligned with the OKE tfvars file:

```bash
cp envs/oke-vcn-native-cilium-network.tfvars.example \
  envs/oke-vcn-native-cilium-network.tfvars
```

The two example files already use matching disposable VCN and subnet names. Edit both files with the same target region and compartment OCID, set only approved source CIDRs, and verify that the example Kubernetes version, compute shape, and nonoverlapping network CIDRs are available in the target region. The examples intentionally use `null` and empty-list defaults for tenancy-specific identifiers and allowed sources; Terraform rejects missing required values instead of opening access broadly.

## Run the complete workflow

The recommended entry point for an existing enterprise VCN provisions the OKE cluster and VCN-native node pool with Terraform, generates kubeconfig, waits for the nodes, installs Cilium with Terraform, runs every network proof, and prints one final summary:

```bash
scripts/deploy-and-validate.sh
```

To reproduce the complete solution from an empty compartment, use the same entry point with optional disposable-network ownership:

```bash
scripts/deploy-and-validate.sh --provision-network
```

This mode applies `stacks/00-network` first, creates the OKE resources, automatically attaches the generated role-specific security lists to the sample-owned subnets, installs Cilium, and runs the same validation suite. If a later stage fails, rerun the same command after correcting the cause; Terraform resumes from the recorded state.

In existing-network mode, the referenced subnets must already have equivalent OKE API, worker, pod, and load balancer rules. The example tfvars enables generated security lists. When those generated lists are required and this repository is authorized to update the existing subnet associations, use:

```bash
scripts/deploy-and-validate.sh --attach-security-lists
```

The attachment remains interactive and requires `APPLY`. Without the flag, cluster creation can succeed while Kubernetes API access or pod networking is blocked by the existing subnet rules.

The cluster name defaults to `oke_cilium_chaining`, matching the key in the example tfvars file. For a private Kubernetes API endpoint, run from a connected private runner:

```bash
scripts/deploy-and-validate.sh \
  --kube-endpoint PRIVATE_ENDPOINT
```

If `oke_cilium_chaining` already exists as a kubeconfig context for another cluster, select a unique context name. The cluster configuration key remains `oke_cilium_chaining`:

```bash
scripts/deploy-and-validate.sh \
  --kube-context oke_cilium_chaining_live
```

The runner writes `validation-results/deploy-and-validate-<timestamp>.log`. It delegates the Cilium stages to `scripts/cilium-install-verify.sh`, which in turn calls the individual connectivity, endpoint, Service, Hubble, and policy checks. Terraform plans are saved and applied noninteractively by the orchestration wrappers. Helm repository metadata is kept in the ignored repository-local `.helm/` runtime, so the workflow does not depend on a user-specific Helm cache. This keeps the one-command workflow and every focused test independently usable.

## Manual workflow: Deploy the OKE cluster

`stacks/01-oke` creates the OKE enhanced cluster, its VCN-native managed node pool, and optional security lists. It resolves the compartment, VCN, and subnets from the OCIDs or names in the tfvars file. The optional `stacks/00-network` is applied automatically only when `--provision-network` is selected.

```bash
terraform -chdir=stacks/01-oke init
terraform -chdir=stacks/01-oke validate
terraform -chdir=stacks/01-oke plan \
  -var-file=../../envs/oke-vcn-native-cilium-chaining.tfvars \
  -out=tfplan
terraform -chdir=stacks/01-oke apply tfplan
```

Verify the resulting cluster, CNI types, node pool, and resolved network:

```bash
terraform -chdir=stacks/01-oke output cluster_ids
terraform -chdir=stacks/01-oke output cluster_cni_types
terraform -chdir=stacks/01-oke output node_pool_cni_types
terraform -chdir=stacks/01-oke output resolved_network
```

When `security_lists.enabled = true`, review and optionally run the generated attachment script. It updates existing subnet security-list associations and requires an explicit `APPLY` confirmation:

```bash
terraform -chdir=stacks/01-oke output attach_instructions
sed -n '1,240p' generated/attach-security-lists.sh
generated/attach-security-lists.sh
```

The stack records the original subnet security-list associations in Terraform state before attachment. This keeps `generated/detach-security-lists.sh` stable and safe to use even after later Terraform refreshes.

## Configure cluster access

Set the region to the value used in the tfvars file, generate kubeconfig, and rename the generated context to the name expected by the sample scripts:

```bash
export OCI_REGION="us-phoenix-1"
export CLUSTER_ID="$(terraform -chdir=stacks/01-oke output -json cluster_ids | \
  jq -r '.oke_cilium_chaining')"

oci ce cluster create-kubeconfig \
  --cluster-id "$CLUSTER_ID" \
  --file "$HOME/.kube/config" \
  --region "$OCI_REGION" \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT

if [[ "$(kubectl config current-context)" != "oke_cilium_chaining" ]]; then
  kubectl config rename-context \
    "$(kubectl config current-context)" oke_cilium_chaining
fi

kubectl --context oke_cilium_chaining get nodes -o wide
```

For a private API endpoint, run from a connected private runner and change the endpoint argument to `--kube-endpoint PRIVATE_ENDPOINT`. See [Setting Up Cluster Access](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdownloadkubeconfigfile.htm).

Continue only when the worker nodes report `Ready`.

## Manual workflow: Configure Cilium chaining

For an OKE cluster that already exists and is reachable through kubeconfig, this Cilium-level orchestration command runs base OCI CNI connectivity, the chaining ConfigMap, Terraform Cilium installation, Cilium health, cross-node endpoint and ClusterIP service tests, Cilium service-table inspection, Hubble flow checks, and the NetworkPolicy test:

```bash
scripts/cilium-install-verify.sh oke_cilium_chaining
```

The command writes a timestamped log under `validation-results/` and finishes with a concise PASS or FAIL summary. Use `--verify-only` to rerun health and tests without applying Terraform, or `--plan-only` to review the Cilium Terraform plan. The top-level `deploy-and-validate.sh` calls this same wrapper after completing OKE provisioning and cluster access.

When the kubeconfig context differs from the cluster key in the tfvars file, pass the target key explicitly:

```bash
TARGET_CLUSTER_NAME=oke_cilium_chaining \
  scripts/cilium-install-verify.sh oke_cilium_chaining_live
```

To perform the same installation stages manually, create the chained CNI ConfigMap and then apply the Cilium stack:

```bash
scripts/apply-oci-cilium-chaining-config.sh oke_cilium_chaining

terraform -chdir=stacks/03-cilium init
terraform -chdir=stacks/03-cilium workspace select oke_cilium_chaining || \
  terraform -chdir=stacks/03-cilium workspace new oke_cilium_chaining
terraform -chdir=stacks/03-cilium apply \
  -var-file=../../envs/oke-vcn-native-cilium-chaining.tfvars \
  -var="target_cluster_name=oke_cilium_chaining"
```

## Validate

The combined validation can be rerun without changing the installation:

```bash
scripts/cilium-install-verify.sh oke_cilium_chaining --verify-only
```

Run the individual proof points when you want separate namespaces and outputs for troubleshooting or demonstrations:

```bash
scripts/pod-connectivity-test.sh oke_cilium_chaining
scripts/cilium-smoke-test.sh oke_cilium_chaining
scripts/cilium-policy-test.sh oke_cilium_chaining
```

The validation scripts accept the kubeconfig context as the first argument and an optional namespace as the second argument. They create timestamped namespaces when a namespace is not supplied.

| Script | What it validates |
| --- | --- |
| `pod-connectivity-test.sh` | Base OCI VCN-native pod IP allocation and cross-node pod-to-pod routing. |
| `cilium-smoke-test.sh` | Cross-node pod-IP, ClusterIP, and service-DNS traffic after chaining; Cilium endpoint and service-table state; and a forwarded Hubble flow. |
| `cilium-policy-test.sh` | Kubernetes NetworkPolicy allow/deny enforcement plus a Hubble policy-denial flow while pods keep VCN-native IPs. |

The smoke test uses a backend pod on one worker and a client pod on another. Because the baseline keeps `kubeProxyReplacement=false` and retains `kube-proxy`, the ClusterIP result proves that Kubernetes Service connectivity works in the composed OKE and Cilium design. The service-table output proves that Cilium has learned the Service; it does not claim that Cilium exclusively owns Service forwarding.

The wrappers retain complete command output under `validation-results/` and finish with a compact summary containing separate PASS or FAIL results for cross-node pod traffic, ClusterIP and DNS traffic, Cilium service visibility, Hubble flow visibility, and NetworkPolicy enforcement.

To override the validation images or Cilium namespace for one run, pass them to the command:

```bash
SERVER_IMAGE=registry.k8s.io/e2e-test-images/agnhost:2.45 \
CLIENT_IMAGE=registry.k8s.io/e2e-test-images/busybox:1.29-4 \
CILIUM_NS=kube-system \
  scripts/cilium-install-verify.sh oke_cilium_chaining --verify-only
```

## Optional Gateway API extension

Use `examples/gateway-api` only after the baseline OCI CNI and Cilium chaining model is healthy. Cilium Gateway API requires kube-proxy replacement and must be validated separately from the conservative baseline. The extension README identifies the required Gateway API CRDs and Terraform-managed Cilium settings.

Gateway API was not enabled in the baseline validation environment. Cilium documents that some advanced features, including Layer 7 policy, can be limited in generic-veth chaining mode. Treat the manifests as an optional validation path, not as part of the proven baseline.

## Clean up

The recommended cleanup command deletes validation namespaces, destroys Cilium, removes the chaining ConfigMap, restores the original subnet security-list associations, and then destroys the OKE stack:

```bash
scripts/destroy-all.sh oke_cilium_chaining --plan-only
scripts/destroy-all.sh oke_cilium_chaining --confirm DESTROY
```

The script does not destroy the prerequisite VCN by default because the sample normally references an existing network. When the deployment used `--provision-network`, preview and delete the sample-owned network explicitly:

```bash
scripts/destroy-all.sh oke_cilium_chaining \
  --plan-only \
  --destroy-network

scripts/destroy-all.sh oke_cilium_chaining \
  --confirm DESTROY \
  --destroy-network
```

The cleanup refuses network deletion unless `stacks/00-network` contains Terraform state for the VCN. `--network-stack` and `--network-tfvars` remain available only as advanced overrides.

After deleting a sample-owned disposable network, rerun `scripts/deploy-and-validate.sh --provision-network` to recreate it. For enterprise mode, provide another compatible existing VCN and update the OKE tfvars before rerunning the deployment.

When the kubeconfig context is an alias, keep the tfvars cluster key explicit:

```bash
TARGET_CLUSTER_NAME=oke_cilium_chaining \
  scripts/destroy-all.sh oke_cilium_chaining_live --confirm DESTROY
```

The following commands show the equivalent manual order.

Delete all namespaces created by the validation and Gateway API examples:

```bash
kubectl --context oke_cilium_chaining delete namespace \
  -l oke-cilium-sample=true
```

Destroy Cilium before the OKE cluster:

```bash
terraform -chdir=stacks/03-cilium destroy \
  -var-file=../../envs/oke-vcn-native-cilium-chaining.tfvars \
  -var="target_cluster_name=oke_cilium_chaining"

kubectl --context oke_cilium_chaining -n kube-system delete configmap \
  cilium-chaining-config --ignore-not-found
```

If `generated/attach-security-lists.sh` was run, review and execute `generated/detach-security-lists.sh` before destroying `stacks/01-oke`. Then destroy the cluster stack:

```bash
sed -n '1,240p' generated/detach-security-lists.sh
generated/detach-security-lists.sh

terraform -chdir=stacks/01-oke destroy \
  -var-file=../../envs/oke-vcn-native-cilium-chaining.tfvars
```

## Contributing

This project welcomes contributions. Before submitting a pull request, review
[CONTRIBUTING.md](CONTRIBUTING.md), including the Oracle Contributor Agreement
and sign-off requirements.

## Security

Do not report suspected vulnerabilities through public repository issues. See
[SECURITY.md](SECURITY.md) for Oracle's responsible disclosure process.

## License

Copyright (c) 2026 Oracle and/or its affiliates.

Released under the Universal Permissive License v1.0 as shown at
<https://oss.oracle.com/licenses/upl/>. See [LICENSE.txt](LICENSE.txt).

The external tools, providers, charts, and images referenced by this sample are
listed in [THIRD_PARTY_LICENSES.txt](THIRD_PARTY_LICENSES.txt). The required
Cilium Apache 2.0 license text is included in
[CILIUM_LICENSE.txt](CILIUM_LICENSE.txt); keep both files with distributed
copies of this sample.

## Disclaimer

ORACLE AND ITS AFFILIATES DO NOT PROVIDE ANY WARRANTY WHATSOEVER, EXPRESS OR
IMPLIED, FOR ANY SOFTWARE, MATERIAL OR CONTENT OF ANY KIND CONTAINED OR
PRODUCED WITHIN THIS REPOSITORY, AND IN PARTICULAR SPECIFICALLY DISCLAIM ANY
AND ALL IMPLIED WARRANTIES OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY, AND
FITNESS FOR A PARTICULAR PURPOSE. FURTHERMORE, ORACLE AND ITS AFFILIATES DO NOT
REPRESENT THAT ANY CUSTOMARY SECURITY REVIEW HAS BEEN PERFORMED WITH RESPECT TO
ANY SOFTWARE, MATERIAL OR CONTENT CONTAINED OR PRODUCED WITHIN THIS REPOSITORY.
IN ADDITION, AND WITHOUT LIMITING THE FOREGOING, THIRD PARTIES MAY HAVE POSTED
SOFTWARE, MATERIAL OR CONTENT TO THIS REPOSITORY WITHOUT ANY REVIEW. USE AT
YOUR OWN RISK.
