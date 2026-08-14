# Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
#
# Author: Ulaganathan N
#
# Renders Cilium values for primary or chaining mode and manages the Helm release.

locals {
  install_mode        = lower(try(var.cilium.install_mode, "primary"))
  cilium_cluster_name = try(var.cilium.cluster_name, replace(var.cluster_name, "_", "-"))

  hubble_values = {
    enabled = try(var.cilium.hubble_enabled, true)
    relay = {
      enabled = try(var.cilium.hubble_relay_enabled, true)
    }
    ui = {
      enabled = try(var.cilium.hubble_ui_enabled, true)
    }
    tls = {
      enabled = try(var.cilium.hubble_tls_enabled, false)
    }
  }

  cluster_values = merge({
    name = local.cilium_cluster_name
    }, try(var.cilium.cluster_id, null) == null ? {} : {
    id = var.cilium.cluster_id
  })

  common_bpf_values = {
    lbMapMax            = try(var.cilium.bpf_lb_map_max, 65536)
    policyMapMax        = try(var.cilium.bpf_policy_map_max, 16384)
    mapDynamicSizeRatio = try(var.cilium.bpf_map_dynamic_size_ratio, 0.025)
    monitorAggregation  = try(var.cilium.monitor_aggregation, "medium")
    monitorFlags        = try(var.cilium.monitor_flags, "all")
    monitorInterval     = try(var.cilium.monitor_interval, "5s")
    distributedLRU = {
      enabled = try(var.cilium.bpf_distributed_lru, true)
    }
    events = {
      drop = {
        enabled = try(var.cilium.bpf_events_drop_enabled, true)
      }
      policyVerdict = {
        enabled = try(var.cilium.bpf_events_policy_verdict_enabled, true)
      }
      trace = {
        enabled = try(var.cilium.bpf_events_trace_enabled, true)
      }
    }
  }

  prometheus_values = {
    enabled        = try(var.cilium.prometheus_enabled, true)
    metricsService = try(var.cilium.prometheus_metrics_service, false)
    port           = try(var.cilium.prometheus_port, 9962)
    serviceMonitor = {
      enabled = try(var.cilium.prometheus_service_monitor_enabled, false)
    }
  }

  operator_values = {
    replicas = try(var.cilium.operator_replicas, 2)
    prometheus = {
      enabled = try(var.cilium.operator_prometheus_enabled, true)
      port    = try(var.cilium.operator_prometheus_port, 9963)
      serviceMonitor = {
        enabled = try(var.cilium.operator_prometheus_service_monitor_enabled, false)
      }
    }
  }

  service_host_values = merge(
    try(var.cilium.k8s_service_host, null) == null ? {} : { k8sServiceHost = var.cilium.k8s_service_host },
    try(var.cilium.k8s_service_port, null) == null ? {} : { k8sServicePort = var.cilium.k8s_service_port }
  )

  optional_common_values = merge(
    try(var.cilium.devices, null) == null ? {} : {
      devices = var.cilium.devices
    },
    try(var.cilium.endpoint_routes_enabled, null) == null ? {} : {
      endpointRoutes = {
        enabled = var.cilium.endpoint_routes_enabled
      }
    },
    try(var.cilium.extra_config, null) == null ? {} : {
      extraConfig = var.cilium.extra_config
    },
    try(var.cilium.k8s_require_ipv4_pod_cidr, null) == null ? {} : {
      k8s = {
        requireIPv4PodCIDR = var.cilium.k8s_require_ipv4_pod_cidr
      }
    }
  )

  common_values = merge({
    cluster = local.cluster_values
    ipam = {
      mode = try(var.cilium.ipam_mode, "kubernetes")
    }
    bpf                          = local.common_bpf_values
    enableLBIPAM                 = try(var.cilium.enable_lb_ipam, true)
    enableNonDefaultDenyPolicies = try(var.cilium.enable_non_default_deny_policies, true)
    endpointHealthChecking = {
      enabled = try(var.cilium.endpoint_health_checking_enabled, true)
    }
    healthChecking = try(var.cilium.health_checking_enabled, true)
    k8sNetworkPolicy = {
      enabled = try(var.cilium.k8s_network_policy_enabled, true)
    }
    l7Proxy              = try(var.cilium.l7_proxy_enabled, true)
    enableIPv4Masquerade = try(var.cilium.enable_ipv4_masquerade, true)
    enableIPv6Masquerade = try(var.cilium.enable_ipv6_masquerade, false)
    hubble               = local.hubble_values
    operator             = local.operator_values
    prometheus           = local.prometheus_values
  }, local.service_host_values, local.optional_common_values)

  primary_values = merge({
    kubeProxyReplacement = try(var.cilium.kube_proxy_replacement, true)
    routingMode          = try(var.cilium.routing_mode, "tunnel")
    bpf = merge(local.common_bpf_values, {
      masquerade = try(var.cilium.bpf_masquerade, true)
    })
    cni = {
      exclusive = try(var.cilium.cni_exclusive, true)
    }
    socketLB = {
      enabled                 = try(var.cilium.socket_lb_enabled, true)
      hostNamespaceOnly       = try(var.cilium.socket_lb_host_namespace_only, false)
      terminatePodConnections = try(var.cilium.socket_lb_terminate_pod_connections, true)
    }
    }, try(var.cilium.tunnel_protocol, null) == null ? {} : {
    tunnelProtocol = var.cilium.tunnel_protocol
    }, try(var.cilium.wireguard_enabled, false) ? {
    encryption = {
      enabled        = true
      type           = "wireguard"
      nodeEncryption = try(var.cilium.wireguard_node_encryption, false)
      wireguard = {
        persistentKeepalive = try(var.cilium.wireguard_persistent_keepalive, "0s")
      }
    }
  } : {})

  chaining_cni_values = merge({
    chainingMode = try(var.cilium.chaining_mode, "generic-veth")
    customConf   = try(var.cilium.cni_custom_conf, false)
    exclusive    = try(var.cilium.cni_exclusive, false)
    }, try(var.cilium.chaining_target, null) == null ? {} : {
    chainingTarget = var.cilium.chaining_target
    }, try(var.cilium.cni_config_map, null) == null ? {} : {
    configMap = var.cilium.cni_config_map
    }, try(var.cilium.cni_config_map_key, null) == null ? {} : {
    configMapKey = var.cilium.cni_config_map_key
    }, try(var.cilium.cni_external_routing, null) == null ? {} : {
    externalRouting = var.cilium.cni_external_routing
  })

  chaining_values = {
    kubeProxyReplacement = try(var.cilium.kube_proxy_replacement, false)
    routingMode          = try(var.cilium.routing_mode, "native")
    bpf = merge(local.common_bpf_values, {
      masquerade = try(var.cilium.bpf_masquerade, false)
    })
    socketLB = {
      enabled = try(var.cilium.socket_lb_enabled, false)
    }
    cni = local.chaining_cni_values
  }

  generated_values_yaml = local.install_mode == "chaining" ? yamlencode(merge(
    local.common_values,
    local.chaining_values
    )) : yamlencode(merge(
    local.common_values,
    local.primary_values
  ))

  generated_values = yamldecode(local.generated_values_yaml)
}

resource "helm_release" "cilium" {
  name             = "cilium"
  namespace        = try(var.cilium.namespace, "kube-system")
  create_namespace = false
  repository       = try(var.cilium.repository, "https://helm.cilium.io/")
  chart            = "cilium"
  version          = try(var.cilium.version, "1.18.11")

  wait            = true
  timeout         = try(var.cilium.timeout_seconds, 900)
  atomic          = try(var.cilium.atomic, false)
  cleanup_on_fail = true

  values = compact([
    local.generated_values_yaml,
    try(var.cilium.extra_values_yaml, "")
  ])

  lifecycle {
    precondition {
      condition     = contains(["primary", "chaining"], local.install_mode)
      error_message = "cilium.install_mode must be primary or chaining."
    }
  }
}
