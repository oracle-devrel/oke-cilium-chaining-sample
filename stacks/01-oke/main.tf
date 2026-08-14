# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Provisions the OKE cluster, VCN-native node pool, and network security lists.

provider "oci" {
  region              = var.region
  config_file_profile = var.oci_config_profile
  auth                = var.oci_auth
  tenancy_ocid        = var.tenancy_ocid
  user_ocid           = var.user_ocid
  fingerprint         = var.fingerprint
  private_key_path    = var.private_key_path
}

locals {
  lookup_parent_tenancy_id = (
    try(trimspace(var.tenancy_id), "") != "" ? trimspace(var.tenancy_id) :
    try(trimspace(var.tenancy_ocid), "") != "" ? trimspace(var.tenancy_ocid) :
    null
  )

  subnet_roles = ["endpoint", "worker", "pod", "lb"]
}

module "lookup" {
  source   = "../../modules/lookup"
  for_each = var.clusters

  tenancy_id                    = local.lookup_parent_tenancy_id
  compartment_id                = try(each.value.compartment_id, null)
  compartment_name              = try(each.value.compartment_name, null)
  compartment_lookup_parent_id  = local.lookup_parent_tenancy_id
  compartment_lookup_in_subtree = var.compartment_lookup_in_subtree
  vcn_id                        = try(each.value.vcn_id, null)
  vcn_name                      = try(each.value.vcn_name, null)
  network                       = each.value.network
}

locals {
  subnet_ids_by_cluster = {
    for cluster_name in keys(var.clusters) : cluster_name => {
      endpoint = module.lookup[cluster_name].endpoint_subnet_id
      worker   = module.lookup[cluster_name].worker_subnet_id
      pod      = module.lookup[cluster_name].pod_subnet_id
      lb       = module.lookup[cluster_name].lb_subnet_id
    }
  }

  subnet_refs = merge({}, [
    for cluster_name, subnet_ids in local.subnet_ids_by_cluster : {
      for role, subnet_id in subnet_ids : "${cluster_name}.${role}" => {
        cluster_name = cluster_name
        role         = role
        subnet_id    = subnet_id
      }
      if try(trimspace(subnet_id), "") != ""
    }
  ]...)
}

data "oci_core_subnet" "selected" {
  for_each = local.subnet_refs

  subnet_id = each.value.subnet_id
}

resource "terraform_data" "original_security_list_ids" {
  for_each = local.subnet_refs

  input = sort(data.oci_core_subnet.selected[each.key].security_list_ids)

  lifecycle {
    ignore_changes = [input]
  }
}

data "oci_identity_availability_domains" "ads" {
  for_each = var.clusters

  compartment_id = module.lookup[each.key].compartment_id
}

locals {
  subnet_cidrs_by_cluster = {
    for cluster_name in keys(var.clusters) : cluster_name => {
      for role in local.subnet_roles :
      role => try(data.oci_core_subnet.selected["${cluster_name}.${role}"].cidr_block, null)
    }
  }

  all_availability_domains = {
    for cluster_name, ads in data.oci_identity_availability_domains.ads :
    cluster_name => ads.availability_domains[*].name
  }

  node_pools = merge({}, [
    for cluster_name, cluster in var.clusters : {
      for node_pool_key, node_pool in try(cluster.node_pools, {}) :
      "${cluster_name}.${node_pool_key}" => {
        cluster_name   = cluster_name
        cluster_config = cluster
        node_pool_key  = node_pool_key
        node_pool      = node_pool
      }
    }
  ]...)

  node_pool_os_arch = {
    for key, node_pool in local.node_pools :
    key => (
      try(trimspace(node_pool.node_pool.os_arch), "") != ""
      ? trimspace(node_pool.node_pool.os_arch)
      : can(regex("(^|\\.)A1(\\.|$)", node_pool.node_pool.shape)) ? "AARCH64" : "X86_64"
    )
  }

  node_pool_os_type = {
    for key, node_pool in local.node_pools :
    key => (
      try(trimspace(node_pool.node_pool.os_type), "") != ""
      ? trimspace(node_pool.node_pool.os_type)
      : "OL8"
    )
  }

  node_pool_image_id = {
    for key, node_pool in local.node_pools :
    key => try(trimspace(coalesce(node_pool.node_pool.image_id, "")), "")
  }

  node_pool_image_name = {
    for key, node_pool in local.node_pools :
    key => try(trimspace(coalesce(node_pool.node_pool.image_name, "")), "")
  }

  node_pool_image_name_pattern = {
    for key, node_pool in local.node_pools :
    key => try(trimspace(coalesce(node_pool.node_pool.image_name_pattern, "")), "")
  }

  node_pool_exclude_image_name_pattern = {
    for key, node_pool in local.node_pools :
    key => try(trimspace(coalesce(node_pool.node_pool.exclude_image_name_pattern, "")), "")
  }
}

module "security_lists" {
  source = "../../modules/oke-security-lists"
  for_each = {
    for cluster_name, cluster in var.clusters : cluster_name => cluster
    if try(cluster.security_lists.enabled, true)
  }

  cluster_name   = each.key
  compartment_id = module.lookup[each.key].compartment_id
  vcn_id         = module.lookup[each.key].vcn_id
  cluster_config = each.value
  subnet_cidrs   = local.subnet_cidrs_by_cluster[each.key]

  admin_source_cidrs = try(each.value.security_lists.admin_source_cidrs, var.admin_source_cidrs)
  lb_source_cidrs    = try(each.value.security_lists.lb_source_cidrs, var.lb_source_cidrs)
  lb_ingress_ports   = try(each.value.security_lists.lb_ingress_ports, var.lb_ingress_ports)
  nodeport_min       = try(each.value.security_lists.nodeport_min, var.nodeport_min)
  nodeport_max       = try(each.value.security_lists.nodeport_max, var.nodeport_max)
}

locals {
  security_list_ids_by_subnet = {
    for key, ref in local.subnet_refs :
    key => try(module.security_lists[ref.cluster_name].security_list_ids[ref.role], null)
  }

  attach_security_list_ids = {
    for key, security_list_id in local.security_list_ids_by_subnet :
    key => sort(distinct(concat(data.oci_core_subnet.selected[key].security_list_ids, [security_list_id])))
    if security_list_id != null
  }

  attach_commands = {
    for key, ref in local.subnet_refs :
    key => format(
      "oci network subnet update --region \"$${OCI_REGION}\" --subnet-id %s --security-list-ids '%s' --force",
      ref.subnet_id,
      jsonencode(local.attach_security_list_ids[key])
    )
    if contains(keys(local.attach_security_list_ids), key)
  }

  detach_commands = {
    for key, ref in local.subnet_refs :
    key => format(
      "oci network subnet update --region \"$${OCI_REGION}\" --subnet-id %s --security-list-ids '%s' --force",
      ref.subnet_id,
      jsonencode(terraform_data.original_security_list_ids[key].output)
    )
    if contains(keys(local.attach_security_list_ids), key)
  }

  attach_run_order = flatten([
    for cluster_name in sort(keys(var.clusters)) : [
      for role in local.subnet_roles : "${cluster_name}.${role}"
      if contains(keys(local.attach_commands), "${cluster_name}.${role}")
    ]
  ])

  attach_commands_by_cluster = {
    for cluster_name in sort(keys(var.clusters)) : cluster_name => {
      for role in local.subnet_roles : role => {
        subnet_id            = local.subnet_refs["${cluster_name}.${role}"].subnet_id
        new_security_list_id = local.security_list_ids_by_subnet["${cluster_name}.${role}"]
        attach_command       = local.attach_commands["${cluster_name}.${role}"]
      }
      if contains(keys(local.attach_commands), "${cluster_name}.${role}")
    }
  }

  detach_commands_by_cluster = {
    for cluster_name in sort(keys(var.clusters)) : cluster_name => {
      for role in local.subnet_roles : role => {
        subnet_id       = local.subnet_refs["${cluster_name}.${role}"].subnet_id
        restore_command = local.detach_commands["${cluster_name}.${role}"]
      }
      if contains(keys(local.detach_commands), "${cluster_name}.${role}")
    }
  }

  attach_script_path = (
    try(trimspace(var.attach_script_path), "") != "" ?
    trimspace(var.attach_script_path) :
    abspath("${path.root}/../../generated/attach-security-lists.sh")
  )

  detach_script_path = (
    try(trimspace(var.detach_script_path), "") != "" ?
    trimspace(var.detach_script_path) :
    abspath("${path.root}/../../generated/detach-security-lists.sh")
  )

  attach_script_lines = concat(
    [
      "#!/usr/bin/env bash",
      "# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.",
      "#",
      "# Author: Ulaganathan N",
      "#",
      "# Generated by Terraform. Review this file before running it.",
      "",
      "set -euo pipefail",
      "",
      "OCI_REGION=\"$${OCI_REGION:-${var.region}}\"",
      "",
      "command -v oci >/dev/null || { echo \"ERROR: OCI CLI is not available in PATH.\"; exit 1; }",
      "",
      "echo \"WARNING: This script mutates existing OCI subnet security_list_ids.\"",
      "echo \"It preserves current security lists and appends the Terraform-created OKE security lists.\"",
      "echo \"If these subnets are managed by another Terraform state, running this can create drift there.\"",
      "echo \"OCI region: $${OCI_REGION}\"",
      "echo",
      "read -r -p \"Review completed. Type APPLY to continue: \" CONFIRM",
      "if [ \"$${CONFIRM}\" != \"APPLY\" ]; then",
      "  echo \"Aborted. No subnet changes were made.\"",
      "  exit 0",
      "fi",
      "",
      "echo \"Starting security-list attachment...\""
    ],
    flatten([
      for cluster_name in sort(keys(local.attach_commands_by_cluster)) : concat(
        [
          "",
          "echo",
          "echo \"===== ${cluster_name} =====\""
        ],
        flatten([
          for role in local.subnet_roles : [
            "",
            "echo \"Attaching ${cluster_name}.${role}\"",
            local.attach_commands_by_cluster[cluster_name][role].attach_command
          ]
          if contains(keys(local.attach_commands_by_cluster[cluster_name]), role)
        ])
      )
    ]),
    [
      "",
      "echo",
      "echo \"Security-list attachment completed.\""
    ]
  )

  attach_script_content = "${join("\n", local.attach_script_lines)}\n"

  detach_script_lines = concat(
    [
      "#!/usr/bin/env bash",
      "# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.",
      "#",
      "# Author: Ulaganathan N",
      "#",
      "# Generated by Terraform. Review this file before running it.",
      "",
      "set -euo pipefail",
      "",
      "OCI_REGION=\"$${OCI_REGION:-${var.region}}\"",
      "",
      "command -v oci >/dev/null || { echo \"ERROR: OCI CLI is not available in PATH.\"; exit 1; }",
      "",
      "echo \"WARNING: This script restores original OCI subnet security_list_ids captured during Terraform apply.\"",
      "echo \"Run this before destroying Terraform-created OKE security lists if the attach script was executed.\"",
      "echo \"OCI region: $${OCI_REGION}\"",
      "echo",
      "read -r -p \"Review completed. Type RESTORE to continue: \" CONFIRM",
      "if [ \"$${CONFIRM}\" != \"RESTORE\" ]; then",
      "  echo \"Aborted. No subnet changes were made.\"",
      "  exit 0",
      "fi",
      "",
      "echo \"Starting security-list restore...\""
    ],
    flatten([
      for cluster_name in sort(keys(local.detach_commands_by_cluster)) : concat(
        [
          "",
          "echo",
          "echo \"===== ${cluster_name} =====\""
        ],
        flatten([
          for role in local.subnet_roles : [
            "",
            "echo \"Restoring ${cluster_name}.${role}\"",
            local.detach_commands_by_cluster[cluster_name][role].restore_command
          ]
          if contains(keys(local.detach_commands_by_cluster[cluster_name]), role)
        ])
      )
    ]),
    [
      "",
      "echo",
      "echo \"Security-list restore completed.\""
    ]
  )

  detach_script_content = "${join("\n", local.detach_script_lines)}\n"
}

resource "local_file" "attach_security_lists" {
  filename             = local.attach_script_path
  content              = local.attach_script_content
  file_permission      = "0755"
  directory_permission = "0755"
}

resource "local_file" "detach_security_lists" {
  filename             = local.detach_script_path
  content              = local.detach_script_content
  file_permission      = "0755"
  directory_permission = "0755"
}

module "clusters" {
  source   = "../../modules/oke-cluster"
  for_each = var.clusters

  cluster_name          = each.key
  config                = each.value
  compartment_id        = module.lookup[each.key].compartment_id
  vcn_id                = module.lookup[each.key].vcn_id
  endpoint_subnet_id    = module.lookup[each.key].endpoint_subnet_id
  endpoint_nsg_ids      = module.lookup[each.key].endpoint_nsg_ids
  service_lb_subnet_ids = [for id in [module.lookup[each.key].lb_subnet_id] : id if id != null && id != ""]
  lb_backend_nsg_ids    = module.lookup[each.key].lb_backend_nsg_ids
}

data "oci_containerengine_node_pool_option" "options" {
  for_each = local.node_pools

  node_pool_option_id   = module.clusters[each.value.cluster_name].id
  compartment_id        = module.lookup[each.value.cluster_name].compartment_id
  node_pool_k8s_version = try(each.value.node_pool.kubernetes_version, each.value.cluster_config.kubernetes_version)
  node_pool_os_type     = local.node_pool_os_type[each.key]
  node_pool_os_arch     = local.node_pool_os_arch[each.key]
}

locals {
  image_candidates = {
    for key, node_pool in local.node_pools : key => [
      for source in data.oci_containerengine_node_pool_option.options[key].sources : source
      if source.source_type == "IMAGE"
      && (
        local.node_pool_image_name[key] == ""
        || source.source_name == local.node_pool_image_name[key]
      )
      && (
        local.node_pool_image_name_pattern[key] == ""
        || can(regex(local.node_pool_image_name_pattern[key], source.source_name))
      )
      && (
        try(node_pool.node_pool.allow_gpu_image, false)
        || !can(regex("GPU", source.source_name))
      )
      && (
        local.node_pool_exclude_image_name_pattern[key] == ""
        || !can(regex(local.node_pool_exclude_image_name_pattern[key], source.source_name))
      )
    ]
  }

  resolved_image_ids = {
    for key, node_pool in local.node_pools :
    key => local.node_pool_image_id[key] != "" ? local.node_pool_image_id[key] : try(local.image_candidates[key][0].image_id, null)
  }

  resolved_image_names = {
    for key, node_pool in local.node_pools :
    key => local.node_pool_image_id[key] != "" ? "explicit image_id" : try(local.image_candidates[key][0].source_name, null)
  }
}

module "node_pools" {
  source   = "../../modules/oke-node-pool"
  for_each = local.node_pools

  cluster_name       = each.value.cluster_name
  node_pool_key      = each.value.node_pool_key
  node_pool          = each.value.node_pool
  cluster_id         = module.clusters[each.value.cluster_name].id
  compartment_id     = module.lookup[each.value.cluster_name].compartment_id
  kubernetes_version = try(each.value.node_pool.kubernetes_version, each.value.cluster_config.kubernetes_version)
  cni_type           = try(each.value.node_pool.cni_type, each.value.cluster_config.cluster.cni_type)
  worker_subnet_id   = module.lookup[each.value.cluster_name].worker_subnet_id
  worker_nsg_ids     = module.lookup[each.value.cluster_name].worker_nsg_ids
  resolved_image_id  = local.resolved_image_ids[each.key]
  pod_subnet_ids     = [for id in [module.lookup[each.value.cluster_name].pod_subnet_id] : id if id != null && id != ""]
  pod_nsg_ids        = module.lookup[each.value.cluster_name].pod_nsg_ids

  placement_configs = [
    for ad in(
      length(try(each.value.node_pool.availability_domains, [])) > 0
      ? each.value.node_pool.availability_domains
      : local.all_availability_domains[each.value.cluster_name]
      ) : {
      availability_domain = ad
      subnet_id           = module.lookup[each.value.cluster_name].worker_subnet_id
      fault_domains       = try(each.value.node_pool.fault_domains, [])
    }
  ]
}
