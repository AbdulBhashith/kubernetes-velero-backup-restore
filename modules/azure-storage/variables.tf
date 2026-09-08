# modules/azure-storage/variables.tf

variable "name_prefix" {
  description = "Lowercase alphanumeric prefix for generated resource names."
  type        = string
}

variable "random_suffix" {
  description = "Random suffix appended to globally-unique names (e.g. storage account)."
  type        = string
}

variable "location" {
  description = "Azure region for the resource group and storage account."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name to create or reuse."
  type        = string
}

variable "create_resource_group" {
  description = "Create the resource group if true; otherwise reuse an existing one."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "account_tier" {
  description = "Storage account performance tier."
  type        = string
  default     = "Standard"
}

variable "account_replication_type" {
  description = "Storage account replication type."
  type        = string
  default     = "ZRS"
}

variable "blob_container_name" {
  description = "Name of the blob container for Velero backups."
  type        = string
  default     = "velero"
}

variable "soft_delete_retention" {
  description = "Blob soft-delete retention in days."
  type        = number
  default     = 30
}

variable "network_default_action" {
  description = "Default network firewall action (Allow or Deny)."
  type        = string
  default     = "Allow"
}

variable "allowed_ip_ranges" {
  description = "Public IP/CIDR ranges allowed when network_default_action = Deny."
  type        = list(string)
  default     = []
}

variable "tenant_id" {
  description = "Entra ID tenant ID."
  type        = string
}

variable "federated_identities" {
  description = <<-EOT
    Federated identity credentials to create on the managed identity, keyed by
    a stable name (e.g. source/destination).
      issuer  : AKS OIDC issuer URL.
      subject : Kubernetes subject (system:serviceaccount:<ns>:<sa>).
  EOT
  type = map(object({
    issuer  = string
    subject = string
  }))
}
