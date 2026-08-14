# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

variable "region" {
  type = string
}

variable "tenancy_id" {
  type    = string
  default = null
}

variable "tenancy_ocid" {
  type    = string
  default = null
}

variable "user_ocid" {
  type    = string
  default = null
}

variable "fingerprint" {
  type    = string
  default = null
}

variable "private_key_path" {
  type    = string
  default = null
}

variable "oci_config_profile" {
  type    = string
  default = null
}

variable "oci_auth" {
  type    = string
  default = null
}

variable "compartment_lookup_in_subtree" {
  type    = bool
  default = true
}

variable "admin_source_cidrs" {
  description = "CIDRs allowed to reach public Kubernetes API endpoints."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.admin_source_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every admin_source_cidrs value must be a valid IPv4 CIDR."
  }
}

variable "lb_source_cidrs" {
  description = "CIDRs allowed to reach public load balancers."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.lb_source_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every lb_source_cidrs value must be a valid IPv4 CIDR."
  }
}

variable "lb_ingress_ports" {
  description = "Load balancer listener ports to allow from lb_source_cidrs."
  type        = list(number)
  default     = [80, 443]
}

variable "nodeport_min" {
  type    = number
  default = 30000
}

variable "nodeport_max" {
  type    = number
  default = 32767
}

variable "attach_script_path" {
  description = "Path for the generated security-list attach script. Defaults to generated/attach-security-lists.sh in the repository."
  type        = string
  default     = null
}

variable "detach_script_path" {
  description = "Path for the generated security-list restore script. Defaults to generated/detach-security-lists.sh in the repository."
  type        = string
  default     = null
}

variable "clusters" {
  description = "Map of cluster configurations. See envs/oke-vcn-native-cilium-chaining.tfvars.example."
  type        = any

  validation {
    condition = alltrue([
      for _, cluster in var.clusters :
      try(startswith(cluster.compartment_id, "ocid1.compartment."), false) ||
      try(trimspace(cluster.compartment_name) != "", false)
    ])
    error_message = "Each cluster must set a valid compartment_id OCID or a non-empty compartment_name."
  }

  validation {
    condition = alltrue([
      for _, cluster in var.clusters :
      !try(cluster.security_lists.enabled, true) ||
      !try(cluster.cluster.public_endpoint, true) ||
      (
        length(try(cluster.security_lists.admin_source_cidrs, var.admin_source_cidrs)) > 0 &&
        alltrue([
          for cidr in try(cluster.security_lists.admin_source_cidrs, var.admin_source_cidrs) :
          can(cidrnetmask(cidr))
        ])
      )
    ])
    error_message = "A public endpoint using generated security lists requires at least one valid admin_source_cidrs entry."
  }
}
