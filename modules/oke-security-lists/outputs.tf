# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

output "security_list_ids" {
  value = {
    endpoint = try(oci_core_security_list.endpoint[0].id, null)
    worker   = try(oci_core_security_list.worker[0].id, null)
    pod      = try(oci_core_security_list.pod[0].id, null)
    lb       = try(oci_core_security_list.lb[0].id, null)
  }
}
