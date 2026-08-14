# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N

variable "region" {
  description = "OCI region for the disposable reference network."
  type        = string
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

variable "compartment_id" {
  description = "Compartment OCID in which the disposable network is created."
  type        = string

  validation {
    condition     = try(startswith(var.compartment_id, "ocid1.compartment."), false)
    error_message = "compartment_id must be set to a valid OCI compartment OCID."
  }
}

variable "vcn_name" {
  description = "Display name referenced by the OKE sample tfvars."
  type        = string
}

variable "vcn_cidr" {
  description = "IPv4 CIDR for the disposable VCN."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vcn_cidr))
    error_message = "vcn_cidr must be a valid IPv4 CIDR."
  }
}

variable "vcn_dns_label" {
  description = "DNS label for the disposable VCN."
  type        = string
}

variable "api_endpoint_source_cidrs" {
  description = "Optional source CIDRs allowed to reach TCP/6443 during network bootstrap."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.api_endpoint_source_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every api_endpoint_source_cidrs value must be a valid IPv4 CIDR."
  }
}

variable "subnets" {
  description = "Endpoint, worker, pod, and load-balancer subnets referenced by the OKE sample tfvars."
  type = map(object({
    cidr_block = string
    dns_label  = string
    private    = bool
    route_type = string
  }))

  validation {
    condition     = length(var.subnets) >= 3
    error_message = "Define at least endpoint, worker, and pod subnets."
  }

  validation {
    condition     = alltrue([for subnet in values(var.subnets) : can(cidrnetmask(subnet.cidr_block))])
    error_message = "Every subnet cidr_block must be a valid IPv4 CIDR."
  }

  validation {
    condition     = alltrue([for subnet in values(var.subnets) : contains(["public", "private"], subnet.route_type)])
    error_message = "Every subnet route_type must be public or private."
  }
}
