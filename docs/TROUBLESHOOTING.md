# Troubleshooting

Common errors and how to resolve them. See also the [root README](../README.md).

- [Terraform / provisioning](#terraform--provisioning)
- [Velero / backup storage](#velero--backup-storage)
- [Restore issues](#restore-issues)
- [Useful commands](#useful-commands)

---

## Terraform / provisioning

### `VM size ... is not allowed in your subscription in location`

Your subscription restricts which VM sizes are available in that region. Pick a size from the list in the error and set it:

```hcl
cluster_config = {
  node_vm_size = "Standard_D2als_v7" # or another permitted 2-vCPU size
}
```

### `cannot create REST client: no client config`

Caused by `kubernetes_manifest` needing a live cluster API at plan time. This project avoids that resource (schedules go through Helm chart values, restores render to a file), so if you see it, confirm you are on the current code and have not reintroduced a `kubernetes_manifest` resource.

### `Argument is deprecated: resource_group_name` on federated identity credential

Informational only in current code (the argument was removed). If it appears, ensure `azurerm_federated_identity_credential` does not set `resource_group_name` — the credential is scoped by `parent_id`.

### Quota errors (`QuotaExceeded`, cores)

Request a quota increase for the VM family in the target region, reduce `max_node_count`, or choose a smaller size.

---

### `error converting YAML to JSON: did not find expected key`

Malformed Helm values, historically caused by `indent()` not indenting the first line of the `schedules` block. Current code encodes the whole key with `yamlencode({ schedules = ... })`, which is uniform and valid. If you see this, ensure the template uses `${schedules_block}` at column 0 (not a hand-written `schedules:` followed by an indented block).

### `velero-upgrade-crds` / CRD job stuck on `docker.io/bitnami/kubectl` ImagePullBackOff

The chart's CRD-management job used `docker.io/bitnami/kubectl`, whose tags became unreliable after Bitnami's 2025 Docker Hub repo migration — pinned tags like `1.35` now fail to pull.

Fixed in this project by pinning the job image to `registry.k8s.io/kubectl` and disabling the CRD-upgrade job (`upgradeCRDs: false`). If you still see it, your cluster is running an **old Velero release** that predates this change — you must fully remove it (see below) so the new values apply. You can tune the image with `kubectl_image_tag`.

### `IMDSUnreachable: connection timed out`

The Velero pod is trying to reach the Instance Metadata Service (169.254.169.254) instead of using Workload Identity. This means the Workload Identity token was not injected. Check:

1. Workload Identity is enabled on the cluster (created clusters enable it; for existing clusters run `az aks update --enable-oidc-issuer --enable-workload-identity`).
2. The mutating webhook is running: `kubectl get pods -n kube-system | grep azure-wi-webhook`.
3. The Velero pod has the label and the injected env vars:
   ```bash
   kubectl -n velero get pod -l app.kubernetes.io/name=velero -o yaml | grep -E "azure.workload.identity/use|AZURE_CLIENT_ID|AZURE_FEDERATED_TOKEN_FILE"
   ```
   If `AZURE_FEDERATED_TOKEN_FILE` is missing, the webhook did not mutate the pod — the label was not present when the pod was created. Recreate the pod: `kubectl -n velero rollout restart deploy/velero`.

### Velero pod stuck in `Init:ImagePullBackOff` (plugin image)

The Velero pod's **init container** (a plugin image) cannot be pulled. Almost always a **nonexistent image tag**.

```bash
kubectl -n velero describe pod -l app.kubernetes.io/name=velero | grep -A3 -i "failed to pull\|Back-off"
```

The `velero-plugin-for-microsoft-azure` tag must actually exist in the registry **and** match the Velero server version. Use a verified pairing:

| `velero_plugin_azure_tag` | `velero_image_tag` | `velero_helm_chart_version` |
|---------------------------|--------------------|-----------------------------|
| `v1.12.0` | `v1.16.0` | `12.1.0` (default) |
| `v1.13.0` | `v1.17.0` | `13.x` |

`v1.11.0` was **never published** — do not use it. After fixing the tags, uninstall the failed release and re-apply (see next entry).

### `helm_release ... timed out waiting for the condition` / `failed pre-install`

The Velero pod did not become ready within the Helm `timeout`. On a fresh single-node cluster this is usually slow image pulls for the plugin init containers.

1. A **failed release may be left behind** (you'll see `release "" ... failed status`). Clean it up before re-applying:
   ```bash
   # against the affected cluster
   helm -n velero list --all
   helm -n velero uninstall velero        # if a failed/pending release exists
   kubectl delete namespace velero --wait # optional: start clean
   ```
2. Re-run `terraform apply`. The modules use `timeout = 900`, `cleanup_on_fail = true`, and `replace = true` to be resilient.
3. If it still times out, inspect why the pod is not ready:
   ```bash
   kubectl -n velero get pods
   kubectl -n velero describe pod -l app.kubernetes.io/name=velero
   kubectl -n velero logs -l app.kubernetes.io/name=velero --all-containers
   ```

## Velero / backup storage

### `BackupStorageLocation` is not `Available`

Almost always an identity/authentication problem. Check in order:

1. The Velero ServiceAccount is annotated with the correct managed identity client ID:
   ```bash
   kubectl -n velero get sa velero -o yaml | grep client-id
   terraform output managed_identity_client_id
   ```
2. The federated credential `subject` matches `system:serviceaccount:velero:velero` and its `issuer` equals the cluster OIDC issuer URL.
3. The managed identity has **Storage Blob Data Contributor** on the storage account.
4. The pod has the workload-identity label and the webhook is running:
   ```bash
   kubectl -n velero get pod -l app.kubernetes.io/name=velero -o yaml | grep azure.workload.identity/use
   ```

### `AADSTS70021` / token exchange errors

The OIDC issuer is not enabled on the cluster, or the federated credential issuer URL does not match. For created clusters this is enabled automatically; for existing clusters:

```bash
az aks update -g <rg> -n <cluster> --enable-oidc-issuer --enable-workload-identity
```

### `PartiallyFailed`: `failed to get VolumeSnapshotClass for provisioner disk.csi.azure.com`

The backup captured all resources but could not snapshot PVCs because there is no
`VolumeSnapshotClass` that Velero can use. Velero needs a class that matches the
PVC's CSI driver **and** carries the label `velero.io/csi-volumesnapshot-class: "true"`.

Fix (apply on BOTH clusters — source to snapshot, destination to restore):

```bash
kubectl --context aks-source      apply -f examples/volumesnapshotclass-azure-disk.yaml
kubectl --context aks-destination apply -f examples/volumesnapshotclass-azure-disk.yaml
```

This project also creates the class automatically via the Velero Helm release
(`extraObjects`) when `enable_csi_snapshots = true`, so re-running `terraform apply`
adds it on both clusters. Verify:

```bash
kubectl get volumesnapshotclass
kubectl get volumesnapshotclass -l velero.io/csi-volumesnapshot-class=true
```

Then re-run the backup:

```bash
velero backup create sample-app-2 --include-namespaces sample-app --snapshot-volumes --wait -n velero
```

### Backup finishes as `PartiallyFailed` (other causes)

```bash
velero backup logs <name> -n velero
velero backup describe <name> --details -n velero
```

Common causes: a resource type that cannot be serialized, a PV without a working CSI snapshot path, or RBAC gaps. Consider excluding the offending resource with `excluded_resources`.

### PV snapshots are skipped

- `snapshot_volumes` is `false` on the schedule/backup, or
- CSI is not enabled (`enable_csi_snapshots`), or
- no `VolumeSnapshotClass` exists for the CSI driver. Enable the node-agent (`enable_node_agent = true`) for filesystem-level backups of volumes that lack CSI snapshot support.

---

## Restore issues

### Backup not visible on the destination

```bash
velero backup-location get -n velero        # must be Available
velero backup get -n velero
```

If missing, confirm the destination `BackupStorageLocation` prefix matches the source `backup_prefix`. Velero syncs from storage periodically; `scripts/restore.sh` waits and retries.

### PVCs stay `Pending` after restore

The StorageClass referenced by the PVC does not exist on the destination, or the CSI driver differs. Pre-create matching StorageClasses, or remap them, and ensure the CSI driver + `VolumeSnapshotClass` exist.

### Conflicts with existing resources

Set the restore policy:

```hcl
restore_config = {
  existing_resource_policy = "update" # or "none"
}
```

---

## Useful commands

```bash
# Velero server logs
kubectl -n velero logs deploy/velero

# Node-agent logs (if enabled)
kubectl -n velero logs -l name=node-agent

# Everything Velero knows
velero backup get -n velero
velero restore get -n velero
velero schedule get -n velero
velero backup-location get -n velero

# Terraform state of key outputs
terraform output
```
