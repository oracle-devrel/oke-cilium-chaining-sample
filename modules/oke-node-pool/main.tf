# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Provisions a managed node pool with OCI VCN-native pod-network options.

locals {
  cni_type = upper(var.cni_type)

  node_pool_name = coalesce(try(var.node_pool.name, null), "${var.cluster_name}-${var.node_pool_key}")

  imds_metadata = try(var.node_pool.imds_v1_disabled, true) ? {
    areLegacyImdsEndpointsDisabled = "true"
  } : {}

  node_metadata = merge(
    try(var.node_pool.metadata, {}),
    local.imds_metadata
  )

  labels = try(var.node_pool.labels, {})
}

resource "oci_containerengine_node_pool" "this" {
  cluster_id         = var.cluster_id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = local.node_pool_name
  node_shape         = var.node_pool.shape
  node_metadata      = local.node_metadata
  ssh_public_key     = try(var.node_pool.ssh_public_key, null)

  dynamic "initial_node_labels" {
    for_each = local.labels

    content {
      key   = initial_node_labels.key
      value = initial_node_labels.value
    }
  }

  node_config_details {
    size    = var.node_pool.size
    nsg_ids = var.worker_nsg_ids

    dynamic "placement_configs" {
      for_each = var.placement_configs

      content {
        availability_domain = placement_configs.value.availability_domain
        subnet_id           = placement_configs.value.subnet_id
        fault_domains       = placement_configs.value.fault_domains
      }
    }

    node_pool_pod_network_option_details {
      cni_type          = local.cni_type
      max_pods_per_node = local.cni_type == "OCI_VCN_IP_NATIVE" ? try(var.node_pool.max_pods_per_node, null) : null
      pod_nsg_ids       = local.cni_type == "OCI_VCN_IP_NATIVE" ? var.pod_nsg_ids : null
      pod_subnet_ids    = local.cni_type == "OCI_VCN_IP_NATIVE" ? var.pod_subnet_ids : null
    }
  }

  dynamic "node_shape_config" {
    for_each = try(var.node_pool.ocpus, null) != null || try(var.node_pool.memory_gb, null) != null ? [1] : []

    content {
      ocpus         = try(var.node_pool.ocpus, null)
      memory_in_gbs = try(var.node_pool.memory_gb, null)
    }
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = var.resolved_image_id
    boot_volume_size_in_gbs = try(var.node_pool.boot_volume_size_gb, null) == null ? null : tostring(var.node_pool.boot_volume_size_gb)
  }

  freeform_tags = merge(
    {
      "managed-by" = "terraform"
      "stack"      = "oke-cilium"
      "cluster"    = var.cluster_name
    },
    try(var.node_pool.freeform_tags, {})
  )

  lifecycle {
    precondition {
      condition     = contains(["FLANNEL_OVERLAY", "OCI_VCN_IP_NATIVE"], local.cni_type)
      error_message = "Node pool cni_type must be FLANNEL_OVERLAY or OCI_VCN_IP_NATIVE."
    }

    precondition {
      condition     = local.cni_type != "OCI_VCN_IP_NATIVE" || length(var.pod_subnet_ids) > 0
      error_message = "OCI_VCN_IP_NATIVE node pools require at least one pod subnet."
    }
  }
}
