# Module: velero-source

Installs Velero on the **source** cluster and creates the scheduled backups.

## What it creates

- `kubernetes_namespace` for Velero
- `helm_release` (vmware-tanzu Velero chart) configured for Azure + Workload Identity
- Backup **schedules** — rendered into the Helm chart's native `schedules:` values (not `kubernetes_manifest`)

## Why schedules go through Helm values

`kubernetes_manifest` requires a live cluster API at **plan** time. When the cluster is created in the same `terraform apply`, that API does not exist yet, causing `cannot create REST client`. The Velero Helm chart accepts a `schedules:` map and creates the `Schedule` CRs itself, and Helm connects at **apply** time — so a single apply works end to end.

The module transforms `backup_schedules` into the chart's expected shape and injects the whole `schedules:` key as YAML:

```hcl
schedules_block = yamlencode({ schedules = local.schedules_map })
```

> Note: we encode the entire `{ schedules = ... }` object with `yamlencode` rather than `indent(2, yamlencode(...))`. Terraform's `indent()` does not indent the *first* line, which caused mismatched indentation (`did not find expected key`) when more than one schedule was defined.

## Passwordless auth

The chart is configured with `credentials.useSecret = false`, the Velero ServiceAccount is annotated with `azure.workload.identity/client-id`, pods carry the `azure.workload.identity/use: "true"` label, and the backup storage location uses `useAAD: "true"`. No secret is mounted.

## Key inputs

| Name | Description |
|------|-------------|
| `helm_chart_version`, `velero_image_tag`, `plugin_azure_tag` | Version pins. |
| `use_builtin_csi` / `enable_csi_snapshots` | CSI snapshot support (Velero ≥ 1.14). |
| `enable_node_agent` | Kopia filesystem backups. |
| `workload_identity_client_id` | Identity client ID for the ServiceAccount. |
| `storage_account_name`, `blob_container_name`, `backup_prefix` | Backup destination. |
| `backup_schedules` | Map of schedules to create. |

## Key outputs

| Name | Description |
|------|-------------|
| `velero_namespace` | Namespace Velero runs in. |
| `helm_release_status` | Release status. |
| `schedule_names` | Names of created schedules. |
