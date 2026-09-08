# modules/velero-restore/variables.tf

variable "velero_namespace" {
  description = "Namespace where Velero is installed on the destination cluster."
  type        = string
  default     = "velero"
}

variable "restore_config" {
  description = "Restore configuration (see root variables.tf for field docs)."
  type = object({
    backup_name              = optional(string, "")
    restore_name             = optional(string, "restore-from-source")
    included_namespaces      = optional(list(string), ["*"])
    excluded_namespaces      = optional(list(string), [])
    excluded_resources       = optional(list(string), ["nodes", "events", "events.events.k8s.io"])
    namespace_mappings       = optional(map(string), {})
    restore_pvs              = optional(bool, true)
    existing_resource_policy = optional(string, "none")
  })
}
