# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Optional disposable network for reproducing the blog from an empty
# compartment. Existing-VCN deployments do not use this stack.

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
  common_tags = {
    "managed-by" = "terraform"
    "stack"      = "oke-cilium-blog-network"
    "purpose"    = "disposable-reference-environment"
  }
}

data "oci_core_services" "all_services" {
}

locals {
  oracle_services_network = one([
    for service in data.oci_core_services.all_services.services : service
    if can(regex("^All .* Services In Oracle Services Network$", service.name))
  ])
}

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = var.vcn_name
  dns_label      = var.vcn_dns_label
  freeform_tags  = local.common_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.vcn_name}-igw"
  enabled        = true
  freeform_tags  = local.common_tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.vcn_name}-nat"
  freeform_tags  = local.common_tags
}

resource "oci_core_service_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.vcn_name}-service-gateway"
  freeform_tags  = local.common_tags

  services {
    service_id = local.oracle_services_network.id
  }
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.vcn_name}-public-rt"
  freeform_tags  = local.common_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.vcn_name}-private-rt"
  freeform_tags  = local.common_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }

  route_rules {
    destination       = local.oracle_services_network.cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this.id
  }
}

resource "oci_core_security_list" "bootstrap" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.vcn_name}-bootstrap-sl"
  freeform_tags  = local.common_tags

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  ingress_security_rules {
    protocol    = "all"
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
  }

  dynamic "ingress_security_rules" {
    for_each = var.api_endpoint_source_cidrs
    content {
      protocol    = "6"
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"

      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }
}

resource "oci_core_subnet" "this" {
  for_each = var.subnets

  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = each.value.cidr_block
  display_name               = each.key
  dns_label                  = each.value.dns_label
  prohibit_internet_ingress  = each.value.private
  prohibit_public_ip_on_vnic = each.value.private
  route_table_id             = each.value.route_type == "public" ? oci_core_route_table.public.id : oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.bootstrap.id]
  freeform_tags              = local.common_tags

  lifecycle {
    # Role-specific OKE lists are attached after cluster creation. The network
    # stack owns the subnet but must preserve those recorded associations.
    ignore_changes = [security_list_ids]

    precondition {
      condition     = contains(["public", "private"], each.value.route_type)
      error_message = "subnets.route_type must be public or private."
    }
  }
}
