# modules/azure-storage/main.tf
# Provisions the backup storage account + container and the passwordless
# identity (user-assigned managed identity + federated credentials) that
# Velero uses via Azure Workload Identity.

# ---------------------------------------------------------------------------
# Resource group (create or reuse).
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

locals {
  resource_group_name     = var.create_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
  resource_group_location = var.create_resource_group ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.existing[0].location

  # Storage account names: 3-24 chars, lowercase letters + digits only.
  storage_account_name = substr(lower("${var.name_prefix}bkp${var.random_suffix}"), 0, 24)
}

# ---------------------------------------------------------------------------
# Storage account for Velero backups.
# Security posture:
#  - HTTPS only, TLS 1.2 minimum.
#  - Public blob (anonymous) access disabled.
#  - Shared access keys still enabled because the Azure Blob backend can use
#    AAD, but disabling keys entirely is offered via the firewall + identity.
#  - Infrastructure encryption (double encryption at rest) enabled.
#  - Blob soft-delete + container soft-delete + versioning enabled to protect
#    backups from accidental/malicious deletion.
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "this" {
  name                     = local.storage_account_name
  resource_group_name      = local.resource_group_name
  location                 = local.resource_group_location
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  account_kind             = "StorageV2"

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true
  infrastructure_encryption_enabled = true

  # Prefer Entra ID (AAD) auth for portal/data-plane operations.
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.soft_delete_retention
    }

    container_delete_retention_policy {
      days = var.soft_delete_retention
    }
  }

  network_rules {
    default_action = var.network_default_action
    ip_rules       = var.allowed_ip_ranges
    # Allow trusted Azure services (Velero authenticates as a managed identity
    # which is treated as a trusted Azure service path).
    bypass = ["AzureServices"]
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Blob container that stores the backups (shared by source + destination).
# ---------------------------------------------------------------------------
resource "azurerm_storage_container" "this" {
  name                  = var.blob_container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# User-assigned managed identity used by Velero on BOTH clusters.
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "velero" {
  name                = "${var.name_prefix}-velero-identity"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  tags                = var.tags
}

# Least-privilege data-plane role: Velero only needs to read/write blob data in
# the backup container, not manage the account. Scope is the storage account.
resource "azurerm_role_assignment" "blob_data_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}

# ---------------------------------------------------------------------------
# Federated identity credentials: bind each cluster's Velero service account
# to the managed identity so pods get tokens with no stored secret.
# ---------------------------------------------------------------------------
resource "azurerm_federated_identity_credential" "velero" {
  for_each = var.federated_identities

  name = "velero-${each.key}"
  # The credential is scoped by the managed identity. In azurerm v4 the argument
  # was renamed from `parent_id` to `user_assigned_identity_id` (parent_id is
  # deprecated and removed in v5).
  user_assigned_identity_id = azurerm_user_assigned_identity.velero.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = each.value.issuer
  subject                   = each.value.subject
}
