# Architecture

This document explains how the pieces fit together. Diagrams below use [Mermaid](https://mermaid.js.org/) (renders inline on GitHub). Editable **draw.io** versions of the main diagrams live in [docs/diagrams/](./diagrams/README.md) for polished exports.

- [System overview](#system-overview)
- [Terraform module dependency graph](#terraform-module-dependency-graph)
- [Passwordless authentication (Workload Identity)](#passwordless-authentication-workload-identity)
- [Backup flow](#backup-flow)
- [Restore flow](#restore-flow)
- [Apply-time ordering](#apply-time-ordering)

---

## System overview

One shared Azure Blob container is written to by the **source** cluster and read by the **destination** cluster. Both authenticate passwordlessly to the same user-assigned managed identity via Azure Workload Identity.

```mermaid
flowchart LR
    subgraph AZ["Azure Subscription"]
        subgraph RGB["Resource Group: backup"]
            SA["Storage Account<br/>(TLS1.2, infra encryption,<br/>soft-delete, versioning)"]
            CT["Blob Container: velero"]
            MI["User-Assigned<br/>Managed Identity"]
            RA["Role Assignment<br/>Storage Blob Data Contributor"]
            SA --> CT
            MI -. "granted" .-> RA
            RA -. "scoped to" .-> SA
        end

        subgraph SRC["Source AKS cluster"]
            VS["Velero + plugins"]
            SSA["ServiceAccount: velero<br/>(WI annotated)"]
            SCH["Schedule CRs"]
            VS --> SSA
            VS --> SCH
        end

        subgraph DST["Destination AKS cluster"]
            VD["Velero + plugins"]
            DSA["ServiceAccount: velero<br/>(WI annotated)"]
            VD --> DSA
        end
    end

    SSA -- "federated identity" --> MI
    DSA -- "federated identity" --> MI

    SCH -- "writes backups<br/>prefix: source/" --> CT
    VD -- "reads backups<br/>prefix: source/" --> CT

    classDef store fill:#e3f2fd,stroke:#1565c0;
    classDef id fill:#fff3e0,stroke:#e65100;
    class SA,CT store;
    class MI,RA,SSA,DSA id;
```

---

## Terraform module dependency graph

How the root module wires the child modules together.

```mermaid
flowchart TD
    ROOT["root module<br/>main.tf"]

    AKS_S["module.aks_source<br/>(aks-cluster)"]
    AKS_D["module.aks_destination<br/>(aks-cluster)"]
    STORE["module.azure_storage"]
    VEL_S["module.velero_source"]
    VEL_D["module.velero_destination"]
    REST["module.velero_restore<br/>(optional)"]

    ROOT --> AKS_S
    ROOT --> AKS_D
    ROOT --> STORE
    ROOT --> VEL_S
    ROOT --> VEL_D
    ROOT --> REST

    AKS_S -- "oidc_issuer_url" --> STORE
    AKS_D -- "oidc_issuer_url" --> STORE
    STORE -- "identity client_id + storage" --> VEL_S
    STORE -- "identity client_id + storage" --> VEL_D
    AKS_S -- "kube_config" --> VEL_S
    AKS_D -- "kube_config" --> VEL_D
    VEL_D --> REST
```

The clusters' OIDC issuer URLs feed the storage module (to create federated credentials), and the storage module's identity + account details feed both Velero installs. `create_clusters = false` swaps the two `aks-*` modules for `azurerm_kubernetes_cluster` data-source lookups; everything downstream is unchanged because it reads normalized `locals`.

---

## Passwordless authentication (Workload Identity)

No storage keys or secrets are stored anywhere. A Velero pod exchanges its Kubernetes service-account token for an Azure AD token, which grants blob access.

```mermaid
sequenceDiagram
    participant Pod as Velero Pod
    participant SA as K8s ServiceAccount token
    participant AAD as Entra ID (AAD)
    participant MI as Managed Identity
    participant Blob as Azure Blob

    Pod->>SA: projected SA token (OIDC)
    Pod->>AAD: token exchange (federated credential)
    Note over AAD,MI: issuer = cluster OIDC URL<br/>subject = system:serviceaccount:velero:velero
    AAD-->>Pod: Azure AD access token (as MI)
    Pod->>Blob: read/write with AAD token
    Note over MI,Blob: MI has Storage Blob Data Contributor<br/>scoped to the storage account
    Blob-->>Pod: 200 OK
```

---

## Backup flow

```mermaid
flowchart LR
    A["Schedule CR fires<br/>(or manual velero backup create)"] --> B["Velero collects<br/>K8s resources"]
    B --> C{"snapshot_volumes<br/>&amp; CSI enabled?"}
    C -- yes --> D["CSI VolumeSnapshots<br/>of PVs"]
    C -- no --> E["Skip volume data<br/>(or Kopia if node-agent on)"]
    B --> F["Upload resource manifests<br/>+ metadata"]
    D --> F
    E --> F
    F --> G["Blob container<br/>prefix: source/backups/&lt;name&gt;"]

    classDef ok fill:#e8f5e9,stroke:#2e7d32;
    class G ok;
```

Backups land under `source/backups/<backup-name>/` in the shared container. Each schedule has its own `ttl`, so old backups expire automatically.

---

## Restore flow

The destination cluster reads the same prefix, so the source's backups are visible there.

```mermaid
flowchart LR
    A["velero backup get<br/>(destination sees source backups)"] --> B["velero restore create<br/>--from-backup &lt;name&gt;"]
    B --> C["Velero downloads<br/>backup from Blob"]
    C --> D{"namespace<br/>mapping?"}
    D -- yes --> E["Recreate into<br/>mapped namespaces"]
    D -- no --> F["Recreate into<br/>original namespaces"]
    E --> G{"restore_pvs?"}
    F --> G
    G -- yes --> H["Restore PVs<br/>from snapshots"]
    G -- no --> I["Skip volume data"]
    H --> J["Workloads running<br/>on destination"]
    I --> J

    classDef ok fill:#e8f5e9,stroke:#2e7d32;
    class J ok;
```

---

## Apply-time ordering

Why a single `terraform apply` works even when the clusters are created in the same run.

```mermaid
sequenceDiagram
    participant TF as Terraform
    participant AKS as AKS clusters
    participant ST as Storage + Identity
    participant HELM as Helm (Velero)

    TF->>AKS: create source + destination clusters
    AKS-->>TF: oidc_issuer_url, kube_config
    TF->>ST: create storage, identity, role, federated creds
    ST-->>TF: identity client_id, account name
    TF->>HELM: install Velero (connects at APPLY time)
    Note over HELM: schedules rendered via chart values<br/>(no kubernetes_manifest = no plan-time API call)
    HELM-->>TF: release deployed
```

The key design choice: backup schedules are rendered through the Velero **Helm chart values**, not the `kubernetes_manifest` resource. `kubernetes_manifest` needs a live cluster API at *plan* time, which does not exist yet when the clusters are created in the same run. Helm connects at *apply* time, after the clusters exist.
