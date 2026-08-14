# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Creates role-specific security lists for OKE API, worker, pod, and load-balancer subnets.

locals {
  endpoint_cidr = try(var.subnet_cidrs.endpoint, null)
  worker_cidr   = try(var.subnet_cidrs.worker, null)
  pod_cidr      = try(var.subnet_cidrs.pod, null)
  lb_cidr       = try(var.subnet_cidrs.lb, null)
  service_cidr  = try(var.cluster_config.cluster.service_cidr, null)

  has_endpoint = try(trimspace(local.endpoint_cidr), "") != ""
  has_worker   = try(trimspace(local.worker_cidr), "") != ""
  has_pod      = try(trimspace(local.pod_cidr), "") != ""
  has_lb       = try(trimspace(local.lb_cidr), "") != ""

  common_tags = {
    "managed-by" = "terraform"
    "stack"      = "oke-cilium-security-lists"
    "cluster"    = var.cluster_name
  }
}

resource "oci_core_security_list" "endpoint" {
  count = local.has_endpoint ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.cluster_name}-endpoint-sl"

  dynamic "ingress_security_rules" {
    for_each = var.admin_source_cidrs
    content {
      protocol    = "6"
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = local.worker_cidr
    source_type = "CIDR_BLOCK"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = local.worker_cidr
    source_type = "CIDR_BLOCK"
    tcp_options {
      min = 12250
      max = 12250
    }
  }

  egress_security_rules {
    protocol         = "all"
    destination      = local.worker_cidr
    destination_type = "CIDR_BLOCK"
  }

  freeform_tags = merge(local.common_tags, {
    "role" = "endpoint"
  })
}

resource "oci_core_security_list" "worker" {
  count = local.has_worker ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.cluster_name}-worker-sl"

  ingress_security_rules {
    protocol    = "all"
    source      = local.worker_cidr
    source_type = "CIDR_BLOCK"
  }

  dynamic "ingress_security_rules" {
    for_each = local.has_pod ? [local.pod_cidr] : []
    content {
      protocol    = "all"
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
    }
  }

  dynamic "ingress_security_rules" {
    for_each = local.has_endpoint ? [local.endpoint_cidr] : []
    content {
      protocol    = "all"
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
    }
  }

  dynamic "ingress_security_rules" {
    for_each = local.has_lb ? [local.lb_cidr] : []
    content {
      protocol    = "6"
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      tcp_options {
        min = var.nodeport_min
        max = var.nodeport_max
      }
    }
  }

  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
  }

  freeform_tags = merge(local.common_tags, {
    "role" = "worker"
  })
}

resource "oci_core_security_list" "pod" {
  count = local.has_pod ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.cluster_name}-pod-sl"

  ingress_security_rules {
    protocol    = "all"
    source      = local.pod_cidr
    source_type = "CIDR_BLOCK"
  }

  ingress_security_rules {
    protocol    = "all"
    source      = local.worker_cidr
    source_type = "CIDR_BLOCK"
  }

  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
  }

  freeform_tags = merge(local.common_tags, {
    "role" = "pod"
  })
}

resource "oci_core_security_list" "lb" {
  count = local.has_lb ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.cluster_name}-lb-sl"

  dynamic "ingress_security_rules" {
    for_each = flatten([
      for cidr in var.lb_source_cidrs : [
        for port in var.lb_ingress_ports : {
          cidr = cidr
          port = port
        }
      ]
    ])
    content {
      protocol    = "6"
      source      = ingress_security_rules.value.cidr
      source_type = "CIDR_BLOCK"
      tcp_options {
        min = ingress_security_rules.value.port
        max = ingress_security_rules.value.port
      }
    }
  }

  egress_security_rules {
    protocol         = "6"
    destination      = local.worker_cidr
    destination_type = "CIDR_BLOCK"
    tcp_options {
      min = var.nodeport_min
      max = var.nodeport_max
    }
  }

  freeform_tags = merge(local.common_tags, {
    "role" = "lb"
  })
}
