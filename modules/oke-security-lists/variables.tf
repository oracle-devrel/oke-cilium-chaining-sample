# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

variable "cluster_name" {
  type = string
}

variable "compartment_id" {
  type = string
}

variable "vcn_id" {
  type = string
}

variable "cluster_config" {
  type = any
}

variable "subnet_cidrs" {
  type = object({
    endpoint = optional(string)
    worker   = optional(string)
    pod      = optional(string)
    lb       = optional(string)
  })
}

variable "admin_source_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint."
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
