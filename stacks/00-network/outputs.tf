# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N

output "vcn_id" {
  value = oci_core_vcn.this.id
}

output "vcn_name" {
  value = oci_core_vcn.this.display_name
}

output "subnet_ids" {
  value = {
    for name, subnet in oci_core_subnet.this : name => subnet.id
  }
}

output "subnet_cidrs" {
  value = {
    for name, subnet in oci_core_subnet.this : name => subnet.cidr_block
  }
}

output "bootstrap_security_list_id" {
  value = oci_core_security_list.bootstrap.id
}

output "service_gateway_id" {
  value = oci_core_service_gateway.this.id
}
