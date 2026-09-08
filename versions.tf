# versions.tf
# Pins Terraform core and all provider versions used across the project.
# Version constraints are intentionally conservative to keep repeated runs
# reproducible while still allowing patch-level upgrades.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    # Two Kubernetes/Helm provider instances are configured (source + destination)
    # via provider aliases in providers.tf.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }

    # Used to generate a stable, DNS-safe suffix for globally-unique names
    # (e.g. the storage account name).
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Used to render the on-demand Velero Restore manifest to disk.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}
