# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#

output "cilium_release" {
  value = length(module.cilium) == 0 ? null : {
    name         = module.cilium[0].name
    version      = module.cilium[0].version
    install_mode = module.cilium[0].install_mode
  }
}

output "generated_cilium_values" {
  value = length(module.cilium) == 0 ? null : module.cilium[0].generated_values
}
