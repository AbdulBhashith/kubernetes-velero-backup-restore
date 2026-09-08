# modules/azure-storage/outputs.tf

output "resource_group_name" {
  description = "Resource group holding the backup storage."
  value       = local.resource_group_name
}

output "storage_account_name" {
  description = "Backup storage account name."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Backup storage account resource ID."
  value       = azurerm_storage_account.this.id
}

output "blob_container_name" {
  description = "Backup blob container name."
  value       = azurerm_storage_container.this.name
}

output "managed_identity_client_id" {
  description = "Client ID of the Velero user-assigned managed identity."
  value       = azurerm_user_assigned_identity.velero.client_id
}

output "managed_identity_principal_id" {
  description = "Principal (object) ID of the Velero managed identity."
  value       = azurerm_user_assigned_identity.velero.principal_id
}
