# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

variable "cluster_name" {
  type = string
}

variable "node_pool_key" {
  type = string
}

variable "node_pool" {
  type = any
}

variable "cluster_id" {
  type = string

  validation {
    condition     = try(trimspace(var.cluster_id), "") != ""
    error_message = "cluster_id must resolve to a non-empty OCID."
  }
}

variable "compartment_id" {
  type = string

  validation {
    condition     = try(trimspace(var.compartment_id), "") != ""
    error_message = "compartment_id must resolve to a non-empty OCID. Check compartment_id or compartment_name."
  }
}

variable "kubernetes_version" {
  type = string
}

variable "cni_type" {
  type = string
}

variable "worker_subnet_id" {
  type = string

  validation {
    condition     = try(trimspace(var.worker_subnet_id), "") != ""
    error_message = "worker_subnet_id must resolve to a non-empty OCID. Check worker_subnet_id or worker_subnet_name."
  }
}

variable "worker_nsg_ids" {
  type    = list(string)
  default = []
}

variable "resolved_image_id" {
  type = string

  validation {
    condition     = try(trimspace(var.resolved_image_id), "") != ""
    error_message = "resolved_image_id must be a non-empty OKE worker image OCID. Set node_pools.<name>.image_id, or set image_name/image_name_pattern so the node-pool stack can resolve one from OKE node pool options."
  }
}

variable "pod_subnet_ids" {
  type    = list(string)
  default = []
}

variable "pod_nsg_ids" {
  type    = list(string)
  default = []
}

variable "placement_configs" {
  type = list(object({
    availability_domain = string
    subnet_id           = string
    fault_domains       = list(string)
  }))
}
