<!-- Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved. -->
<!-- Author: Ulaganathan N -->

# Cilium Gateway API extension

These manifests provide an optional Gateway API extension to the baseline sample.

Use them only after the base OCI VCN-native CNI and Cilium chaining model is working. Cilium Gateway API requires Cilium kube-proxy replacement and should be validated as a separate extension to the conservative chaining baseline.

The baseline `deploy-and-validate.sh` workflow does not apply or validate these manifests.

Before applying the manifests, install `curl`, install the Gateway API CRDs, enable `gatewayAPI.enabled=true` and `kubeProxyReplacement=true` through the Terraform state that owns the Cilium Helm release, and verify that the `cilium` GatewayClass is accepted. Do not use an unmanaged Helm upgrade on a Terraform-managed release.

```bash
CONTEXT=oke_cilium_chaining

kubectl --context "$CONTEXT" create namespace gateway-demo
kubectl --context "$CONTEXT" label namespace gateway-demo \
  oke-cilium-sample=true oke-cilium-test=gateway-api
kubectl --context "$CONTEXT" -n gateway-demo create deployment web \
  --image=nginxinc/nginx-unprivileged:1.27-alpine
kubectl --context "$CONTEXT" -n gateway-demo expose deployment web \
  --port=80 \
  --target-port=8080

kubectl --context "$CONTEXT" apply -f examples/gateway-api/web-gateway.yaml

GATEWAY_ADDRESS=$(kubectl --context "$CONTEXT" -n gateway-demo \
  get gateway web-gateway \
  -o jsonpath='{.status.addresses[0].value}')

curl -i "http://${GATEWAY_ADDRESS}/"

kubectl --context "$CONTEXT" apply \
  -f examples/gateway-api/allow-gateway-to-web.yaml
curl -i "http://${GATEWAY_ADDRESS}/"
curl -i -X POST "http://${GATEWAY_ADDRESS}/"
```
