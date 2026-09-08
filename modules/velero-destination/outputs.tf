# modules/velero-destination/outputs.tf

output "velero_namespace" {
  description = "Namespace where Velero is installed on the destination cluster."
  value       = kubernetes_namespace.velero.metadata[0].name
}

output "helm_release_name" {
  description = "Name of the Velero Helm release."
  value       = helm_release.velero.name
}

output "helm_release_status" {
  description = "Status of the Velero Helm release."
  value       = helm_release.velero.status
}
