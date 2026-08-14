# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

variable "tenancy_id" {
  description = "Tenancy OCID. Used as the default parent for compartment name lookup."
  type        = string
  default     = null
}

variable "compartment_id" {
  description = "Compartment OCID. If set, compartment_name is ignored."
  type        = string
  default     = null
}

variable "compartment_name" {
  description = "Compartment name to resolve when compartment_id is not set."
  type        = string
  default     = null
}

variable "compartment_lookup_parent_id" {
  description = "Parent compartment OCID for compartment name lookup. Defaults to tenancy_id."
  type        = string
  default     = null
}

variable "compartment_lookup_in_subtree" {
  description = "Search all subcompartments when resolving compartment_name."
  type        = bool
  default     = true
}

variable "vcn_id" {
  description = "VCN OCID. If set, vcn_name is ignored."
  type        = string
  default     = null
}

variable "vcn_name" {
  description = "VCN display name to resolve when vcn_id is not set."
  type        = string
  default     = null
}

variable "network" {
  description = "Cluster network map. Each resource can be supplied by OCID or by display name."
  type        = any
}
