# outputs.tf
# Useful values for operators and downstream automation. No secrets are
# emitted; the managed identity is passwordless so only its client ID is shown.

output "resource_group_name" {
  description = "Resource group holding the Velero backup storage."
  value       = module.azure_storage.resource_group_name
}

output "storage_account_name" {
  description = "Storage account used for Velero backups."
  value       = module.azure_storage.storage_account_name
}

output "blob_container_name" {
  description = "Blob container that stores Velero backups."
  value       = module.azure_storage.blob_container_name
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity used by Velero (Workload Identity)."
  value       = module.azure_storage.managed_identity_client_id
}

output "managed_identity_principal_id" {
  description = "Principal (object) ID of the user-assigned managed identity."
  value       = module.azure_storage.managed_identity_principal_id
}

output "velero_namespace" {
  description = "Namespace where Velero is installed on both clusters."
  value       = var.velero_namespace
}

output "source_backup_prefix" {
  description = "Object-storage prefix under which the source cluster stores its backups."
  value       = var.source_cluster.backup_prefix
}

output "source_cluster_name" {
  description = "Name of the source (backup) AKS cluster."
  value       = var.source_cluster.name
}

output "destination_cluster_name" {
  description = "Name of the destination (restore) AKS cluster."
  value       = var.destination_cluster.name
}

output "clusters_created_by_terraform" {
  description = "Whether Terraform created the AKS clusters (true) or looked them up (false)."
  value       = var.create_clusters
}

output "source_cluster_id" {
  description = "Resource ID of the source AKS cluster."
  value       = var.create_clusters ? module.aks_source[0].cluster_id : data.azurerm_kubernetes_cluster.source[0].id
}

output "destination_cluster_id" {
  description = "Resource ID of the destination AKS cluster."
  value       = var.create_clusters ? module.aks_destination[0].cluster_id : data.azurerm_kubernetes_cluster.destination[0].id
}

output "backup_schedule_names" {
  description = "Names of the Velero scheduled backups created on the source cluster."
  value       = keys(var.backup_schedules)
}

output "velero_cli_source_context_hint" {
  description = "Command to fetch kubeconfig credentials for the source cluster."
  value       = "az aks get-credentials --resource-group ${var.source_cluster.resource_group_name} --name ${var.source_cluster.name}"
}

output "velero_cli_destination_context_hint" {
  description = "Command to fetch kubeconfig credentials for the destination cluster."
  value       = "az aks get-credentials --resource-group ${var.destination_cluster.resource_group_name} --name ${var.destination_cluster.name}"
}
