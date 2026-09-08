# Backup & Restore Operations

Day-to-day operations for creating backups on the source cluster and restoring them onto the destination cluster. For the underlying flows see [ARCHITECTURE](./ARCHITECTURE.md#backup-flow).

- [Beginner walkthrough](#beginner-walkthrough-first-manual-backup--restore)
- [Backups](#backups)
- [Restores](#restores)
- [Verifying data landed in Blob storage](#verifying-data-landed-in-blob-storage)
- [Retention](#retention)

---

## Beginner walkthrough: first manual backup & restore

New to Velero? These exact steps back up an app on the **source** cluster and restore it on the **destination** cluster. Every command says which cluster to run it on.

### Before you start

You have run `terraform apply` successfully and have the `velero` and `kubectl` CLIs. Get credentials for both clusters:

```bash
az aks get-credentials -g rg-aks-source      -n aks-source      --overwrite-existing
az aks get-credentials -g rg-aks-destination -n aks-destination --overwrite-existing
kubectl config get-contexts
```

Switch clusters with `kubectl config use-context <name>` (use your real context names below).

### Part A — create something to back up (SOURCE)

```bash
kubectl config use-context aks-source
kubectl create namespace demo-app
kubectl -n demo-app create deployment web --image=nginx --replicas=2
kubectl -n demo-app create configmap site-config --from-literal=greeting=hello
kubectl -n demo-app get all
```

### Part B — back it up (SOURCE)

```bash
velero backup create demo-backup-1 --include-namespaces demo-app --wait -n velero
velero backup get -n velero                                  # STATUS = Completed
velero backup describe demo-backup-1 --details -n velero
```

> Helper script equivalent: `./scripts/backup.sh demo-backup-1 --include-namespaces demo-app`

### Part C — restore on the other cluster (DESTINATION)

```bash
kubectl config use-context aks-destination
velero backup get -n velero                                  # demo-backup-1 should appear (wait ~1 min if not)
velero restore create demo-restore-1 \
  --from-backup demo-backup-1 \
  --namespace-mappings demo-app:demo-app-restored \
  --wait -n velero
kubectl -n demo-app-restored get all                         # your app, on the new cluster
```

### Part D — clean up the demo

```bash
kubectl config use-context aks-source
kubectl delete namespace demo-app
velero backup delete demo-backup-1 -n velero

kubectl config use-context aks-destination
kubectl delete namespace demo-app-restored
```

### What just happened

- The backup captured the `demo-app` namespace and stored it in Blob under `source/backups/`.
- The destination reads that same location, so the backup was visible there without copying anything.
- The restore recreated the objects; the namespace mapping put them in `demo-app-restored` so nothing collided.

For an example covering **all** object types (PVs, StatefulSet, DaemonSet, Job…), see [examples/sample-app](../examples/sample-app/README.md).

---

## Backups

### Scheduled (declarative)

Schedules are defined in `backup_schedules` in `terraform.tfvars` and created by the Velero Helm chart on the source cluster during `terraform apply`.

```hcl
backup_schedules = {
  daily = {
    cron                = "0 2 * * *"
    included_namespaces = ["*"]
    excluded_namespaces = ["kube-system", "velero"]
    ttl                 = "720h0m0s" # 30 days
    snapshot_volumes    = true
  }
}
```

Inspect them on the source cluster:

```bash
velero schedule get -n velero
velero schedule describe daily -n velero
```

### Manual / on-demand

```bash
# kubectl context = source cluster
./scripts/backup.sh app-backup-$(date +%Y%m%d) --include-namespaces production
```

Or directly with the CLI:

```bash
velero backup create adhoc-1 \
  --include-namespaces production \
  --snapshot-volumes \
  --ttl 168h0m0s \
  --wait -n velero
```

### Watch progress

```bash
velero backup get -n velero
velero backup describe app-backup-YYYYMMDD --details -n velero   # look for Phase: Completed
velero backup logs app-backup-YYYYMMDD -n velero
```

---

## Restores

Restores run on the **destination** cluster, which reads the same Blob prefix as the source.

### Preconditions on the destination BEFORE restoring

- Velero installed and its `BackupStorageLocation` is `Available`.
- The backup is visible: `velero backup get -n velero` (Velero syncs from storage periodically).
- StorageClasses used by restored PVCs exist (or are remapped).
- For CSI restores, the CSI driver and a `VolumeSnapshotClass` exist on the destination.
- If mapping onto an existing namespace, that namespace already exists; otherwise Velero creates target namespaces automatically.

### Script (recommended)

```bash
# kubectl context = destination cluster
./scripts/restore.sh app-backup-YYYYMMDD \
  --namespace-mappings production:production-dr \
  --restore-volumes
```

### Declarative (Terraform-rendered manifest)

Set `enable_restore = true` and fill `restore_config` (including `backup_name`), then `terraform apply`. Terraform renders the manifest to `generated/restore-<name>.yaml` (it does not contact the cluster API). Apply it:

```bash
kubectl apply -f generated/restore-<restore_name>.yaml
velero restore describe <restore_name> -n velero --details
```

Velero `Restore` objects are one-shot; to run again, change `restore_name` and re-apply.

### Verify the restore

```bash
velero restore get -n velero
velero restore describe <restore-name> --details -n velero   # Phase: Completed
kubectl get pods -A
kubectl get pvc -A
```

---

## Verifying data landed in Blob storage

Passwordless listing with your Azure login:

```bash
az storage blob list \
  --account-name <storage_account_name> \
  --container-name velero \
  --prefix source/backups/app-backup-YYYYMMDD \
  --auth-mode login -o table
```

`<storage_account_name>` is a Terraform output:

```bash
terraform output storage_account_name
```

---

## Retention

- Each schedule's `ttl` controls how long its backups live (Velero garbage-collects expired backups).
- Blob **soft-delete** and **versioning** (default 30 days) protect against accidental or malicious deletion even after Velero removes a backup.
- To reduce storage cost, lower `storage_soft_delete_retention_days` or add lifecycle rules to tier old backups to Cool/Archive.
