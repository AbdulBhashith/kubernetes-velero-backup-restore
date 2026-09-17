# main.tf
# Root module wiring: looks up the AKS clusters, provisions shared backup
# storage + identity, then installs/configures Velero on the source and
# destination clusters and optionally the restore scaffolding.

# ---------------------------------------------------------------------------
# AKS clusters.
# Two modes controlled by var.create_clusters:
#   true  -> Terraform CREATES both cost-optimized clusters (default).
#   false -> Both clusters already exist and are looked up via data sources.
# All downstream references use the normalized locals below so the rest of the
# config is agnostic to which mode is active.
# ---------------------------------------------------------------------------
module "aks_source" {
  source = "./modules/aks-cluster"
  count  = var.create_clusters ? 1 : 0

  cluster_name        = var.source_cluster.name
  resource_group_name = var.source_cluster.resource_group_name
  location            = coalesce(var.source_cluster.location, var.location)

  kubernetes_version    = var.cluster_config.kubernetes_version
  sku_tier              = var.cluster_config.sku_tier
  node_vm_size          = var.cluster_config.node_vm_size
  enable_auto_scaling   = var.cluster_config.enable_auto_scaling
  min_node_count        = var.cluster_config.min_node_count
  max_node_count        = var.cluster_config.max_node_count
  node_count            = var.cluster_config.node_count
  os_disk_size_gb       = var.cluster_config.os_disk_size_gb
  use_ephemeral_os_disk = var.cluster_config.use_ephemeral_os_disk

  pod_cidr       = var.cluster_config.pod_cidr
  service_cidr   = var.cluster_config.service_cidr
  dns_service_ip = var.cluster_config.dns_service_ip

  tags = var.tags
}

module "aks_destination" {
  source = "./modules/aks-cluster"
  count  = var.create_clusters ? 1 : 0

  cluster_name        = var.destination_cluster.name
  resource_group_name = var.destination_cluster.resource_group_name
  location            = coalesce(var.destination_cluster.location, var.location)

  kubernetes_version    = var.cluster_config.kubernetes_version
  sku_tier              = var.cluster_config.sku_tier
  node_vm_size          = var.cluster_config.node_vm_size
  enable_auto_scaling   = var.cluster_config.enable_auto_scaling
  min_node_count        = var.cluster_config.min_node_count
  max_node_count        = var.cluster_config.max_node_count
  node_count            = var.cluster_config.node_count
  os_disk_size_gb       = var.cluster_config.os_disk_size_gb
  use_ephemeral_os_disk = var.cluster_config.use_ephemeral_os_disk

  pod_cidr       = var.cluster_config.pod_cidr
  service_cidr   = var.cluster_config.service_cidr
  dns_service_ip = var.cluster_config.dns_service_ip

  tags = var.tags
}

# Look up existing clusters only when NOT creating them.
data "azurerm_kubernetes_cluster" "source" {
  count               = var.create_clusters ? 0 : 1
  name                = var.source_cluster.name
  resource_group_name = var.source_cluster.resource_group_name
}

data "azurerm_kubernetes_cluster" "destination" {
  count               = var.create_clusters ? 0 : 1
  name                = var.destination_cluster.name
  resource_group_name = var.destination_cluster.resource_group_name
}

# Normalized connection details, independent of create-vs-lookup mode.
locals {
  # Resolve the local chart path: use the explicit override if given, else the
  # default vendored location under the root module (./chart/velero).
  resolved_local_chart_path = var.local_chart_path != "" ? var.local_chart_path : "${path.root}/chart/velero"

  source_oidc_issuer_url = var.create_clusters ? module.aks_source[0].oidc_issuer_url : data.azurerm_kubernetes_cluster.source[0].oidc_issuer_url
  dest_oidc_issuer_url   = var.create_clusters ? module.aks_destination[0].oidc_issuer_url : data.azurerm_kubernetes_cluster.destination[0].oidc_issuer_url

  source_kube = var.create_clusters ? {
    host                   = module.aks_source[0].host
    client_certificate     = module.aks_source[0].client_certificate
    client_key             = module.aks_source[0].client_key
    cluster_ca_certificate = module.aks_source[0].cluster_ca_certificate
    } : {
    host                   = data.azurerm_kubernetes_cluster.source[0].kube_config[0].host
    client_certificate     = data.azurerm_kubernetes_cluster.source[0].kube_config[0].client_certificate
    client_key             = data.azurerm_kubernetes_cluster.source[0].kube_config[0].client_key
    cluster_ca_certificate = data.azurerm_kubernetes_cluster.source[0].kube_config[0].cluster_ca_certificate
  }

  dest_kube = var.create_clusters ? {
    host                   = module.aks_destination[0].host
    client_certificate     = module.aks_destination[0].client_certificate
    client_key             = module.aks_destination[0].client_key
    cluster_ca_certificate = module.aks_destination[0].cluster_ca_certificate
    } : {
    host                   = data.azurerm_kubernetes_cluster.destination[0].kube_config[0].host
    client_certificate     = data.azurerm_kubernetes_cluster.destination[0].kube_config[0].client_certificate
    client_key             = data.azurerm_kubernetes_cluster.destination[0].kube_config[0].client_key
    cluster_ca_certificate = data.azurerm_kubernetes_cluster.destination[0].kube_config[0].cluster_ca_certificate
  }
}

# A short random suffix keeps the storage account name globally unique across
# repeated deployments without requiring the user to invent one.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

# ---------------------------------------------------------------------------
# Shared backup storage + passwordless identity (Workload Identity).
# A single storage account/container is shared by both clusters so the
# destination can read backups produced by the source.
# ---------------------------------------------------------------------------
module "azure_storage" {
  source = "./modules/azure-storage"

  name_prefix           = var.name_prefix
  random_suffix         = random_string.suffix.result
  location              = var.location
  resource_group_name   = var.resource_group_name
  create_resource_group = var.create_resource_group
  tags                  = var.tags

  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  blob_container_name      = var.blob_container_name
  soft_delete_retention    = var.storage_soft_delete_retention_days
  network_default_action   = var.storage_network_default_action
  allowed_ip_ranges        = var.allowed_ip_ranges

  # Both clusters' Velero service accounts must be federated to the same
  # user-assigned managed identity so they can authenticate passwordlessly.
  federated_identities = {
    source = {
      issuer  = local.source_oidc_issuer_url
      subject = "system:serviceaccount:${var.velero_namespace}:velero"
    }
    destination = {
      issuer  = local.dest_oidc_issuer_url
      subject = "system:serviceaccount:${var.velero_namespace}:velero"
    }
  }

  tenant_id = var.tenant_id
}

# ---------------------------------------------------------------------------
# Velero on the SOURCE cluster (backups).
# ---------------------------------------------------------------------------
module "velero_source" {
  source = "./modules/velero-source"

  providers = {
    helm       = helm.source
    kubernetes = kubernetes.source
  }

  velero_namespace     = var.velero_namespace
  helm_chart_version   = var.velero_helm_chart_version
  use_local_chart      = var.use_local_chart
  local_chart_path     = local.resolved_local_chart_path
  velero_image_tag     = var.velero_image_tag
  plugin_azure_tag     = var.velero_plugin_azure_tag
  plugin_csi_tag       = var.velero_plugin_csi_tag
  kubectl_image_tag    = var.kubectl_image_tag
  use_builtin_csi      = var.use_builtin_csi
  enable_csi_snapshots = var.enable_csi_snapshots
  csi_driver           = var.csi_driver
  enable_node_agent    = var.enable_node_agent

  # Passwordless auth via Workload Identity.
  workload_identity_client_id = module.azure_storage.managed_identity_client_id
  tenant_id                   = var.tenant_id

  # Storage backend.
  storage_account_name = module.azure_storage.storage_account_name
  blob_container_name  = module.azure_storage.blob_container_name
  backup_prefix        = var.source_cluster.backup_prefix
  resource_group_name  = module.azure_storage.resource_group_name
  subscription_id      = var.subscription_id

  backup_schedules = var.backup_schedules

  depends_on = [module.azure_storage, module.aks_source]
}

# ---------------------------------------------------------------------------
# Velero on the DESTINATION cluster (reads the same storage, read/restore).
# ---------------------------------------------------------------------------
module "velero_destination" {
  source = "./modules/velero-destination"

  providers = {
    helm       = helm.destination
    kubernetes = kubernetes.destination
  }

  velero_namespace     = var.velero_namespace
  helm_chart_version   = var.velero_helm_chart_version
  use_local_chart      = var.use_local_chart
  local_chart_path     = local.resolved_local_chart_path
  velero_image_tag     = var.velero_image_tag
  plugin_azure_tag     = var.velero_plugin_azure_tag
  plugin_csi_tag       = var.velero_plugin_csi_tag
  kubectl_image_tag    = var.kubectl_image_tag
  use_builtin_csi      = var.use_builtin_csi
  enable_csi_snapshots = var.enable_csi_snapshots
  csi_driver           = var.csi_driver
  enable_node_agent    = var.enable_node_agent

  workload_identity_client_id = module.azure_storage.managed_identity_client_id
  tenant_id                   = var.tenant_id

  storage_account_name = module.azure_storage.storage_account_name
  blob_container_name  = module.azure_storage.blob_container_name
  # Destination reads the SOURCE prefix so cross-cluster restore can find backups.
  backup_prefix       = var.source_cluster.backup_prefix
  resource_group_name = module.azure_storage.resource_group_name
  subscription_id     = var.subscription_id

  depends_on = [module.azure_storage, module.aks_destination]
}

# ---------------------------------------------------------------------------
# Optional restore scaffolding on the destination cluster.
# ---------------------------------------------------------------------------
module "velero_restore" {
  source = "./modules/velero-restore"
  count  = var.enable_restore ? 1 : 0

  velero_namespace = var.velero_namespace
  restore_config   = var.restore_config

  depends_on = [module.velero_destination]
}
