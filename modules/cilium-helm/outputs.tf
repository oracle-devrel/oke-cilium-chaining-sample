# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

output "name" {
  value = helm_release.cilium.name
}

output "version" {
  value = helm_release.cilium.version
}

output "install_mode" {
  value = local.install_mode
}

output "generated_values" {
  value = local.generated_values
}
