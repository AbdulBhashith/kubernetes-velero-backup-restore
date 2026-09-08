# Module: velero-destination

Installs Velero on the **destination** cluster, pointed at the same storage account and prefix as the source so it can list and restore the source's backups.

## What it creates

- `kubernetes_namespace` for Velero
- `helm_release` (vmware-tanzu Velero chart) with the same Workload Identity wiring as the source

## How it differs from velero-source

- **No schedules** — this cluster restores, it does not back up on a schedule.
- The `BackupStorageLocation` uses `accessMode: ReadWrite` (Velero must write restore metadata). Set it to `ReadOnly` only if this cluster should never create backups.
- `backup_prefix` is set to the **source** prefix so the source's backups are visible here. This is what makes cross-cluster restore work.

## Passwordless auth

Identical to the source: `credentials.useSecret = false`, ServiceAccount annotated with the managed identity client ID, `useAAD: "true"`. The same managed identity is federated to this cluster's Velero ServiceAccount by the `azure-storage` module.

## Key inputs

| Name | Description |
|------|-------------|
| `helm_chart_version`, `velero_image_tag`, `plugin_azure_tag` | Version pins. |
| `use_builtin_csi` / `enable_csi_snapshots` | CSI restore support. |
| `workload_identity_client_id` | Identity client ID. |
| `storage_account_name`, `blob_container_name`, `backup_prefix` | Points at the source's backups. |

## Key outputs

| Name | Description |
|------|-------------|
| `velero_namespace` | Namespace Velero runs in. |
| `helm_release_status` | Release status. |
