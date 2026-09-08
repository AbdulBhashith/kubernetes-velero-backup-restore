# providers.tf
# Provider configuration for Azure control plane and for BOTH Kubernetes
# clusters (source + destination) using aliases.
#
# Design decisions:
# - azurerm/azuread authenticate via the ambient Azure CLI / environment
#   credentials (az login, OIDC in CI, or a service principal via env vars).
#   No secrets are placed in Terraform code.
# - The source and destination clusters are addressed through separate provider
#   aliases so a single `terraform apply` can operate on both clusters.
# - Cluster credentials are pulled from AKS data sources (see main.tf) so we do
#   not hardcode kubeconfig contents. This keeps the config passwordless and
#   works regardless of how the clusters were provisioned.

provider "azurerm" {
  features {
    resource_group {
      # Prevent accidental deletion of a resource group that still contains
      # resources managed outside this configuration.
      prevent_deletion_if_contains_resources = true
    }
  }

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}

# ---------------------------------------------------------------------------
# Source cluster providers
# ---------------------------------------------------------------------------
provider "kubernetes" {
  alias = "source"

  host                   = local.source_kube.host
  client_certificate     = base64decode(local.source_kube.client_certificate)
  client_key             = base64decode(local.source_kube.client_key)
  cluster_ca_certificate = base64decode(local.source_kube.cluster_ca_certificate)
}

provider "helm" {
  alias = "source"

  kubernetes {
    host                   = local.source_kube.host
    client_certificate     = base64decode(local.source_kube.client_certificate)
    client_key             = base64decode(local.source_kube.client_key)
    cluster_ca_certificate = base64decode(local.source_kube.cluster_ca_certificate)
  }
}

# ---------------------------------------------------------------------------
# Destination cluster providers
# ---------------------------------------------------------------------------
provider "kubernetes" {
  alias = "destination"

  host                   = local.dest_kube.host
  client_certificate     = base64decode(local.dest_kube.client_certificate)
  client_key             = base64decode(local.dest_kube.client_key)
  cluster_ca_certificate = base64decode(local.dest_kube.cluster_ca_certificate)
}

provider "helm" {
  alias = "destination"

  kubernetes {
    host                   = local.dest_kube.host
    client_certificate     = base64decode(local.dest_kube.client_certificate)
    client_key             = base64decode(local.dest_kube.client_key)
    cluster_ca_certificate = base64decode(local.dest_kube.cluster_ca_certificate)
  }
}
