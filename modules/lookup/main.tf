# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Resolves existing OCI compartments, VCNs, subnets, and NSGs by ID or name.

locals {
  compartment_id_input   = try(trimspace(var.compartment_id), "") != "" ? trimspace(var.compartment_id) : null
  compartment_name_input = try(trimspace(var.compartment_name), "") != "" ? trimspace(var.compartment_name) : null
  vcn_id_input           = try(trimspace(var.vcn_id), "") != "" ? trimspace(var.vcn_id) : null
  vcn_name_input         = try(trimspace(var.vcn_name), "") != "" ? trimspace(var.vcn_name) : null
}

data "oci_identity_compartments" "selected" {
  count = local.compartment_id_input == null ? 1 : 0

  compartment_id            = coalesce(var.compartment_lookup_parent_id, var.tenancy_id)
  compartment_id_in_subtree = var.compartment_lookup_in_subtree
  access_level              = "ACCESSIBLE"
  name                      = local.compartment_name_input
  state                     = "ACTIVE"
}

locals {
  compartment_id = local.compartment_id_input != null ? local.compartment_id_input : one(data.oci_identity_compartments.selected[0].compartments[*].id)
}

data "oci_core_vcns" "selected" {
  count = local.vcn_id_input == null ? 1 : 0

  compartment_id = local.compartment_id
  display_name   = local.vcn_name_input
  state          = "AVAILABLE"
}

locals {
  vcn_id = local.vcn_id_input != null ? local.vcn_id_input : one(data.oci_core_vcns.selected[0].virtual_networks[*].id)

  subnet_ids = {
    endpoint = try(trimspace(var.network.endpoint_subnet_id), "") != "" ? trimspace(var.network.endpoint_subnet_id) : null
    worker   = try(trimspace(var.network.worker_subnet_id), "") != "" ? trimspace(var.network.worker_subnet_id) : null
    pod      = try(trimspace(var.network.pod_subnet_id), "") != "" ? trimspace(var.network.pod_subnet_id) : null
    lb       = try(trimspace(var.network.lb_subnet_id), "") != "" ? trimspace(var.network.lb_subnet_id) : null
  }

  subnet_names = {
    endpoint = try(trimspace(var.network.endpoint_subnet_name), "") != "" ? trimspace(var.network.endpoint_subnet_name) : null
    worker   = try(trimspace(var.network.worker_subnet_name), "") != "" ? trimspace(var.network.worker_subnet_name) : null
    pod      = try(trimspace(var.network.pod_subnet_name), "") != "" ? trimspace(var.network.pod_subnet_name) : null
    lb       = try(trimspace(var.network.lb_subnet_name), "") != "" ? trimspace(var.network.lb_subnet_name) : null
  }

  nsg_ids = {
    endpoint = compact([for id in coalesce(try(var.network.endpoint_nsg_ids, null), []) : try(trimspace(id), "")])
    worker   = compact([for id in coalesce(try(var.network.worker_nsg_ids, null), []) : try(trimspace(id), "")])
    pod      = compact([for id in coalesce(try(var.network.pod_nsg_ids, null), []) : try(trimspace(id), "")])
    lb       = compact([for id in coalesce(try(var.network.lb_nsg_ids, null), []) : try(trimspace(id), "")])
    backend  = compact([for id in coalesce(try(var.network.lb_backend_nsg_ids, null), []) : try(trimspace(id), "")])
  }

  nsg_names = {
    endpoint = compact([for name in coalesce(try(var.network.endpoint_nsg_names, null), []) : try(trimspace(name), "")])
    worker   = compact([for name in coalesce(try(var.network.worker_nsg_names, null), []) : try(trimspace(name), "")])
    pod      = compact([for name in coalesce(try(var.network.pod_nsg_names, null), []) : try(trimspace(name), "")])
    lb       = compact([for name in coalesce(try(var.network.lb_nsg_names, null), []) : try(trimspace(name), "")])
    backend  = compact([for name in coalesce(try(var.network.lb_backend_nsg_names, null), []) : try(trimspace(name), "")])
  }

  subnet_lookup_names = {
    for key, name in local.subnet_names : key => name
    if local.subnet_ids[key] == null && name != null
  }

  all_nsg_names = toset(distinct(concat(
    local.nsg_names.endpoint,
    local.nsg_names.worker,
    local.nsg_names.pod,
    local.nsg_names.lb,
    local.nsg_names.backend
  )))
}

data "oci_core_subnets" "selected" {
  for_each = local.subnet_lookup_names

  compartment_id = local.compartment_id
  vcn_id         = local.vcn_id
  display_name   = each.value
  state          = "AVAILABLE"
}

data "oci_core_network_security_groups" "selected" {
  for_each = local.all_nsg_names

  compartment_id = local.compartment_id
  vcn_id         = local.vcn_id
  display_name   = each.key
  state          = "AVAILABLE"
}

locals {
  subnet_id_by_role = {
    for role in keys(local.subnet_names) :
    role => local.subnet_ids[role] != null ? local.subnet_ids[role] : try(one(data.oci_core_subnets.selected[role].subnets[*].id), null)
  }

  subnet_cidr_by_role = {
    for role in keys(local.subnet_names) :
    role => try(one(data.oci_core_subnets.selected[role].subnets[*].cidr_block), null)
  }

  nsg_id_by_name = {
    for name, nsgs in data.oci_core_network_security_groups.selected :
    name => one(nsgs.network_security_groups[*].id)
  }

  endpoint_nsg_ids   = distinct(concat(local.nsg_ids.endpoint, [for name in local.nsg_names.endpoint : local.nsg_id_by_name[name]]))
  worker_nsg_ids     = distinct(concat(local.nsg_ids.worker, [for name in local.nsg_names.worker : local.nsg_id_by_name[name]]))
  pod_nsg_ids        = distinct(concat(local.nsg_ids.pod, [for name in local.nsg_names.pod : local.nsg_id_by_name[name]]))
  lb_nsg_ids         = distinct(concat(local.nsg_ids.lb, [for name in local.nsg_names.lb : local.nsg_id_by_name[name]]))
  lb_backend_nsg_ids = distinct(concat(local.nsg_ids.backend, [for name in local.nsg_names.backend : local.nsg_id_by_name[name]]))
}
