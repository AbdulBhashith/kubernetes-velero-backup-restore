# modules/aks-cluster/main.tf
# Cost-optimized AKS cluster suitable for the Velero source/destination roles.
#
# Cost decisions (all overridable via variables):
#   - sku_tier = "Free"        : no control-plane uptime-SLA charge.
#   - Standard_B2s burstable VM : cheap 2 vCPU / 4 GiB node for dev/demo.
#   - autoscaler min=1/max=2    : scales down to a single node when idle.
#   - small OS disk (32 GiB)    : minimizes managed-disk cost.
#   - system-assigned identity  : no extra identity resource to manage/pay for.
#
# Required for Velero passwordless auth:
#   - oidc_issuer_enabled       = true
#   - workload_identity_enabled = true

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = coalesce(var.dns_prefix, var.cluster_name)
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  # Passwordless prerequisites for Azure Workload Identity used by Velero.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Turn off local admin kubeconfig is possible, but we keep it enabled so the
  # azurerm data/kube_config works out of the box. For hardened environments,
  # set local_account_disabled = true and use AAD RBAC.
  default_node_pool {
    name       = "system"
    vm_size    = var.node_vm_size
    node_count = var.enable_auto_scaling ? null : var.node_count

    auto_scaling_enabled = var.enable_auto_scaling
    min_count            = var.enable_auto_scaling ? var.min_node_count : null
    max_count            = var.enable_auto_scaling ? var.max_node_count : null

    os_disk_size_gb = var.os_disk_size_gb
    # Ephemeral OS disks avoid a separate managed-disk cost but require a VM
    # size with a large enough cache. Falls back to Managed when disabled.
    os_disk_type = var.use_ephemeral_os_disk ? "Ephemeral" : "Managed"

    # Only upgrade one node at a time to keep small clusters stable.
    upgrade_settings {
      max_surge = "10%"
    }

    tags = var.tags
  }

  identity {
    type = "SystemAssigned"
  }

  # Azure CNI Overlay: the supported, recommended networking model. Kubenet is
  # deprecated and unsupported after 2028-03-31. Overlay keeps kubenet's key
  # benefit - pods get IPs from an overlay CIDR, NOT the VNet subnet, so it
  # scales without consuming subnet address space - while remaining supported.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"

    # Overlay pod CIDR (not routable outside the cluster; does not touch the VNet).
    pod_cidr = var.pod_cidr
    # Kubernetes Service CIDR + kube-dns IP (dns_service_ip must be inside service_cidr).
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip
  }

  tags = var.tags

  lifecycle {
    # Node count drifts due to the autoscaler; ignore it so plans stay clean.
    ignore_changes = [
      default_node_pool[0].node_count,
    ]
  }
}
