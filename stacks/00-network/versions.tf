# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0"
    }
  }
}
