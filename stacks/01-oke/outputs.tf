# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

output "attach_instructions" {
  value = {
    warning        = "The commands update existing subnet security_list_ids. This mutates existing subnets and can cause drift or conflicts if those subnets are managed by another Terraform state. Review the generated script before running it."
    restore_note   = "Run restore_script before destroying this stack if attach_script was executed."
    run_order      = local.attach_run_order
    attach_script  = local_file.attach_security_lists.filename
    restore_script = local_file.detach_security_lists.filename
    by_cluster     = local.attach_commands_by_cluster
  }
}

output "cluster_ids" {
  value = {
    for name, cluster in module.clusters : name => cluster.id
  }
}

output "region" {
  description = "OCI region used by this stack."
  value       = var.region
}

output "cluster_cni_types" {
  value = {
    for name, cluster in module.clusters : name => cluster.cni_type
  }
}

output "cluster_endpoints" {
  value = {
    for name, cluster in module.clusters : name => cluster.endpoints
  }
}

output "node_pool_ids" {
  value = {
    for key, node_pool in module.node_pools : key => node_pool.id
  }
}

output "node_pool_cni_types" {
  value = {
    for key, node_pool in module.node_pools : key => node_pool.cni_type
  }
}

output "resolved_network" {
  value = {
    for name, lookup in module.lookup : name => {
      compartment_id     = lookup.compartment_id
      vcn_id             = lookup.vcn_id
      endpoint_subnet_id = lookup.endpoint_subnet_id
      worker_subnet_id   = lookup.worker_subnet_id
      pod_subnet_id      = lookup.pod_subnet_id
      lb_subnet_id       = lookup.lb_subnet_id
      subnet_cidrs       = lookup.resolved_subnet_cidrs
    }
  }
}

output "resolved_node_pool_images" {
  value = {
    for key, image_name in local.resolved_image_names : key => {
      image_name = image_name
      os_arch    = local.node_pool_os_arch[key]
    }
  }
}
