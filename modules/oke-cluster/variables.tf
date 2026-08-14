# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

variable "cluster_name" {
  type = string
}

variable "config" {
  type = any
}

variable "compartment_id" {
  type = string

  validation {
    condition     = try(trimspace(var.compartment_id), "") != ""
    error_message = "compartment_id must resolve to a non-empty OCID. Check compartment_id or compartment_name."
  }
}

variable "vcn_id" {
  type = string

  validation {
    condition     = try(trimspace(var.vcn_id), "") != ""
    error_message = "vcn_id must resolve to a non-empty OCID. Check vcn_id or vcn_name."
  }
}

variable "endpoint_subnet_id" {
  type = string

  validation {
    condition     = try(trimspace(var.endpoint_subnet_id), "") != ""
    error_message = "endpoint_subnet_id must resolve to a non-empty OCID. Check endpoint_subnet_id or endpoint_subnet_name."
  }
}

variable "endpoint_nsg_ids" {
  type    = list(string)
  default = []
}

variable "service_lb_subnet_ids" {
  type    = list(string)
  default = []
}

variable "lb_backend_nsg_ids" {
  type    = list(string)
  default = []
}
