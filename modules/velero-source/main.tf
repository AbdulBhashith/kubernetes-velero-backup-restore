# modules/velero-source/main.tf
# Installs Velero on the SOURCE cluster and creates scheduled backups.
#
# Idempotency:
#  - The namespace is created explicitly; the Helm release upgrades in place on
#    re-apply.
#  - Backup schedules are rendered into the Helm chart's native `schedules`
#    values (the chart creates the Velero Schedule CRs as part of the release).
#    This avoids `kubernetes_manifest`, which requires a live cluster API at
#    PLAN time and therefore fails when the cluster is created in the same run.

# ---------------------------------------------------------------------------
# Transform the backup_schedules map into the structure expected by the Velero
# Helm chart's `schedules:` value, then encode to YAML for injection into the
# values template.
# ---------------------------------------------------------------------------
locals {
  schedules_map = {
    for name, s in var.backup_schedules : name => {
      disabled = false
      schedule = s.cron
      template = {
        ttl                     = s.ttl
        snapshotVolumes         = s.snapshot_volumes
        includeClusterResources = s.include_cluster_resources
        storageLocation         = "default"
        volumeSnapshotLocations = ["default"]
        includedNamespaces      = s.included_namespaces
        excludedNamespaces      = s.excluded_namespaces
        includedResources       = s.included_resources
        excludedResources       = s.excluded_resources
      }
    }
  }

  # Encode the ENTIRE `schedules` key with yamlencode so indentation is uniform
  # and valid. (Terraform's indent() does NOT indent the first line, which
  # previously produced a mismatched-indentation "did not find expected key"
  # error when there was more than one schedule.)
  # yamlencode always emits valid YAML for `{ schedules = {} }` too.
  schedules_block = yamlencode({ schedules = local.schedules_map })
}

# ---------------------------------------------------------------------------
# Namespace for Velero.
# ---------------------------------------------------------------------------
resource "kubernetes_namespace" "velero" {
  metadata {
    name = var.velero_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# Velero Helm release (includes backup schedules).
# ---------------------------------------------------------------------------
resource "helm_release" "velero" {
  name      = "velero"
  namespace = kubernetes_namespace.velero.metadata[0].name

  # Chart source is switchable:
  #   remote (default): pull "velero" from the vmware-tanzu Helm repo.
  #   local  (fallback): install from a vendored chart directory. When using a
  #                      local chart, repository/version must be null and chart
  #                      is a filesystem path.
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
  replace         = true

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
      schedules_block             = local.schedules_block
    })
  ]

  depends_on = [kubernetes_namespace.velero]
}
