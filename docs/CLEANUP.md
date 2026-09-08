# Cleanup & Teardown

How to remove what this project created — from a light cleanup (just Velero) to a
full teardown (all Azure resources). Use the helper script or the manual steps.

> All destructive actions are irreversible. Back up anything you need first.

## Using the cleanup script

`scripts/cleanup.sh` runs in stages; each destructive stage asks for confirmation.

```bash
# Show help (no args)
./scripts/cleanup.sh

# Remove Velero from the cluster your CURRENT kubectl context points at
./scripts/cleanup.sh --velero

# Delete all backups (run with kubectl pointed at the SOURCE cluster)
./scripts/cleanup.sh --backups

# Full teardown across both clusters + destroy all infra
SOURCE_CONTEXT=aks-source DEST_CONTEXT=aks-destination \
  ./scripts/cleanup.sh --all
```

| Flag | Effect |
|------|--------|
| `--backups` | Delete all Velero backups from object storage (current context). |
| `--velero`  | Uninstall Velero (Helm) + delete the `velero` namespace. |
| `--infra`   | `terraform destroy` — removes all Azure resources (and clusters if created here). |
| `--all`     | `--backups`, then `--velero` on both contexts, then `--infra`. |
| `--yes`     | Skip confirmation prompts (use with care). |

## Manual teardown (equivalent steps)

### 1. Delete backups (optional)

```bash
kubectl config use-context aks-source
velero backup delete --all --confirm -n velero
```

### 2. Uninstall Velero from both clusters

```bash
for ctx in aks-source aks-destination; do
  kubectl config use-context "$ctx"
  helm -n velero uninstall velero
  kubectl delete namespace velero --wait
done
```

### 3. Remove the sample app (if deployed)

```bash
kubectl config use-context aks-source
kubectl delete -f examples/sample-app/

kubectl config use-context aks-destination
kubectl delete namespace sample-app-restored   # if you restored there
```

### 4. Destroy all infrastructure

```bash
terraform destroy
```

## What `terraform destroy` removes

- The Velero managed identity, its role assignment, and federated credentials.
- The blob container and storage account (**including any backups still in it**).
- The resource group (if `create_resource_group = true`).
- **The AKS clusters** (only if `create_clusters = true` — otherwise they are left untouched).

## Notes and gotchas

- **Backups outlive Velero.** Uninstalling Velero does not delete backup data in
  Blob storage. Delete backups first (step 1) if you want the container empty.
- **Soft-delete retention.** Blob soft-delete/versioning keeps deleted objects for
  the configured retention window even after `terraform destroy` removes the
  container. They are purged per Azure retention policy.
- **`prevent_deletion_if_contains_resources`** guards the backup resource group;
  ensure nothing outside this project lives in it before destroying.
- **Generated files.** Remove any rendered restore manifests: `rm -rf generated/`.
