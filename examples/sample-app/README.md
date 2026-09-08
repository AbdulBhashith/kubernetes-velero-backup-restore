# Sample application — backup/restore test workload

A self-contained app in the `sample-app` namespace that exercises **every major
Kubernetes object type**, so you can prove Velero backs up and restores them all
(including persistent volumes).

## What's included

| File | Objects | Why |
|------|---------|-----|
| `01-namespace.yaml` | Namespace | The unit you back up/restore. |
| `02-config.yaml` | ConfigMap, Secret, ServiceAccount | Config + identity objects. |
| `03-deployment.yaml` | Deployment, Service | Stateless tier consuming the ConfigMap/Secret. |
| `04-statefulset.yaml` | StatefulSet, headless Service, PVC (via volumeClaimTemplates) + PV | **Persistent volume** backup/restore via CSI snapshot. |
| `05-daemonset.yaml` | DaemonSet | One pod per node. |
| `06-pvc-and-pod.yaml` | PersistentVolumeClaim, standalone Pod | Manually-created PVC/PV and a bare Pod. |
| `07-job.yaml` | Job | batch/v1 run-to-completion workload. |

Object types covered: **Namespace, Deployment, StatefulSet, DaemonSet, Pod, Job,
Service, PersistentVolumeClaim/PersistentVolume, ConfigMap, Secret, ServiceAccount.**

## Prerequisites

- Velero installed and healthy on both clusters (`velero backup-location get -n velero` shows `Available`).
- A default StorageClass on both clusters (AKS provides a CSI-backed one).
- For PV snapshot restore across clusters, a CSI driver + `VolumeSnapshotClass` on the destination.

---

## Step 1 — deploy the app (SOURCE cluster)

```bash
kubectl config use-context aks-source
kubectl apply -f examples/sample-app/
```

Wait for everything to be ready:

```bash
kubectl -n sample-app get all,pvc
kubectl -n sample-app rollout status deploy/web
kubectl -n sample-app rollout status statefulset/db
```

## Step 2 — write some data to verify later (SOURCE cluster)

The StatefulSet and the standalone Pod already write marker files on start. Confirm them:

```bash
kubectl -n sample-app exec db-0 -- cat /data/created-at.txt
kubectl -n sample-app exec standalone-writer -- cat /data/hello.txt
```

Note these values — after restore they must match.

## Step 3 — back it up (SOURCE cluster)

```bash
velero backup create sample-app-1 \
  --include-namespaces sample-app \
  --snapshot-volumes \
  --wait -n velero

velero backup describe sample-app-1 --details -n velero   # Phase: Completed
```

## Step 4 — restore on the other cluster (DESTINATION cluster)

```bash
kubectl config use-context aks-destination

# Confirm the backup is visible here (reads the same storage). Wait ~1 min if not.
velero backup get -n velero

# Restore. Map to a new namespace so it does not collide with anything.
velero restore create sample-app-restore-1 \
  --from-backup sample-app-1 \
  --namespace-mappings sample-app:sample-app-restored \
  --wait -n velero

velero restore describe sample-app-restore-1 --details -n velero   # Phase: Completed
```

## Step 5 — validate the restore (DESTINATION cluster)

```bash
# All objects recreated?
kubectl -n sample-app-restored get all,pvc,configmap,secret,serviceaccount,job

# Persistent data survived? These must match the values from Step 2.
kubectl -n sample-app-restored exec db-0 -- cat /data/created-at.txt
kubectl -n sample-app-restored exec standalone-writer -- cat /data/hello.txt
```

If the marker files match and pods are `Running`, the restore (including PVs) succeeded.

---

## Troubleshooting the restore

- **PVCs stuck `Pending`:** the StorageClass name differs on the destination. Either pre-create a matching class, or remap it with a Velero change-storageclass ConfigMap.
- **Volumes empty after restore:** ensure the backup used `--snapshot-volumes` and that CSI + a `VolumeSnapshotClass` exist on both clusters. As an alternative, enable the Velero node-agent (`enable_node_agent = true`) for filesystem-level backup.
- **DaemonSet pods missing on some nodes:** expected if node taints differ between clusters.

## Clean up

```bash
# SOURCE
kubectl config use-context aks-source
kubectl delete -f examples/sample-app/
velero backup delete sample-app-1 -n velero

# DESTINATION
kubectl config use-context aks-destination
kubectl delete namespace sample-app-restored
```
