#!/usr/bin/env bash
# validate.sh
# Pre-flight dependency and environment checks for the Velero backup/restore
# Terraform project. Run this before `terraform apply`.
#
# Usage:
#   ./scripts/validate.sh
#
# Exit codes:
#   0  all required checks passed
#   1  a required tool or configuration is missing

set -euo pipefail

# Minimum versions we validate against (informational; adjust as needed).
MIN_TERRAFORM="1.5.0"
MIN_KUBECTL="1.27.0"
MIN_HELM="3.12.0"

FAIL=0

info()  { printf '\033[0;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[0;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[0;33m[WARN]\033[0m  %s\n' "$*"; }
error() { printf '\033[0;31m[FAIL]\033[0m  %s\n' "$*"; FAIL=1; }

# Compare two dotted versions: returns 0 if $1 >= $2.
version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

check_tool() {
  local name="$1" min="$2" version_cmd="$3"
  if ! command -v "$name" >/dev/null 2>&1; then
    error "$name is not installed."
    return
  fi
  local current
  current="$(eval "$version_cmd" 2>/dev/null || echo "0.0.0")"
  if version_ge "$current" "$min"; then
    ok "$name $current (>= $min)"
  else
    warn "$name $current is older than recommended $min"
  fi
}

info "Checking required CLI tools..."
check_tool terraform "$MIN_TERRAFORM" "terraform version -json | grep -o '\"terraform_version\":\"[^\"]*' | cut -d'\"' -f4"
check_tool kubectl   "$MIN_KUBECTL"   "kubectl version --client -o json 2>/dev/null | grep -o '\"gitVersion\":\"v[^\"]*' | head -n1 | cut -d'\"' -f4 | tr -d 'v'"
check_tool helm      "$MIN_HELM"      "helm version --short | tr -d 'v' | cut -d'+' -f1"

if ! command -v az >/dev/null 2>&1; then
  error "Azure CLI (az) is not installed."
else
  ok "az $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo unknown)"
fi

if ! command -v velero >/dev/null 2>&1; then
  warn "velero CLI not found (needed for backup/restore scripts, not for terraform apply)."
else
  ok "velero $(velero version --client-only 2>/dev/null | grep -i version | head -n1 || echo present)"
fi

info "Checking Azure authentication..."
if az account show >/dev/null 2>&1; then
  SUB="$(az account show --query id -o tsv)"
  ok "Logged in to Azure (subscription: $SUB)"
else
  error "Not logged in to Azure. Run 'az login' (or configure a service principal / OIDC)."
fi

info "Checking Terraform configuration..."
if [ -f "terraform.tfvars" ]; then
  ok "terraform.tfvars found."
else
  warn "terraform.tfvars not found. Copy terraform.tfvars.example and edit it."
fi

if command -v terraform >/dev/null 2>&1; then
  if terraform fmt -check -recursive >/dev/null 2>&1; then
    ok "Terraform files are formatted."
  else
    warn "Terraform files need formatting. Run 'terraform fmt -recursive'."
  fi
fi

echo
if [ "$FAIL" -ne 0 ]; then
  error "One or more required checks failed. Resolve them before applying."
  exit 1
fi
ok "All required checks passed."
