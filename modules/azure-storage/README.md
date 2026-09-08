# Module: azure-storage

Provisions the shared backup storage and the passwordless identity Velero uses on both clusters.

## What it creates

- `azurerm_resource_group` (create or reuse via `create_resource_group`)
- `azurerm_storage_account` (hardened — see below)
- `azurerm_storage_container` (private, holds all backups)
- `azurerm_user_assigned_identity` (Velero's identity)
- `azurerm_role_assignment` — **Storage Blob Data Contributor**, scoped to the storage account (least privilege, data plane only)
- `azurerm_federated_identity_credential` (one per cluster) binding each cluster's Velero ServiceAccount to the identity

## Security posture

| Setting | Value |
|---------|-------|
| TLS | 1.2 minimum, HTTPS only |
| Public blob (anonymous) access | Disabled |
| Infrastructure encryption | Enabled (double encryption at rest) |
| Blob versioning | Enabled |
| Blob + container soft-delete | Enabled (default 30 days) |
| Default auth | Entra ID (OAuth) preferred |
| Network firewall | Configurable (`Allow`/`Deny` + IP allow-list) |

No storage keys or secrets are exported. Velero authenticates via Workload Identity, so only the identity's **client ID** is surfaced.

## Key inputs

| Name | Description |
|------|-------------|
| `name_prefix`, `random_suffix` | Compose the globally-unique storage account name. |
| `blob_container_name` | Backup container name. |
| `soft_delete_retention` | Soft-delete window in days. |
| `network_default_action` / `allowed_ip_ranges` | Firewall lockdown. |
| `federated_identities` | Map of `{issuer, subject}` per cluster to federate. |

## Key outputs

| Name | Description |
|------|-------------|
| `storage_account_name` | Backup account name. |
| `blob_container_name` | Backup container. |
| `managed_identity_client_id` | Client ID annotated on Velero's ServiceAccount. |
| `managed_identity_principal_id` | Principal (object) ID of the identity. |

## Notes

- `resource_group_name` is intentionally **not** set on the federated credential — it is deprecated in azurerm v4; the credential is scoped by `parent_id`.
- For production, prefer `network_default_action = "Deny"` with Private Endpoints.
