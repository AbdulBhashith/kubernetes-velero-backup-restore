# modules/velero-restore/main.tf
# Renders a Velero Restore manifest for the destination cluster.
#
# WHY A FILE, NOT kubernetes_manifest:
#   `kubernetes_manifest` requires a reachable cluster API at PLAN time to fetch
#   the CRD schema. When clusters are created in the same run - or simply to
#   avoid coupling plan to cluster availability - that fails with
#   "cannot create REST client: no client config". Restores are also inherently
#   one-shot and on-demand, so a declarative TF-managed Restore object is a poor
#   fit. Instead we render the manifest to disk; apply it with kubectl/velero
#   (see scripts/restore.sh) against the destination cluster.
#
# Preconditions on the destination cluster before applying the restore:
#   - Velero installed and its BackupStorageLocation "Available".
#   - The named backup is visible: `velero backup get`.
#   - StorageClasses used by restored PVCs exist (or are remapped).
#   - CSI driver + VolumeSnapshotClass exist for CSI snapshot restores.
#   - Namespaces mapped onto EXISTING namespaces must already exist; otherwise
#     Velero creates target namespaces automatically.

locals {
  backup_name = var.restore_config.backup_name

  restore_manifest = var.restore_config.backup_name != "" ? yamlencode({
    apiVersion = "velero.io/v1"
    kind       = "Restore"
    metadata = {
      name      = var.restore_config.restore_name
      namespace = var.velero_namespace
    }
    spec = merge(
      {
        backupName             = local.backup_name
        includedNamespaces     = var.restore_config.included_namespaces
        excludedNamespaces     = var.restore_config.excluded_namespaces
        excludedResources      = var.restore_config.excluded_resources
        restorePVs             = var.restore_config.restore_pvs
        existingResourcePolicy = var.restore_config.existing_resource_policy
      },
      length(var.restore_config.namespace_mappings) > 0 ? {
        namespaceMapping = var.restore_config.namespace_mappings
      } : {}
    )
  }) : ""
}

# Write the rendered manifest so it can be applied on demand. No cluster API is
# contacted at plan or apply time.
resource "local_file" "restore_manifest" {
  count = local.backup_name != "" ? 1 : 0

  filename        = "${path.root}/generated/restore-${var.restore_config.restore_name}.yaml"
  content         = local.restore_manifest
  file_permission = "0644"
}
