# Module: aks-cluster

Creates one cost-optimized AKS cluster with OIDC issuer and Workload Identity enabled. Used twice by the root module (source and destination).

## What it creates

- `azurerm_resource_group` for the cluster
- `azurerm_kubernetes_cluster` with a single autoscaling system node pool

## Cost & design choices

| Choice | Why |
|--------|-----|
| `sku_tier = "Free"` | No control-plane uptime-SLA charge. |
| `Standard_D2als_v7` node | Low-cost 2 vCPU size (override if your subscription restricts sizes). |
| Autoscaler min 1 / max 2 | Idle clusters stay at one node. |
| 32 GiB OS disk | Minimizes managed-disk cost. |
| **Azure CNI Overlay** networking | Supported model (kubenet is deprecated after 2028-03-31). Pods get overlay IPs, so no VNet subnet consumption. |
| System-assigned identity | No extra identity resource to manage. |
| `oidc_issuer_enabled` + `workload_identity_enabled` | Required for passwordless Velero auth. |

`node_count` drift from the autoscaler is ignored via `lifecycle.ignore_changes`.

## Key inputs

| Name | Default | Description |
|------|---------|-------------|
| `cluster_name` | — | Cluster name. |
| `resource_group_name` | — | RG to create. |
| `location` | — | Region. |
| `node_vm_size` | `Standard_D2als_v7` | Node VM size. |
| `enable_auto_scaling` | `true` | Autoscaler on/off. |
| `min_node_count` / `max_node_count` | `1` / `2` | Autoscaler bounds. |
| `sku_tier` | `Free` | Control-plane tier. |
| `use_ephemeral_os_disk` | `false` | Ephemeral OS (needs large-cache VM). |
| `pod_cidr` | `10.244.0.0/16` | Azure CNI Overlay pod CIDR. |
| `service_cidr` | `10.0.0.0/16` | Kubernetes Service ClusterIP CIDR. |
| `dns_service_ip` | `10.0.0.10` | Cluster DNS IP (inside `service_cidr`). |

## Key outputs

| Name | Description |
|------|-------------|
| `oidc_issuer_url` | Used for Workload Identity federation. |
| `host`, `client_certificate`, `client_key`, `cluster_ca_certificate` | Kube connection (sensitive). |
| `cluster_id` | Cluster resource ID. |

## Notes

- **Networking:** uses Azure CNI Overlay (`network_plugin = "azure"`, `network_plugin_mode = "overlay"`). Kubenet is deprecated and unsupported after 2028-03-31. Ensure `pod_cidr`, `service_cidr`, and the VNet do not overlap; `dns_service_ip` must sit inside `service_cidr`.
- Some subscriptions restrict allowed VM sizes per region. If `terraform apply` returns `VM size ... is not allowed`, choose a permitted size from the error message.
- To harden, set `local_account_disabled = true` and use AAD RBAC instead of the local admin kubeconfig (not enabled here so the providers work out of the box).
