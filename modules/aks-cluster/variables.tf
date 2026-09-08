# modules/aks-cluster/variables.tf

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create for this AKS cluster."
  type        = string
}

variable "location" {
  description = "Azure region for the cluster."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the cluster API server. Defaults to cluster_name when null."
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "Kubernetes version. Null lets AKS pick the current default for the region."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "AKS control-plane SKU tier. 'Free' has no SLA charge (cheapest); 'Standard' adds a paid uptime SLA."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard, or Premium."
  }
}

# ---- Cost-oriented node pool sizing ----------------------------------------
variable "node_vm_size" {
  description = "VM size for the default node pool. Standard_D2als_v7 (2 vCPU/4GiB, AMD) is a low-cost general-purpose default. Note: some subscriptions restrict which sizes are allowed per region - if you hit a 'VM size not allowed' error, pick a permitted size from the error message (e.g. Standard_D2s_v7)."
  type        = string
  default     = "Standard_D2als_v7"
}

variable "node_count" {
  description = "Initial node count when autoscaling is disabled."
  type        = number
  default     = 1
}

variable "enable_auto_scaling" {
  description = "Enable the cluster autoscaler on the default node pool to minimize idle cost."
  type        = bool
  default     = true
}

variable "min_node_count" {
  description = "Minimum nodes when autoscaling is enabled."
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum nodes when autoscaling is enabled."
  type        = number
  default     = 2
}

variable "os_disk_size_gb" {
  description = "OS disk size in GiB. Kept small for cost; must fit the ephemeral cache of the chosen VM size when using Ephemeral OS."
  type        = number
  default     = 32
}

variable "use_ephemeral_os_disk" {
  description = "Use Ephemeral OS disks (no separate managed disk cost). Requires a VM size whose cache is large enough for os_disk_size_gb."
  type        = bool
  default     = false
}

# ---- Azure CNI Overlay networking -----------------------------------------
variable "pod_cidr" {
  description = "Overlay CIDR for pod IPs (Azure CNI Overlay). Not routable outside the cluster and does not consume VNet subnet space."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR for Kubernetes Service ClusterIPs. Must not overlap the VNet or pod_cidr."
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "IP for cluster DNS (kube-dns). Must be inside service_cidr."
  type        = string
  default     = "10.0.0.10"
}

variable "tags" {
  description = "Tags applied to the cluster and its resource group."
  type        = map(string)
  default     = {}
}
