# modules/velero-restore/outputs.tf

output "restore_name" {
  description = "Name of the Velero Restore object (empty if no backup_name was provided)."
  value       = var.restore_config.backup_name != "" ? var.restore_config.restore_name : ""
}

output "restore_created" {
  description = "Whether a Restore manifest was rendered by Terraform."
  value       = var.restore_config.backup_name != ""
}

output "restore_manifest_path" {
  description = "Path to the rendered Restore manifest. Apply it with: kubectl apply -f <path> (against the destination cluster)."
  value       = var.restore_config.backup_name != "" ? local_file.restore_manifest[0].filename : ""
}
