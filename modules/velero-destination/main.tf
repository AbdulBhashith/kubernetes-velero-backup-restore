# modules/velero-destination/main.tf
# Installs Velero on the DESTINATION cluster, pointed at the SAME storage and
# prefix as the source so it can list and restore the source cluster's backups.

resource "kubernetes_namespace" "velero" {
  metadata {
    name = var.velero_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "velero" {
  name      = "velero"
  namespace = kubernetes_namespace.velero.metadata[0].name

  # Chart source is switchable (see velero-source for details).
  repository = var.use_local_chart ? null : "https://vmware-tanzu.github.io/helm-charts"
  chart      = var.use_local_chart ? var.local_chart_path : "velero"
  version    = var.use_local_chart ? null : var.helm_chart_version

  # Wait for the deployment to be ready. On a fresh single-node cluster the
  # plugin init containers pull images on first start, so allow generous time.
  wait    = true
  timeout = 900

  # If the release fails, roll back and delete the failed release so a broken
  # release object is not left behind blocking the next apply.
  cleanup_on_fail = true
  # Recreate the release if a prior failed/incomplete release exists.
  replace = true

  values = [
    templatefile("${path.module}/values.yaml.tftpl", {
      velero_image_tag            = var.velero_image_tag
      plugin_azure_tag            = var.plugin_azure_tag
      plugin_csi_tag              = var.plugin_csi_tag
      kubectl_image_tag           = var.kubectl_image_tag
      use_builtin_csi             = var.use_builtin_csi
      enable_csi_snapshots        = var.enable_csi_snapshots
      csi_driver                  = var.csi_driver
      enable_node_agent           = var.enable_node_agent
      workload_identity_client_id = var.workload_identity_client_id
      storage_account_name        = var.storage_account_name
      blob_container_name         = var.blob_container_name
      backup_prefix               = var.backup_prefix
      resource_group_name         = var.resource_group_name
      subscription_id             = var.subscription_id
    })
  ]

  depends_on = [kubernetes_namespace.velero]
}
