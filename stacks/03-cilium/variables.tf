# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

variable "clusters" {
  type = any
}

variable "target_cluster_name" {
  description = "Install Cilium only for this cluster."
  type        = string
}

variable "kubeconfig_path" {
  type    = string
  default = null
}

variable "kube_context" {
  description = "Optional override. Defaults to clusters[target_cluster_name].cilium.kube_context, then target_cluster_name."
  type        = string
  default     = null
}

# Accepted by the shared tfvars file but not used in this stack.
variable "region" {
  type    = string
  default = null
}

variable "tenancy_id" {
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

variable "compartment_lookup_in_subtree" {
  type    = bool
  default = null
}
