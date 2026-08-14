# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Installs Cilium through the Terraform Helm provider after OKE is reachable.

locals {
  target_config = var.clusters[var.target_cluster_name]

  explicit_kubeconfig_path = try(trimspace(var.kubeconfig_path), "")
  nested_kubeconfig_path   = try(trimspace(local.target_config.cilium.kubeconfig_path), "")
  kubeconfig_path          = local.explicit_kubeconfig_path != "" ? local.explicit_kubeconfig_path : local.nested_kubeconfig_path != "" ? local.nested_kubeconfig_path : "~/.kube/config"

  explicit_kube_context = try(trimspace(var.kube_context), "")
  nested_kube_context   = try(trimspace(local.target_config.cilium.kube_context), "")
  kube_context          = local.explicit_kube_context != "" ? local.explicit_kube_context : local.nested_kube_context != "" ? local.nested_kube_context : var.target_cluster_name
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand(local.kubeconfig_path)
    config_context = local.kube_context
  }
}

module "cilium" {
  source = "../../modules/cilium-helm"
  count  = try(local.target_config.cilium.enabled, true) ? 1 : 0

  cluster_name = var.target_cluster_name
  cilium       = local.target_config.cilium
}
