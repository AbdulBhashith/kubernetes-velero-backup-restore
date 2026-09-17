# modules/velero-source/variables.tf

variable "velero_namespace" {
  description = "Namespace where Velero is installed."
  type        = string
  default     = "velero"
}

variable "helm_chart_version" {
  description = "vmware-tanzu Velero Helm chart version (used only when use_local_chart = false)."
  type        = string
}

variable "use_local_chart" {
  description = "If true, install from a vendored local chart directory instead of the remote Helm repo (fallback when the remote repo is unavailable)."
  type        = bool
  default     = false
}

variable "local_chart_path" {
  description = "Filesystem path to the unpacked local Velero chart directory (used when use_local_chart = true)."
  type        = string
  default     = ""
}

variable "velero_image_tag" {
  description = "Velero server image tag."
  type        = string
}

variable "plugin_azure_tag" {
  description = "velero-plugin-for-microsoft-azure image tag."
  type        = string
}

variable "plugin_csi_tag" {
  description = "Velero CSI plugin image tag (ignored when use_builtin_csi = true)."
  type        = string
}

variable "kubectl_image_tag" {
  description = "Tag for the registry.k8s.io/kubectl image used by the chart's CRD jobs."
  type        = string
  default     = "v1.31.0"
}

variable "use_builtin_csi" {
  description = "Use Velero's built-in CSI support (>= 1.14) instead of the standalone CSI plugin."
  type        = bool
  default     = true
}

variable "enable_csi_snapshots" {
  description = "Enable CSI snapshot data movement for persistent volumes."
  type        = bool
  default     = true
}

variable "csi_driver" {
  description = "CSI driver name for the VolumeSnapshotClass created for Velero (AKS default disk: disk.csi.azure.com)."
  type        = string
  default     = "disk.csi.azure.com"
}

variable "enable_node_agent" {
  description = "Deploy the Velero node-agent (Kopia) for filesystem-level backups. Required for portable cross-cluster/cross-region volume restores."
  type        = bool
  default     = true
}

variable "workload_identity_client_id" {
  description = "Client ID of the user-assigned managed identity federated to the Velero service account."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant ID."
  type        = string
}

variable "storage_account_name" {
  description = "Backup storage account name."
  type        = string
}

variable "blob_container_name" {
  description = "Backup blob container name."
  type        = string
}

variable "backup_prefix" {
  description = "Object-storage prefix isolating this cluster's backups."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the storage account."
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID of the storage account."
  type        = string
}

variable "backup_schedules" {
  description = "Map of Velero backup schedules to create."
  type = map(object({
    cron                         = string
    included_namespaces          = optional(list(string), ["*"])
    excluded_namespaces          = optional(list(string), [])
    included_resources           = optional(list(string), [])
    excluded_resources           = optional(list(string), [])
    ttl                          = optional(string, "720h0m0s")
    snapshot_volumes             = optional(bool, true)
    default_volumes_to_fs_backup = optional(bool, false)
    include_cluster_resources    = optional(bool, true)
  }))
  default = {}
}
