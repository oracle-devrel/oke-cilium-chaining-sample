# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

output "id" {
  value = oci_containerengine_node_pool.this.id
}

output "name" {
  value = oci_containerengine_node_pool.this.name
}

output "cni_type" {
  value = local.cni_type
}
