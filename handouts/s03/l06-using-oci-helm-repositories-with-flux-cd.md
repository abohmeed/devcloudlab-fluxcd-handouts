---
title: "Using OCI Helm repositories with Flux CD"
kicker: "FLUX CD · SECTION 3 · LECTURE 6"
description: "OCI (Open Container Initiative) registries have become the default way to distribute Helm charts. Unlike traditional HTTP repositories that serve charts from a simple server"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Using OCI Helm repositories with Flux CD

*Section 3, Lecture 6 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Configure a HelmRepository with `type: oci` to pull charts from an OCI registry
- Deploy a chart from a public OCI registry, working around Bitnami's 2025 image relocation
- Package and push a Helm chart to a private OCI registry with `helm push`
- Authenticate Flux CD to a private OCI registry using a Docker-config Secret built from Helm's own credential store
- Verify an OCI HelmRepository with `flux get sources helm`, since `kubectl get helmrepository` shows no status for it

## Overview

OCI (Open Container Initiative) registries have become the default way to distribute Helm charts. Unlike traditional HTTP repositories that serve charts from a simple server using `index.yaml` files, OCI registries provide enhanced security features like digest-based references instead of tags, built-in vulnerability scanning, and chart signing capabilities.

Flux CD can connect to both public and private OCI registries to deploy Helm charts using GitOps. This lecture demonstrates both scenarios: pulling from a public registry (Bitnami) and pushing to and pulling from a private registry (GitLab Container Registry).

> **Placeholders in this document.** Wherever you see `<your-gitlab-username>`,
> `<your-repository>` or `<your-gitlab-token>`, substitute your own values — the
> examples will not work as written, because they point at a private registry.

## Key Concepts

### OCI vs. Traditional HTTP Repositories

- **OCI**: Uses digest references for version immutability, supports signing and scanning, requires authentication before push/pull
- **HTTP**: Uses `index.yaml` file, simpler setup, fewer security features

### OCI in Flux CD

- **HelmRepository resource**: Defines where Helm charts are located
  - `type: oci` specifies OCI protocol instead of HTTP
  - `url` format: `oci://registry-host/path/to/charts`
  - `secretRef` (optional): References Kubernetes secret with registry credentials

- **HelmRelease resource**: Deploys a chart from a HelmRepository
  - Same as HTTP-based releases, but references the OCI HelmRepository

## Full Working Example: Public OCI Repository

### 1. Create HelmRepository for Bitnami

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: mysql
  namespace: default
spec:
  type: oci
  interval: 5m0s
  url: oci://registry-1.docker.io/bitnamicharts
```

### 2. Create HelmRelease to Deploy MySQL

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: mysql
  namespace: default
spec:
  interval: 5m
  chart:
    spec:
      chart: mysql
      version: '9.10.9'
      sourceRef:
        kind: HelmRepository
        name: mysql
        namespace: default
      interval: 1m
  values:
    # Bitnami moved its images out of the free Docker Hub catalog in 2025, so the
    # chart's default docker.io/bitnami/mysql tag no longer resolves. The images
    # are still published under bitnamilegacy. Newer Bitnami charts also require
    # this opt-in flag before they will accept a non-default image repository;
    # chart 9.10.9 predates the flag and simply ignores it, so it is harmless here
    # and is kept so the manifest still works if you raise the chart version.
    global:
      security:
        allowInsecureImages: true
    image:
      repository: bitnamilegacy/mysql
    auth:
      username: "myuser"
      password: "mypassword"
      database: "mydatabase"
```

### 3. Verify Deployment

```bash
# Check the HelmRepository status
flux get sources helm -A

# Check the HelmRelease status (the install takes about a minute)
kubectl wait helmrelease/mysql --for=condition=ready --timeout=5m
kubectl get helmrelease

# Verify the pod is running
kubectl get pods

# Connect to the database
kubectl exec -it mysql-0 -- mysql -u myuser -pmypassword mydatabase
```

> **Why `flux get sources helm` and not `kubectl get helmrepository`?** An OCI
> HelmRepository is a *static* source: Flux never reconciles it, so it carries no
> status conditions and `kubectl get helmrepository` prints an empty READY column
> for it. That is normal, not a failure. `flux get sources helm` renders the
> verdict, and `kubectl get helmchart` shows the chart Flux actually pulled.
>
> The `-A` is not optional: these manifests put the repository in the `default`
> namespace, and without `-A` the command looks only in `flux-system` and answers
> `✗ no HelmRepository objects found in "flux-system" namespace`.

## Full Working Example: Private OCI Repository

### 1. Create and Package a Helm Chart

```bash
# Create a new chart
helm create apache
cd apache

# Update Chart.yaml
# Change appVersion to: 2.4.68  (the current GA release of the Apache httpd 2.4 branch)

# Update values.yaml
# Change image repository from nginx to httpd

# Package the chart
helm package .
```

### 2. Push Chart to GitLab Container Registry

```bash
# Login to GitLab registry (requires valid personal access token)
helm registry login -u <your-gitlab-username> registry.gitlab.com
# When prompted for password, paste your GitLab personal access token

# Push the packaged chart
helm push apache-0.1.0.tgz oci://registry.gitlab.com/<your-gitlab-username>/<your-repository>
```

### 3. Create Secret for Private Registry Access

`helm registry login` writes its credentials to **Helm's own registry store**, not
to `~/.docker/config.json`. On Helm 3.21 (the version used in this course) that is
the path below; `helm env | grep HELM_REGISTRY_CONFIG` prints it for your own
installation, so use that rather than assuming. The file format is the same
Docker config JSON a `kubernetes.io/dockerconfigjson` Secret expects, so only the
path differs.

First, encode that config:

```bash
cat ~/.config/helm/registry/config.json | base64 | tr -d "\n"
```

Then create the Kubernetes secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-credentials
  namespace: default
data:
  .dockerconfigjson: # paste the base64 output from above
type: kubernetes.io/dockerconfigjson
```

### 4. Create HelmRepository for Private Registry

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: gitlab
  namespace: default
spec:
  type: oci
  interval: 5m0s
  url: oci://registry.gitlab.com/<your-gitlab-username>/<your-repository>
  secretRef:
    name: gitlab-credentials
```

### 5. Create HelmRelease to Deploy Apache

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: apache
  namespace: default
spec:
  interval: 5m
  chart:
    spec:
      chart: apache
      version: '0.1.0'
      sourceRef:
        kind: HelmRepository
        name: gitlab
        namespace: default
      interval: 1m
```

### 6. Verify Private Repository Deployment

```bash
# Check all Helm sources (renders READY for OCI repositories; kubectl does not)
flux get sources helm -A

# The chart Flux actually pulled — this is the proof the Secret was accepted,
# because Flux only contacts the registry when it fetches the chart
kubectl get helmchart

# Check all HelmReleases
kubectl get helmrelease

# Verify pods are running
kubectl get pods
```

## Common Commands Reference

```bash
# Login to an OCI registry
helm registry login -u <username> <registry-host>

# Find out where Helm stores that credential
helm env | grep HELM_REGISTRY_CONFIG

# Push a Helm chart to an OCI registry
helm push <chart-file>.tgz oci://<registry-host>/<username>/<repo>

# Reconcile Flux CD to pick up changes faster
flux reconcile kustomization flux-system --with-source

# View Flux CD resources
flux get sources helm -A
kubectl get helmrelease
kubectl get helmchart

# Debug a HelmRelease
kubectl describe helmrelease <name>
kubectl logs -l app.kubernetes.io/name=<release-name>
```

## Further Reading

- [OCI Spec – Open Container Initiative](https://opencontainers.org/)
- [Helm Chart Distribution – OCI Support](https://helm.sh/docs/topics/registries/)
- [Flux CD HelmRepository Reference](https://fluxcd.io/flux/components/source/helmrepositories/)
- [Flux CD HelmRelease Reference](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Bitnami Helm Charts](https://github.com/bitnami/charts)
- [GitLab Container Registry](https://docs.gitlab.com/ee/user/packages/container_registry/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
