# Getting Started

A step-by-step quickstart. For the full reference see the [root README](../README.md); for concepts see [ARCHITECTURE](./ARCHITECTURE.md).

## 1. Install the tools

| Tool | Minimum | Check |
|------|---------|-------|
| Terraform | 1.5.0 | `terraform version` |
| Azure CLI | 2.55+ | `az version` |
| kubectl | 1.27+ | `kubectl version --client` |
| Helm | 3.12+ | `helm version` |
| velero CLI | 1.14+ | `velero version --client-only` |

Run the bundled pre-flight check:

```bash
./scripts/validate.sh
```

## 2. Log in to Azure

```bash
az login
az account set --subscription <SUBSCRIPTION_ID>
```

## 3. Configure your inputs

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. The values you almost always change:

```hcl
subscription_id = "<your-subscription-id>"
tenant_id       = "<your-tenant-id>"
location        = "eastus"

source_cluster      = { name = "aks-source",      resource_group_name = "rg-aks-source",      location = "eastus" }
destination_cluster = { name = "aks-destination", resource_group_name = "rg-aks-destination", location = "eastus" }
```

> If your subscription restricts VM sizes (a common cause of a `VM size ... is not allowed` error), set `cluster_config.node_vm_size` to a permitted size, for example `Standard_D2als_v7` or `Standard_D2s_v7`.

## 4. Deploy

```bash
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

This creates (by default): both AKS clusters, the backup storage account + container, the managed identity with federated credentials, and Velero on both clusters with your backup schedules.

## 5. Connect kubectl to the new clusters

```bash
az aks get-credentials -g rg-aks-source      -n aks-source
az aks get-credentials -g rg-aks-destination -n aks-destination
```

## 6. Verify Velero is healthy

```bash
kubectl --context aks-source      -n velero get pods
kubectl --context aks-destination -n velero get pods
velero backup-location get -n velero        # expect PHASE = Available
```

## 7. Run your first backup

```bash
# point kubectl at the source cluster, then:
./scripts/backup.sh first-backup --include-namespaces default
```

See [BACKUP_RESTORE](./BACKUP_RESTORE.md) for backups and cross-cluster restores in depth.

## Choosing whether Terraform creates the clusters

| Setting | Behavior |
|---------|----------|
| `create_clusters = true` (default) | Terraform creates both clusters, cost-optimized, with OIDC + Workload Identity enabled. |
| `create_clusters = false` | Both clusters must already exist with OIDC + Workload Identity enabled; Terraform looks them up. |

## Next steps

- [ARCHITECTURE](./ARCHITECTURE.md) — how it all fits together, with diagrams
- [BACKUP_RESTORE](./BACKUP_RESTORE.md) — day-to-day operations
- [TROUBLESHOOTING](./TROUBLESHOOTING.md) — when something goes wrong
- [CLEANUP](./CLEANUP.md) — teardown when you're done
