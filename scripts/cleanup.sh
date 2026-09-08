#!/usr/bin/env bash
# cleanup.sh
# Tears down the Velero backup/restore setup. Runs in stages so you can stop at
# the level you need. Every destructive stage asks for confirmation.
#
# Usage:
#   ./scripts/cleanup.sh [--backups] [--velero] [--infra] [--all] [--yes]
#
# Stages (choose one or more):
#   --backups   Delete all Velero backups from object storage (SOURCE context).
#   --velero    Uninstall Velero (Helm) and delete the velero namespace on the
#               cluster your CURRENT kubectl context points at.
#   --infra     Run `terraform destroy` to remove ALL Azure resources this
#               project created (storage, identity, and clusters if created here).
#   --all       Do --backups, then --velero on both contexts, then --infra.
#   --yes       Skip interactive confirmations (use with care, e.g. in CI).
#
# Environment:
#   VELERO_NAMESPACE   (default: velero)
#   SOURCE_CONTEXT     kube context for the source cluster (for --all)
#   DEST_CONTEXT       kube context for the destination cluster (for --all)
#
# Examples:
#   ./scripts/cleanup.sh --velero                 # remove Velero from current cluster
#   ./scripts/cleanup.sh --backups --velero       # backups + Velero
#   SOURCE_CONTEXT=aks-source DEST_CONTEXT=aks-destination ./scripts/cleanup.sh --all

set -euo pipefail

VELERO_NAMESPACE="${VELERO_NAMESPACE:-velero}"
DO_BACKUPS=false
DO_VELERO=false
DO_INFRA=false
ASSUME_YES=false

info()  { printf '\033[0;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[0;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[0;33m[WARN]\033[0m  %s\n' "$*"; }
err()   { printf '\033[0;31m[FAIL]\033[0m  %s\n' "$*" >&2; }

if [ $# -eq 0 ]; then
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --backups) DO_BACKUPS=true ;;
    --velero)  DO_VELERO=true ;;
    --infra)   DO_INFRA=true ;;
    --all)     DO_BACKUPS=true; DO_VELERO=true; DO_INFRA=true ;;
    --yes)     ASSUME_YES=true ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

confirm() {
  # $1 = prompt
  if [ "$ASSUME_YES" = true ]; then return 0; fi
  read -r -p "$1 [type 'yes' to continue]: " reply
  [ "$reply" = "yes" ]
}

delete_backups() {
  info "Deleting ALL Velero backups in namespace '$VELERO_NAMESPACE' (context: $(kubectl config current-context))."
  if ! confirm "This permanently removes backup data from object storage."; then
    warn "Skipped backup deletion."
    return
  fi
  if command -v velero >/dev/null 2>&1; then
    velero backup delete --all --confirm -n "$VELERO_NAMESPACE" || warn "Some backups may not have been deleted."
    ok "Backup deletion requested. Velero removes objects asynchronously."
  else
    warn "velero CLI not found; skipping backup deletion."
  fi
}

uninstall_velero() {
  local ctx
  ctx="$(kubectl config current-context)"
  info "Uninstalling Velero (Helm release + namespace) on context: $ctx"
  if ! confirm "This removes Velero from cluster '$ctx'."; then
    warn "Skipped Velero uninstall on $ctx."
    return
  fi
  helm -n "$VELERO_NAMESPACE" uninstall velero 2>/dev/null || warn "Helm release 'velero' not found on $ctx."
  kubectl delete namespace "$VELERO_NAMESPACE" --wait=true 2>/dev/null || warn "Namespace '$VELERO_NAMESPACE' not found on $ctx."
  ok "Velero removed from $ctx."
}

destroy_infra() {
  warn "This runs 'terraform destroy' and removes ALL Azure resources managed here."
  warn "If create_clusters=true, this DELETES the AKS clusters as well."
  if ! confirm "Destroy all Terraform-managed infrastructure?"; then
    warn "Skipped terraform destroy."
    return
  fi
  if command -v terraform >/dev/null 2>&1; then
    if [ "$ASSUME_YES" = true ]; then
      terraform destroy -auto-approve
    else
      terraform destroy
    fi
    ok "terraform destroy completed."
  else
    err "terraform not found; cannot destroy infrastructure."
  fi
}

# --- Execution order: backups -> velero -> infra -------------------------------
if [ "$DO_BACKUPS" = true ]; then
  delete_backups
fi

if [ "$DO_VELERO" = true ]; then
  # If SOURCE/DEST contexts are provided (typically with --all), clean both.
  if [ -n "${SOURCE_CONTEXT:-}" ] || [ -n "${DEST_CONTEXT:-}" ]; then
    for ctx in "${SOURCE_CONTEXT:-}" "${DEST_CONTEXT:-}"; do
      [ -z "$ctx" ] && continue
      kubectl config use-context "$ctx" >/dev/null
      uninstall_velero
    done
  else
    uninstall_velero
  fi
fi

if [ "$DO_INFRA" = true ]; then
  destroy_infra
fi

ok "Cleanup finished."
