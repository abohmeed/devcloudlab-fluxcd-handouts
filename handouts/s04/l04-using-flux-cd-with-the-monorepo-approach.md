---
title: "Using Flux CD with the Monorepo approach"
kicker: "FLUX CD · SECTION 4 · LECTURE 4"
description: "In this lecture, you learned how to structure a Git repository using the monorepo approach and deploy applications to multiple Kubernetes clusters using Flux CD and"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Using Flux CD with the Monorepo approach

*Section 4, Lecture 4 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Add a new application (podinfo) to an existing monorepo's `apps/base` directory
- Patch per-environment HelmRelease values with Kustomize's `patches` and JSON Patch operations (`replace`, `add`)
- Set different chart-version constraints for staging (a floating `>=` range) and production (a pinned version)
- Patch cluster-level Flux Kustomizations to add environment-specific ingress hostnames
- Diagnose a HelmRelease that installs successfully but briefly reports a failed revision because of ingress patch timing

## Overview

In this lecture, you learned how to structure a Git repository using the monorepo approach and deploy applications to multiple Kubernetes clusters using Flux CD and Kustomize. The monorepo keeps all infrastructure and application code in a single repository, making it ideal for small teams managing multiple environments.

Key concepts covered:
- **Monorepo structure:** All code (infrastructure, applications) lives in one repository.
- **Kustomize patches:** Override values for different environments (staging, production) without duplicating manifests.
- **Helm Release patches:** Customize Helm chart values per cluster using Kustomize patches.
- **Multi-cluster management:** Deploy the same application to staging and production with environment-specific configurations.

---

## Repository Layout

```
myfluxrepo-2026/
├── clusters/
│   ├── staging/
│   │   ├── flux-system/                 # Written by flux bootstrap
│   │   ├── infrastructure.yaml          # Patch dashboard ingress for staging
│   │   └── apps.yaml                    # Patch podinfo ingress for staging
│   └── production/
│       ├── flux-system/                 # Written by flux bootstrap
│       ├── infrastructure.yaml          # Patch dashboard ingress for production
│       └── apps.yaml                    # Patch podinfo ingress for production
├── infrastructure/
│   └── controllers/
│       ├── nginx-ingress-controller.yaml
│       ├── flux-operator-dashboard.yaml
│       └── kustomization.yaml           # References the controllers
└── apps/
    ├── base/
    │   └── podinfo/                     # New application added in this lecture
    │       ├── repository.yaml
    │       ├── release.yaml
    │       └── kustomization.yaml
    ├── staging/
    │   ├── podinfo-values.yaml          # Track the newest chart >= 6.14.0
    │   └── kustomization.yaml
    └── production/
        ├── podinfo-values.yaml          # Pin to 6.14.0 for stability
        └── kustomization.yaml
```

> If you ever add a `kustomization.yaml` directly inside `clusters/staging/` or
> `clusters/production/`, list `flux-system` in its `resources`. The
> Kustomization that `flux bootstrap` created watches that directory with
> `prune: true`, so whatever the file leaves out is deleted from the cluster —
> and `flux-system/` is Flux itself.

---

## Command Reference

### Kubernetes Context Management

```bash
# List available contexts
kubectl config get-contexts

# Switch to staging cluster
kubectl config use-context kind-staging

# Switch to production cluster
kubectl config use-context kind-production
```

### Reconcile Flux CD

```bash
# Force immediate reconciliation of Flux system
flux reconcile kustomization flux-system --with-source

# This triggers Flux to pull the latest Git changes and apply them to the cluster
```

### Verify Deployments

```bash
# List Helm releases in the cluster
helm list

# List Helm releases and filter for podinfo
helm list | grep podinfo

# Get all ingress objects (shows the hostnames for reaching the applications)
kubectl get ingress

# Inspect the sources and releases Flux is managing
flux get sources helm
flux get helmreleases
```

### View Flux Logs

```bash
# Show Flux reconciliation logs (useful for debugging)
flux logs --follow --all-namespaces
```

### Edit /etc/hosts

There is no DNS server in this lab, so the four hostnames have to be mapped by
hand on the machine your **browser** runs on.

```bash
# macOS and Linux
sudo nano /etc/hosts

# If the clusters run on this same machine, add these lines:
127.0.0.1 dashboard.staging
127.0.0.1 dashboard.production
127.0.0.1 podinfo.staging
127.0.0.1 podinfo.production

# If the clusters run on another machine or a VM, put that machine's IP
# address on all four lines instead of 127.0.0.1.

# Save and exit (Ctrl+X, then Y, then Enter in nano)

# On macOS, flush DNS cache after editing:
sudo dscacheutil -flushcache
```

The staging cluster answers on port 8080 (`http://podinfo.staging:8080`)
because both clusters share one host and only production could take port 80.

---

## Complete Final Manifests

### 1. Infrastructure Controllers Kustomization

**File:** `infrastructure/controllers/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - nginx-ingress-controller.yaml
  - flux-operator-dashboard.yaml
```

This Kustomization file groups the infrastructure components (NGINX ingress controller and Flux Operator dashboard) so they can be referenced as a single resource. There is no `namespace:` transformer here on purpose: each manifest already names the namespace it belongs in.

### 2. Staging Infrastructure Patch

**File:** `clusters/staging/infrastructure.yaml`

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-controllers
  namespace: flux-system
spec:
  interval: 1h
  retryInterval: 5m
  timeout: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/controllers
  prune: true
  wait: true
  patches:
    - patch: |
        - op: replace
          path: /spec/values/web/ingress/hosts/0/host
          value: "dashboard.staging"
      target:
        kind: HelmRelease
        name: flux-web
```

This uses Kustomize's JSON Patch operations to replace the dashboard ingress hostname for the staging cluster. The dashboard chart keeps its ingress settings under a `web` key, which is why the path has `/web/` in it.

### 3. Production Infrastructure Patch

**File:** `clusters/production/infrastructure.yaml`

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-controllers
  namespace: flux-system
spec:
  interval: 1h
  retryInterval: 5m
  timeout: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/controllers
  prune: true
  wait: true
  patches:
    - patch: |
        - op: replace
          path: /spec/values/web/ingress/hosts/0/host
          value: "dashboard.production"
      target:
        kind: HelmRelease
        name: flux-web
```

### 4. Podinfo Application Base Configuration

**File:** `apps/base/podinfo/repository.yaml`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: podinfo
  namespace: default
spec:
  interval: 5m
  type: oci
  url: oci://ghcr.io/stefanprodan/charts
```

Defines the Helm repository where the podinfo chart is located, and checks it for updates every 5 minutes. **`type: oci` is required**: the podinfo chart is published as an OCI artifact rather than in a classic HTTP chart repository with an `index.yaml`. Leave it out and source-controller rejects the URL with `invalid Helm repository URL: 'oci' URL scheme cannot be used with 'default' HelmRepository type`.

**File:** `apps/base/podinfo/release.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: default
spec:
  releaseName: podinfo
  chart:
    spec:
      chart: podinfo
      sourceRef:
        kind: HelmRepository
        name: podinfo
  interval: 50m
  values:
    ingress:
      enabled: true
      className: nginx
      hosts: []
```

The base release defines the core configuration. The `hosts` list is empty here and will be populated by environment-specific patches.

**File:** `apps/base/podinfo/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - repository.yaml
  - release.yaml
```

### 5. Staging Application Configuration

**File:** `apps/staging/podinfo-values.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: default
spec:
  chart:
    spec:
      version: ">=6.14.0"
```

This patch tells Flux to install the newest podinfo chart that is 6.14.0 or higher — `6.15.0` at the time of writing — and to move to anything newer as it is published, so staging always exercises the latest release.

**File:** `apps/staging/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - ../base/podinfo
patches:
  - path: podinfo-values.yaml
    target:
      kind: HelmRelease
```

**File:** `clusters/staging/apps.yaml` (snippet to add under `spec:`)

```yaml
  patches:
    - patch: |
        - op: add
          path: /spec/values/ingress/hosts/-
          value:
            host: podinfo.staging
            paths:
              - path: "/"
                pathType: Prefix
      target:
        kind: HelmRelease
        name: podinfo
```

This adds the staging ingress hostname. The `/-` syntax appends a new item to the hosts list. Note that podinfo puts `ingress` directly under `values`, so this path has no `web` segment — unlike the dashboard patch above.

### 6. Production Application Configuration

**File:** `apps/production/podinfo-values.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: default
spec:
  chart:
    spec:
      version: "6.14.0"
```

This pins the production chart to exactly version 6.14.0. Unlike staging's `>=6.14.0`, a pinned version only changes when you change this file.

**File:** `apps/production/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - ../base/podinfo
patches:
  - path: podinfo-values.yaml
    target:
      kind: HelmRelease
```

**File:** `clusters/production/apps.yaml` (snippet to add under `spec:`)

```yaml
  patches:
    - patch: |
        - op: add
          path: /spec/values/ingress/hosts/-
          value:
            host: podinfo.production
            paths:
              - path: "/"
                pathType: Prefix
      target:
        kind: HelmRelease
        name: podinfo
```

---

## Key Concepts Explained

### Kustomize Patch Operations

**replace:** Overwrites an existing value
```yaml
- op: replace
  path: /spec/values/web/ingress/hosts/0/host
  value: "dashboard.staging"
```

**add:** Adds a new value (especially useful for lists)
```yaml
- op: add
  path: /spec/values/ingress/hosts/-
  value:
    host: podinfo.staging
    paths:
      - path: "/"
        pathType: Prefix
```

The `-` at the end of the path means "append to this list."

A JSON Patch path has to exist before you can patch it: `replace` needs the key
to be there already (the dashboard's `hosts` list has one entry, so `hosts/0`
resolves), and `add` with `-` needs the list itself to exist (which is why the
base release declares `hosts: []`).

### Version Constraints

**`>=6.14.0`** (Staging): Flux installs the newest chart version that satisfies the constraint and upgrades whenever a newer one is published. There is no upper bound — if a 7.x chart appears, this constraint takes it. Write `>=6.14.0 <7.0.0` (or `~6.14`) if you want to stay inside the 6.x series.

**`6.14.0`** (Production): Pins to an exact version. Ensures stability and predictability. You control when to upgrade.

### Namespaces

Every resource in this lecture lands in the `default` namespace: the manifests say so, and the two overlays repeat it with a `namespace: default` transformer. That is why `helm list` and `kubectl get ingress` find everything without an `-n` flag.

### Base and Overlays

- **Base:** Contains the common, unpatched resources (repository, release definitions).
- **Staging/Production:** Contains environment-specific patches and Kustomization files that override base values.

This separation keeps your manifests DRY (Don't Repeat Yourself) and makes environment-specific changes explicit and manageable.

---

## Flux Reconciliation

When you run:
```bash
flux reconcile kustomization flux-system --with-source
```

Flux does the following:
1. Pulls the latest changes from your Git repository.
2. Evaluates all Kustomization resources.
3. Applies patches to resources.
4. Deploys or updates Helm releases based on the patched configurations.

---

## Troubleshooting

### Pod not starting?
```bash
# Check pod status and events
kubectl describe pod <pod-name>

# Check Helm release status
helm status podinfo
```

### Ingress not showing up?
```bash
# Wait a moment, then check again (ingress creation can take time)
kubectl get ingress -w

# Check Helm release values to confirm ingress is enabled
helm get values podinfo
```

### podinfo never appears in `helm list`?
```bash
# The Helm source first — an OCI URL without `type: oci` is rejected here
flux get sources helm

# Then the release, and the chart it is trying to pull
flux get helmreleases
```
A `chart pull error ... not found` means the version you pinned does not exist in the registry. Check the published versions before pinning one.

### `helm list` shows podinfo at revision 2, and the release "failed" once?

This is expected, and it fixes itself. The base HelmRelease enables the ingress with an **empty** `hosts` list, so the very first install renders an Ingress with no rules and the API server rejects it:

```
Helm install failed for release default/podinfo with chart podinfo@6.15.0:
  Ingress.networking.k8s.io "podinfo" is invalid: spec: Invalid value: null:
  either `defaultBackend` or `rules` must be specified
```

A second or two later the cluster-level `add` patch reaches the HelmRelease, the host appears, and Helm upgrades to revision 2 successfully:

```bash
helm history podinfo
# 1  superseded  podinfo-6.15.0  Release "podinfo" failed: ... Ingress ... invalid
# 2  deployed    podinfo-6.15.0  Upgrade complete
```

If revision 2 never arrives, the patch in `clusters/<env>/apps.yaml` is what to check — the target name must be `podinfo` and the path `/spec/values/ingress/hosts/-`.

### Flux reconciliation failing?
```bash
# Check Flux logs for errors
flux logs --follow

# Check Kustomization status
flux get kustomizations
```

---

## Further Reading

- **Flux CD Documentation:** https://fluxcd.io/docs/
- **Kustomize Official Guide:** https://kustomize.io/
- **Helm Chart Best Practices:** https://helm.sh/docs/chart_best_practices/
- **Podinfo Helm Chart:** https://github.com/stefanprodan/podinfo
- **JSON Patch RFC 6902:** https://tools.ietf.org/html/rfc6902 (the syntax Kustomize patches use)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
