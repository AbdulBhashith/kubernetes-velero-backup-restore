# variables.tf
# All configurable inputs for the root module. Sensible defaults are provided
# where safe; anything environment-specific has no default and must be supplied.
# Sensitive values are marked so they are redacted in Terraform output/state UI.

# ---------------------------------------------------------------------------
# Azure identity / subscription
# ---------------------------------------------------------------------------
variable "subscription_id" {
  description = "Azure subscription ID that hosts the storage account and (by default) the AKS clusters."
  type        = string
}

variable "tenant_id" {
  description = "Azure Active Directory (Entra ID) tenant ID."
  type        = string
}

variable "location" {
  description = "Primary Azure region for the backup resource group and storage account (e.g. eastus, westeurope)."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Common tags applied to all Azure resources created by this configuration."
  type        = map(string)
  default = {
    managed-by = "terraform"
    component  = "velero-backup"
  }
}

# ---------------------------------------------------------------------------
# Naming
# ---------------------------------------------------------------------------
variable "name_prefix" {
  description = "Short prefix used to name generated Azure resources. Must be lowercase alphanumeric (used in the storage account name)."
  type        = string
  default     = "velero"

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.name_prefix))
    error_message = "name_prefix must be 2-12 lowercase alphanumeric characters (it becomes part of a globally unique storage account name)."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create (or reuse) for Velero backup storage."
  type        = string
  default     = "rg-velero-backup"
}

variable "create_resource_group" {
  description = "Whether Terraform should create the resource group. Set to false to reuse an existing one."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Cluster lifecycle
# ---------------------------------------------------------------------------
variable "create_clusters" {
  description = <<-EOT
    If true, Terraform CREATES the source and destination AKS clusters (cost-optimized).
    If false, both clusters must already exist and are looked up by name/resource group.
  EOT
  type    = bool
  default = true
}

# ---------------------------------------------------------------------------
# Source AKS cluster
# ---------------------------------------------------------------------------
variable "source_cluster" {
  description = <<-EOT
    Details of the SOURCE AKS cluster (the cluster being backed up).
      name                : AKS cluster resource name.
      resource_group_name : Resource group that contains (or will contain) the cluster.
      location            : Region for the cluster (used only when create_clusters = true).
      backup_prefix       : Object-storage prefix used to isolate this cluster's backups in the shared container.
  EOT
  type = object({
    name                = string
    resource_group_name = string
    location            = optional(string, null)
    backup_prefix       = optional(string, "source")
  })
}

# ---------------------------------------------------------------------------
# Destination AKS cluster
# ---------------------------------------------------------------------------
variable "destination_cluster" {
  description = <<-EOT
    Details of the DESTINATION AKS cluster (the cluster restores are applied to).
      name                : AKS cluster resource name.
      resource_group_name : Resource group that contains (or will contain) the cluster.
      location            : Region for the cluster (used only when create_clusters = true).
  EOT
  type = object({
    name                = string
    resource_group_name = string
    location            = optional(string, null)
  })
}

# ---------------------------------------------------------------------------
# Cost-optimized cluster sizing (used only when create_clusters = true)
# ---------------------------------------------------------------------------
variable "cluster_config" {
  description = <<-EOT
    Sizing/cost settings applied to BOTH created clusters.
      kubernetes_version    : Null lets AKS choose the region default.
      sku_tier              : "Free" (no SLA charge) or "Standard".
      node_vm_size          : Node VM size (Standard_D2als_v7 is a low-cost default; some subscriptions restrict allowed sizes per region).
      enable_auto_scaling   : Autoscale down to min_node_count when idle.
      min_node_count        : Minimum nodes.
      max_node_count        : Maximum nodes.
      node_count            : Fixed node count when autoscaling is disabled.
      os_disk_size_gb       : OS disk size (kept small for cost).
      use_ephemeral_os_disk : Use Ephemeral OS disks (needs a VM size with a large cache).
      pod_cidr              : Azure CNI Overlay pod CIDR (not routable, no VNet subnet consumption).
      service_cidr          : Kubernetes Service ClusterIP CIDR (must not overlap VNet/pod_cidr).
      dns_service_ip        : Cluster DNS IP (must be inside service_cidr).
  EOT
  type = object({
    kubernetes_version    = optional(string, null)
    sku_tier              = optional(string, "Free")
    node_vm_size          = optional(string, "Standard_D2als_v7")
    enable_auto_scaling   = optional(bool, true)
    min_node_count        = optional(number, 1)
    max_node_count        = optional(number, 2)
    node_count            = optional(number, 1)
    os_disk_size_gb       = optional(number, 32)
    use_ephemeral_os_disk = optional(bool, false)
    pod_cidr              = optional(string, "10.244.0.0/16")
    service_cidr          = optional(string, "10.0.0.0/16")
    dns_service_ip        = optional(string, "10.0.0.10")
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Storage account configuration
# ---------------------------------------------------------------------------
variable "storage_account_tier" {
  description = "Performance tier for the backup storage account."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "storage_account_tier must be either Standard or Premium."
  }
}

variable "storage_account_replication_type" {
  description = "Replication strategy for the storage account (LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS)."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "storage_account_replication_type must be one of: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "blob_container_name" {
  description = "Name of the blob container that holds Velero backups (shared by source and destination clusters)."
  type        = string
  default     = "velero"
}

variable "storage_soft_delete_retention_days" {
  description = "Number of days blob soft-delete retains deleted backup objects."
  type        = number
  default     = 30

  validation {
    condition     = var.storage_soft_delete_retention_days >= 1 && var.storage_soft_delete_retention_days <= 365
    error_message = "storage_soft_delete_retention_days must be between 1 and 365."
  }
}

variable "allowed_ip_ranges" {
  description = "Optional list of public IP/CIDR ranges permitted to reach the storage account. Empty means no IP allow-list (Azure services + AKS egress must still be permitted via network_default_action)."
  type        = list(string)
  default     = []
}

variable "storage_network_default_action" {
  description = "Default network action for the storage account firewall. Use 'Deny' with allowed_ip_ranges/subnets for lockdown, or 'Allow' for open access."
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.storage_network_default_action)
    error_message = "storage_network_default_action must be Allow or Deny."
  }
}

# ---------------------------------------------------------------------------
# Velero / Helm configuration
# ---------------------------------------------------------------------------
variable "velero_namespace" {
  description = "Kubernetes namespace where Velero is installed on both clusters."
  type        = string
  default     = "velero"
}

variable "velero_helm_chart_version" {
  description = "Version of the vmware-tanzu Velero Helm chart to install. Chart 12.x installs Velero v1.16."
  type        = string
  default     = "12.1.0"
}

variable "use_local_chart" {
  description = "Fallback: install Velero from a vendored local chart directory (see chart/README.md) instead of the remote vmware-tanzu Helm repo. Useful when the remote repo is unreachable."
  type        = bool
  default     = false
}

variable "local_chart_path" {
  description = "Path to the unpacked local Velero chart directory when use_local_chart = true. Leave empty to use the default ./chart/velero under the root module."
  type        = string
  default     = ""
}

variable "velero_image_tag" {
  description = "Velero server image tag (Velero application version). Must be a published tag AND compatible with velero_plugin_azure_tag (plugin v1.12.x <-> Velero v1.16.x)."
  type        = string
  default     = "v1.16.0"
}

variable "velero_plugin_azure_tag" {
  # IMPORTANT: this must be a tag that actually exists in the registry.
  # The v1.11.x line was never published as v1.11.0, which caused
  # Init:ImagePullBackOff. Published stable tags include v1.12.0, v1.13.0,
  # v1.14.1/.2. Compatibility (plugin <-> Velero): v1.12.x<->v1.16.x,
  # v1.13.x<->v1.17.x, v1.11.x<->v1.15.x, v1.10.x<->v1.14.x.
  description = "Image tag for the velero-plugin-for-microsoft-azure. Must be a published tag compatible with velero_image_tag."
  type        = string
  default     = "v1.12.0"
}

variable "kubectl_image_tag" {
  description = "Tag for the registry.k8s.io/kubectl image used by the chart's CRD jobs. Should be close to your cluster's Kubernetes version."
  type        = string
  default     = "v1.31.0"
}

variable "velero_plugin_csi_tag" {
  description = "Image tag for the Velero CSI plugin. For Velero >= 1.14 CSI support is built-in and this is ignored when use_builtin_csi = true."
  type        = string
  default     = "v0.7.0"
}

variable "use_builtin_csi" {
  description = "If true (Velero >= 1.14), rely on the built-in CSI feature rather than installing the standalone CSI plugin."
  type        = bool
  default     = true
}

variable "enable_csi_snapshots" {
  description = "Enable CSI volume snapshots for persistent volume backup (recommended on AKS with Azure Disk CSI)."
  type        = bool
  default     = true
}

variable "csi_driver" {
  description = "CSI driver for which a Velero-labeled VolumeSnapshotClass is created on both clusters. AKS managed disks use disk.csi.azure.com; Azure Files uses file.csi.azure.com."
  type        = string
  default     = "disk.csi.azure.com"
}

variable "enable_node_agent" {
  description = "Enable the Velero node-agent (Kopia) for filesystem-level backups of volumes that do not support CSI snapshots."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Backup schedule / retention
# ---------------------------------------------------------------------------
variable "backup_schedules" {
  description = <<-EOT
    Map of scheduled backups to create on the source cluster. Key is the schedule name.
      cron                : Cron expression (Velero/Go cron format).
      included_namespaces : Namespaces to include ([] or ["*"] means all).
      excluded_namespaces : Namespaces to exclude.
      included_resources  : Resource types to include ([] means all).
      excluded_resources  : Resource types to exclude.
      ttl                 : Retention duration (e.g. "720h0m0s" = 30 days).
      snapshot_volumes    : Whether to snapshot persistent volumes.
      include_cluster_resources : Include cluster-scoped resources.
  EOT
  type = map(object({
    cron                      = string
    included_namespaces       = optional(list(string), ["*"])
    excluded_namespaces       = optional(list(string), [])
    included_resources        = optional(list(string), [])
    excluded_resources        = optional(list(string), [])
    ttl                       = optional(string, "720h0m0s")
    snapshot_volumes          = optional(bool, true)
    include_cluster_resources = optional(bool, true)
  }))
  default = {
    daily = {
      cron                = "0 2 * * *"
      included_namespaces = ["*"]
      ttl                 = "720h0m0s" # 30 days
      snapshot_volumes    = true
    }
  }
}

# ---------------------------------------------------------------------------
# Restore configuration
# ---------------------------------------------------------------------------
variable "enable_restore" {
  description = "Whether to provision the restore module on the destination cluster. Restores are typically executed on demand via scripts; this creates the supporting scaffolding."
  type        = bool
  default     = false
}

variable "restore_config" {
  description = <<-EOT
    Configuration for restoring a backup onto the destination cluster.
      backup_name          : Name of the source backup to restore (must exist in the shared bucket).
      restore_name         : Name to assign to the restore object.
      included_namespaces  : Namespaces to restore ([] or ["*"] = all in the backup).
      excluded_namespaces  : Namespaces to skip.
      excluded_resources   : Resource types to skip during restore.
      namespace_mappings   : Map of source namespace => destination namespace.
      restore_pvs          : Restore persistent volumes / snapshots.
      existing_resource_policy : "none" or "update" (how to handle pre-existing resources).
  EOT
  type = object({
    backup_name              = optional(string, "")
    restore_name             = optional(string, "restore-from-source")
    included_namespaces      = optional(list(string), ["*"])
    excluded_namespaces      = optional(list(string), [])
    excluded_resources       = optional(list(string), ["nodes", "events", "events.events.k8s.io"])
    namespace_mappings       = optional(map(string), {})
    restore_pvs              = optional(bool, true)
    existing_resource_policy = optional(string, "none")
  })
  default = {}
}
