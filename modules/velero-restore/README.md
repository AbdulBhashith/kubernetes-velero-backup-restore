# Module: velero-restore

Renders a Velero `Restore` manifest for the destination cluster. Optional; enabled by `enable_restore = true`.

## What it creates

- `local_file` at `generated/restore-<restore_name>.yaml` — the rendered Restore manifest

It does **not** create a Kubernetes object directly.

## Why a file instead of `kubernetes_manifest`

Two reasons:

1. `kubernetes_manifest` needs a live cluster API at **plan** time, which fails when clusters are created in the same run (`cannot create REST client`).
2. Velero `Restore` objects are inherently **one-shot** and on-demand, a poor fit for declarative lifecycle management.

So the module renders the manifest to disk; you apply it when you are ready:

```bash
kubectl apply -f generated/restore-<restore_name>.yaml
velero restore describe <restore_name> -n velero --details
```

To restore again, change `restore_name` (and re-apply Terraform to regenerate the file), or just use `scripts/restore.sh`.

## Preconditions on the destination before applying

- Velero installed and `BackupStorageLocation` is `Available`.
- The named backup is visible (`velero backup get`).
- StorageClasses used by restored PVCs exist (or are remapped).
- CSI driver + `VolumeSnapshotClass` exist for CSI snapshot restores.
- Namespaces mapped onto existing namespaces already exist; otherwise Velero creates targets automatically.

## Key inputs

| Name | Description |
|------|-------------|
| `restore_config.backup_name` | Source backup to restore (empty = render nothing). |
| `restore_config.restore_name` | Name for the Restore object / file. |
| `restore_config.namespace_mappings` | `{ source_ns = dest_ns }`. |
| `restore_config.included_namespaces` / `excluded_namespaces` / `excluded_resources` | Filters. |
| `restore_config.restore_pvs` | Restore persistent volumes. |
| `restore_config.existing_resource_policy` | `none` or `update`. |

## Key outputs

| Name | Description |
|------|-------------|
| `restore_manifest_path` | Path to the rendered manifest. |
| `restore_created` | Whether a manifest was rendered. |
