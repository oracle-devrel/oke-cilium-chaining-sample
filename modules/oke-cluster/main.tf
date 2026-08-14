# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Provisions one OKE cluster with the selected pod-network type.

locals {
  cluster  = try(var.config.cluster, {})
  cni_type = upper(try(local.cluster.cni_type, "FLANNEL_OVERLAY"))
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_id
  kubernetes_version = var.config.kubernetes_version
  name               = var.cluster_name
  vcn_id             = var.vcn_id
  type               = try(local.cluster.type, "ENHANCED_CLUSTER")

  cluster_pod_network_options {
    cni_type = local.cni_type
  }

  endpoint_config {
    is_public_ip_enabled = try(local.cluster.public_endpoint, false)
    nsg_ids              = var.endpoint_nsg_ids
    subnet_id            = var.endpoint_subnet_id
  }

  options {
    kubernetes_network_config {
      pods_cidr     = try(local.cluster.pod_cidr, null)
      services_cidr = try(local.cluster.service_cidr, null)
    }

    service_lb_subnet_ids = var.service_lb_subnet_ids

    service_lb_config {
      backend_nsg_ids = var.lb_backend_nsg_ids
    }
  }

  image_policy_config {
    is_policy_enabled = try(local.cluster.image_policy_enabled, false)
  }

  freeform_tags = merge(
    {
      "managed-by" = "terraform"
      "stack"      = "oke-cilium"
    },
    try(var.config.freeform_tags, {})
  )

  lifecycle {
    precondition {
      condition     = contains(["FLANNEL_OVERLAY", "OCI_VCN_IP_NATIVE"], local.cni_type)
      error_message = "cluster.cni_type must be FLANNEL_OVERLAY or OCI_VCN_IP_NATIVE."
    }
  }
}
