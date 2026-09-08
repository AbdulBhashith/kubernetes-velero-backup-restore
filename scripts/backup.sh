#!/usr/bin/env bash
# backup.sh
# Trigger and verify an on-demand Velero backup on the SOURCE cluster.
#
# Prerequisites:
#   - kubectl context points at the SOURCE cluster
#       az aks get-credentials -g <rg> -n <source-cluster>
#   - velero CLI installed
#   - Velero installed by Terraform (namespace defaults to "velero")
#
# Usage:
#   ./scripts/backup.sh <backup-name> [options]
#
# Options (passed through to `velero backup create`):
#   --include-namespaces ns1,ns2
#   --exclude-namespaces ns1,ns2
#   --snapshot-volumes / --snapshot-volumes=false
#   --ttl 720h0m0s
#   --wait                (script always waits; kept for clarity)
#
# Example:
#   ./scripts/backup.sh app-backup-$(date +%Y%m%d) --include-namespaces production

set -euo pipefail

VELERO_NAMESPACE="${VELERO_NAMESPACE:-velero}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <backup-name> [velero backup create options...]" >&2
  exit 1
fi

BACKUP_NAME="$1"
shift

command -v velero >/dev/null 2>&1 || { echo "velero CLI not found." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found." >&2; exit 1; }

CURRENT_CTX="$(kubectl config current-context)"
echo "[INFO] Using kube context: $CURRENT_CTX"
echo "[INFO] Velero namespace   : $VELERO_NAMESPACE"
echo "[INFO] Creating backup     : $BACKUP_NAME"

# Confirm Velero is healthy and the storage location is available first.
if ! velero backup-location get -n "$VELERO_NAMESPACE" 2>/dev/null | grep -qi "Available"; then
  echo "[WARN] Default BackupStorageLocation is not reporting 'Available'." >&2
  echo "       Check: velero backup-location get -n $VELERO_NAMESPACE" >&2
fi

# Create the backup and wait for completion.
velero backup create "$BACKUP_NAME" \
  --namespace "$VELERO_NAMESPACE" \
  --wait \
  "$@"

echo
echo "[INFO] Backup summary:"
velero backup describe "$BACKUP_NAME" --namespace "$VELERO_NAMESPACE" --details || true

# Verify final phase.
PHASE="$(velero backup get "$BACKUP_NAME" -n "$VELERO_NAMESPACE" -o json 2>/dev/null \
  | grep -o '"phase":"[^"]*"' | head -n1 | cut -d'"' -f4 || echo "Unknown")"

echo
if [ "$PHASE" = "Completed" ]; then
  echo "[ OK ] Backup '$BACKUP_NAME' completed successfully."
  echo "       Objects are stored under the configured prefix in the backup container."
  echo "       Verify in Azure: az storage blob list --container-name <container> --account-name <account> --auth-mode login --prefix <prefix>/backups/$BACKUP_NAME"
  exit 0
else
  echo "[FAIL] Backup '$BACKUP_NAME' ended in phase: $PHASE" >&2
  echo "       Logs: velero backup logs $BACKUP_NAME -n $VELERO_NAMESPACE" >&2
  exit 1
fi
