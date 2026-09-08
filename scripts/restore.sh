#!/usr/bin/env bash
# restore.sh
# Restore a backup onto the DESTINATION cluster and verify the result.
#
# Prerequisites:
#   - kubectl context points at the DESTINATION cluster
#       az aks get-credentials -g <rg> -n <destination-cluster>
#   - velero CLI installed
#   - Velero installed on the destination by Terraform, pointed at the SAME
#     storage/prefix as the source (so the backup is visible here).
#
# Usage:
#   ./scripts/restore.sh <backup-name> [options]
#
# Options:
#   --restore-name NAME                 (default: <backup-name>-restore-<ts>)
#   --namespace-mappings src1:dst1,src2:dst2
#   --include-namespaces ns1,ns2
#   --exclude-namespaces ns1,ns2
#   --exclude-resources r1,r2
#   --restore-volumes / --restore-volumes=false
#   --existing-resource-policy none|update
#
# Example:
#   ./scripts/restore.sh app-backup-20260908 \
#       --namespace-mappings production:production-dr \
#       --restore-volumes
#
# Preconditions on the destination cluster before running:
#   - The referenced backup must be visible: `velero backup get`.
#   - StorageClasses used by restored PVCs must exist (or be remapped).
#   - For CSI restores, the CSI driver + VolumeSnapshotClass must be installed.
#   - Namespaces that you map onto EXISTING namespaces must already exist;
#     otherwise Velero creates target namespaces automatically.

set -euo pipefail

VELERO_NAMESPACE="${VELERO_NAMESPACE:-velero}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <backup-name> [options...]" >&2
  exit 1
fi

BACKUP_NAME="$1"
shift

command -v velero >/dev/null 2>&1 || { echo "velero CLI not found." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found." >&2; exit 1; }

# Parse a couple of convenience flags; unrecognized flags pass through.
RESTORE_NAME="${BACKUP_NAME}-restore-$(date +%Y%m%d%H%M%S)"
PASS_THROUGH=()
while [ $# -gt 0 ]; do
  case "$1" in
    --restore-name)
      RESTORE_NAME="$2"; shift 2 ;;
    *)
      PASS_THROUGH+=("$1"); shift ;;
  esac
done

CURRENT_CTX="$(kubectl config current-context)"
echo "[INFO] Using kube context : $CURRENT_CTX"
echo "[INFO] Velero namespace    : $VELERO_NAMESPACE"
echo "[INFO] Source backup       : $BACKUP_NAME"
echo "[INFO] Restore name        : $RESTORE_NAME"

# Ensure the backup is visible on this (destination) cluster.
echo "[INFO] Verifying backup is visible on this cluster..."
if ! velero backup get "$BACKUP_NAME" -n "$VELERO_NAMESPACE" >/dev/null 2>&1; then
  echo "[WARN] Backup '$BACKUP_NAME' not listed yet. Forcing a storage sync..." >&2
  # Velero syncs backups from object storage periodically; give it a moment.
  sleep 30
  if ! velero backup get "$BACKUP_NAME" -n "$VELERO_NAMESPACE" >/dev/null 2>&1; then
    echo "[FAIL] Backup '$BACKUP_NAME' is not visible on the destination cluster." >&2
    echo "       Confirm the BackupStorageLocation prefix matches the source prefix," >&2
    echo "       and that the location is Available: velero backup-location get -n $VELERO_NAMESPACE" >&2
    exit 1
  fi
fi

# Create the restore and wait.
velero restore create "$RESTORE_NAME" \
  --from-backup "$BACKUP_NAME" \
  --namespace "$VELERO_NAMESPACE" \
  --wait \
  "${PASS_THROUGH[@]}"

echo
echo "[INFO] Restore summary:"
velero restore describe "$RESTORE_NAME" --namespace "$VELERO_NAMESPACE" --details || true

PHASE="$(velero restore get "$RESTORE_NAME" -n "$VELERO_NAMESPACE" -o json 2>/dev/null \
  | grep -o '"phase":"[^"]*"' | head -n1 | cut -d'"' -f4 || echo "Unknown")"

echo
case "$PHASE" in
  Completed)
    echo "[ OK ] Restore '$RESTORE_NAME' completed successfully."
    echo "       Verify workloads: kubectl get pods -A"
    exit 0 ;;
  PartiallyFailed)
    echo "[WARN] Restore '$RESTORE_NAME' partially failed. Review warnings/errors:" >&2
    echo "       velero restore logs $RESTORE_NAME -n $VELERO_NAMESPACE" >&2
    exit 2 ;;
  *)
    echo "[FAIL] Restore '$RESTORE_NAME' ended in phase: $PHASE" >&2
    echo "       velero restore logs $RESTORE_NAME -n $VELERO_NAMESPACE" >&2
    exit 1 ;;
esac
