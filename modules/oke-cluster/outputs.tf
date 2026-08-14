# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

output "id" {
  value = oci_containerengine_cluster.this.id
}

output "name" {
  value = oci_containerengine_cluster.this.name
}

output "cni_type" {
  value = local.cni_type
}

output "endpoints" {
  value = oci_containerengine_cluster.this.endpoints
}
