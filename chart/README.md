# Local (vendored) Velero chart — fallback

This folder holds an optional **local copy** of the Velero Helm chart, used when
`use_local_chart = true`. It's a resilience fallback for when the remote
`vmware-tanzu` Helm repo is unreachable, yanked, or you need a pinned, auditable
copy of the chart in source control.

## What this does and does NOT solve

- **Solves:** the remote Helm *repository* being unavailable, or wanting a
  fixed, reviewable chart in the repo.
- **Does NOT solve:** container *image* pull failures (e.g. `ImagePullBackOff`
  on `bitnami/kubectl` or the Velero plugin). A local chart still points at the
  same container images. If your problem is image pulls, the fix is mirroring
  images into your own registry (e.g. Azure Container Registry), not vendoring
  the chart. See [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md).

## How to vendor the chart

Run this once from the repo root. It downloads and unpacks the chart into
`chart/velero/` (the default path the Terraform expects):

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Pull and unpack a specific chart version into ./chart
helm pull vmware-tanzu/velero --version 12.1.0 --untar --untardir ./chart
```

After this you should have:

```text
chart/
├── README.md            # this file
└── velero/              # unpacked chart (Chart.yaml, templates/, values.yaml, ...)
```

## How to enable it

In `terraform.tfvars`:

```hcl
use_local_chart = true
# Optional: only if you unpacked somewhere other than ./chart/velero
# local_chart_path = "/absolute/or/relative/path/to/velero"
```

Then:

```bash
terraform apply
```

When `use_local_chart = true`, the Helm release ignores `velero_helm_chart_version`
and installs from `local_chart_path` (default `./chart/velero`). All other values
(image tags, Workload Identity, schedules) are applied exactly the same way.

## Keeping it in sync

Re-run the `helm pull` command with a new `--version` whenever you bump
`velero_helm_chart_version`, so the local and remote paths stay equivalent.

## Note on version control

The unpacked `chart/velero/` directory is intentionally **not** committed by
default (see `.gitignore`). Vendor it on the machine that runs Terraform. If your
team prefers to commit it for full reproducibility, remove the ignore entry.
