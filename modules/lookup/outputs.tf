# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

output "compartment_id" {
  value = local.compartment_id
}

output "vcn_id" {
  value = local.vcn_id
}

output "endpoint_subnet_id" {
  value = local.subnet_id_by_role.endpoint
}

output "worker_subnet_id" {
  value = local.subnet_id_by_role.worker
}

output "pod_subnet_id" {
  value = local.subnet_id_by_role.pod
}

output "lb_subnet_id" {
  value = local.subnet_id_by_role.lb
}

output "endpoint_nsg_ids" {
  value = local.endpoint_nsg_ids
}

output "worker_nsg_ids" {
  value = local.worker_nsg_ids
}

output "pod_nsg_ids" {
  value = local.pod_nsg_ids
}

output "lb_nsg_ids" {
  value = local.lb_nsg_ids
}

output "lb_backend_nsg_ids" {
  value = local.lb_backend_nsg_ids
}

output "resolved_subnet_cidrs" {
  value = local.subnet_cidr_by_role
}
