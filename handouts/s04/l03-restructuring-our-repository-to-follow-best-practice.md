---
title: "Restructuring our repository to follow best practices"
kicker: "FLUX CD · SECTION 4 · LECTURE 3"
description: "This lecture covers how to restructure a Git repository using the monorepo pattern to manage multiple environments (staging and production) with Flux CD. The key concepts"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Restructuring our repository to follow best practices

*Section 4, Lecture 3 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Restructure a single-cluster manifest directory into a monorepo with `apps/base`, environment overlays, and `infrastructure/controllers`
- Move and rename existing manifests into the app-per-directory convention (`release.yaml`, `repository.yaml`, `kustomization.yaml`)
- Build Kustomize overlays for staging and production that reference shared base applications
- Bootstrap two separate Kubernetes clusters with `flux bootstrap gitlab`, each pointed at its own `clusters/<env>` path
- Verify and reach deployed applications through cluster-specific ports and ingress hostnames

## Overview

This lecture covers how to restructure a Git repository using the monorepo pattern to manage multiple environments (staging and production) with Flux CD. The key concepts are:

- **Directory structure**: Organizing applications in `apps/base`, environment overlays in `apps/staging` and `apps/production`, and infrastructure components in `infrastructure/controllers`
- **Kustomize patterns**: Using base configurations with environment-specific overlays
- **Multiple clusters**: Managing two separate Kubernetes clusters (staging and production) from a single repository
- **Flux CD Kustomization resources**: Declaring what Flux CD should deploy and where

## Before you run any of these commands

Every command below that names a Git account uses the placeholder
`<your-gitlab-username>`. Replace it with your own GitLab username, and
`<your-repo>` with the name of your own repository — these commands push to **your**
personal repository, not to anyone else's.

## Where we start

The previous lectures left every manifest in a single directory, next to the Flux
installation:

```
.
├── cluster-info.yaml
└── clusters/
    └── my-cluster/
        ├── apache-helm-release.yaml
        ├── bitnami-oci.yaml
        ├── busybox-helm-release.yaml
        ├── flux-operator-dashboard.yaml
        ├── flux-system/
        ├── gitlab-oci-repository.yaml
        ├── gitlab-oci-secret.yaml
        ├── localhttprepo.yaml
        ├── mysql-release.yaml
        └── nginx-ingress-controller.yaml
```

That works with one cluster and stops working the moment there are two.

## Directory Structure

The structure created in this lecture looks like this:

```
.
├── apps/
│   ├── base/
│   │   ├── apache/
│   │   ├── busybox/
│   │   └── mysql/
│   ├── staging/
│   └── production/
├── infrastructure/
│   └── controllers/
├── clusters/
│   ├── staging/
│   └── production/
├── staging-info.yaml
└── production-info.yaml
```

## Commands Reference

### 1. Create the directory structure

```bash
mkdir -p apps/base/apache apps/base/mysql apps/base/busybox
mkdir -p apps/staging apps/production
mkdir -p infrastructure/controllers
mkdir -p clusters/staging clusters/production
```

### 2. Move and rename the applications

The convention is the same for every application: `release.yaml` for the Helm release,
`repository.yaml` for the repository (and its pull secret, where there is one), and a
`kustomization.yaml` that lists them.

```bash
# Apache — the Helm release, then the repository and its secret combined into one file
git mv clusters/my-cluster/apache-helm-release.yaml apps/base/apache/release.yaml
cat clusters/my-cluster/gitlab-oci-repository.yaml clusters/my-cluster/gitlab-oci-secret.yaml > apps/base/apache/repository.yaml
git rm -q clusters/my-cluster/gitlab-oci-repository.yaml clusters/my-cluster/gitlab-oci-secret.yaml

# MySQL — the Bitnami OCI repository
git mv clusters/my-cluster/mysql-release.yaml apps/base/mysql/release.yaml
git mv clusters/my-cluster/bitnami-oci.yaml apps/base/mysql/repository.yaml

# BusyBox — the local HTTP repository
git mv clusters/my-cluster/busybox-helm-release.yaml apps/base/busybox/release.yaml
git mv clusters/my-cluster/localhttprepo.yaml apps/base/busybox/repository.yaml
```

> `repository.yaml` for Apache contains the registry pull secret. Do not print it to a
> terminal you are sharing, and keep the repository it lives in private.

Then add a `kustomization.yaml` to each of the three directories (the manifests are
below, and all three are identical).

### 3. Move the infrastructure components

```bash
git mv clusters/my-cluster/nginx-ingress-controller.yaml infrastructure/controllers/
git mv clusters/my-cluster/flux-operator-dashboard.yaml infrastructure/controllers/
```

Then add `infrastructure/controllers/kustomization.yaml` listing both files. There is no
`namespace:` line in it: each of these manifests already declares the namespace it
belongs in.

### 4. Prepare the cluster configuration files

```bash
git mv cluster-info.yaml production-info.yaml
cp production-info.yaml staging-info.yaml

# staging moves off the standard ports so both clusters can run on one machine
sed -i 's/hostPort: 80$/hostPort: 8888/; s/hostPort: 443$/hostPort: 8443/' staging-info.yaml
```

### 5. Remove the old cluster's directory, commit and push

```bash
git rm -r -q clusters/my-cluster
git add -A
git commit -m "Create monorepo directory structure following best practices"
git push
```

### 6. Create and bootstrap the two clusters

```bash
# the cluster the course used until now
kind delete cluster --name my-cluster

# the two that replace it
kind create cluster --name staging --config=staging-info.yaml
kind create cluster --name production --config=production-info.yaml

# your GitLab personal access token
export GITLAB_TOKEN='your-gitlab-token'

# Bootstrap staging
kubectl config use-context kind-staging
flux bootstrap gitlab \
  --owner=<your-gitlab-username> \
  --repository=<your-repo> \
  --branch=main \
  --path=clusters/staging \
  --token-auth \
  --personal

# Switch to production context and bootstrap
kubectl config use-context kind-production
flux bootstrap gitlab \
  --owner=<your-gitlab-username> \
  --repository=<your-repo> \
  --branch=main \
  --path=clusters/production \
  --token-auth \
  --personal

# Pull the files flux bootstrap pushed through its own clone
git pull
```

### 7. Verify the deployments

Flux has to install the ingress controller, the dashboard and three applications into
each new cluster, which takes a few minutes. Re-run the first command until every row
reads `True`.

```bash
# Check staging cluster
kubectl config use-context kind-staging
flux get helmreleases -A
kubectl get pods --all-namespaces
kubectl get ingress --all-namespaces

# Check production cluster
kubectl config use-context kind-production
flux get helmreleases -A
kubectl get pods --all-namespaces
kubectl get ingress --all-namespaces
```

## Final YAML Manifests

### Application: Apache — `apps/base/apache/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - repository.yaml
  - release.yaml
```

### Application: Apache — `apps/base/apache/release.yaml`

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
        name: gitlab-oci
  values:
    replicaCount: 1
```

### Application: Apache — `apps/base/apache/repository.yaml`

The two documents that were `gitlab-oci-repository.yaml` and `gitlab-oci-secret.yaml`,
now in one file. `.dockerconfigjson` is a base64-encoded Docker config holding your
registry username and token — base64 is not encryption, so this file belongs only in a
private repository.

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: gitlab-oci
  namespace: default
spec:
  interval: 10m
  type: oci
  url: oci://registry.gitlab.com/<your-gitlab-username>/<your-repo>
  secretRef:
    name: gitlab-oci-secret
---
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-oci-secret
  namespace: default
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64 of {"auths":{"registry.gitlab.com":{"auth":"<base64 of user:token>"}}}>
```

### Application: MySQL — `apps/base/mysql/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - repository.yaml
  - release.yaml
```

### Application: MySQL — `apps/base/mysql/repository.yaml`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: bitnami
  namespace: default
spec:
  interval: 1h
  type: oci
  url: oci://registry-1.docker.io/bitnamicharts
```

### Application: MySQL — `apps/base/mysql/release.yaml`

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
      version: '14.x.x'
      sourceRef:
        kind: HelmRepository
        name: bitnami
  values:
    # Bitnami moved its images out of the free Docker Hub catalog in 2025, so the
    # chart's default docker.io/bitnami/mysql tag no longer exists. The images are
    # still published under bitnamilegacy; pointing at them requires the chart's
    # own opt-in flag.
    global:
      security:
        allowInsecureImages: true
    image:
      repository: bitnamilegacy/mysql
    auth:
      rootPassword: "rootpass"
```

### Application: BusyBox — `apps/base/busybox/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - repository.yaml
  - release.yaml
```

### Application: BusyBox — `apps/base/busybox/repository.yaml`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: generic
  namespace: default
spec:
  interval: 1h
  url: http://chartrepo:8080
```

### Application: BusyBox — `apps/base/busybox/release.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: busybox
  namespace: default
spec:
  interval: 5m
  chart:
    spec:
      chart: busybox
      version: '0.1.0'
      sourceRef:
        kind: HelmRepository
        name: generic
```

### Staging Environment — `apps/staging/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - ../base/apache
  - ../base/busybox
  - ../base/mysql
```

The overlay references each application's **directory**, not `apps/base` itself:
Kustomize follows a `resources` entry into a directory only if that directory has a
`kustomization.yaml`, and `apps/base` has none.

### Production Environment — `apps/production/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - ../base/apache
  - ../base/busybox
  - ../base/mysql
```

### Infrastructure — `infrastructure/controllers/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - nginx-ingress-controller.yaml
  - flux-operator-dashboard.yaml
```

### Infrastructure — `infrastructure/controllers/nginx-ingress-controller.yaml`

The ingress controller, installed by Flux into every cluster that points at this
directory. The values are the ones a KinD cluster needs: the controller binds the node's
ports 80 and 443 directly, because KinD has no load balancer to hand out an external IP.

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 24h
  url: https://kubernetes.github.io/ingress-nginx
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 1h
  targetNamespace: ingress-nginx
  install:
    createNamespace: true
    remediation:
      retries: 2
  upgrade:
    remediation:
      retries: 2
  chart:
    spec:
      chart: ingress-nginx
      version: '4.x.x'
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
  values:
    controller:
      hostPort:
        enabled: true
      service:
        type: ClusterIP
      nodeSelector:
        ingress-ready: "true"
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Equal
          effect: NoSchedule
        - key: node-role.kubernetes.io/master
          operator: Equal
          effect: NoSchedule
      watchIngressWithoutClass: true
      admissionWebhooks:
        enabled: false
      publishService:
        enabled: false
      extraArgs:
        publish-status-address: localhost
```

### Infrastructure — `infrastructure/controllers/flux-operator-dashboard.yaml`

The Flux CD web UI from the previous section, deployed as a web server only so it never
takes over the bootstrap.

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: flux-operator
  namespace: flux-system
spec:
  interval: 1h0m0s
  type: oci
  url: oci://ghcr.io/controlplaneio-fluxcd/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: flux-web
  namespace: flux-system
spec:
  interval: 1h0m0s
  chart:
    spec:
      chart: flux-operator
      version: 0.60.0
      sourceRef:
        kind: HelmRepository
        name: flux-operator
  values:
    installCRDs: true
    web:
      enabled: true
      serverOnly: true
      ingress:
        enabled: true
        className: nginx
        hosts:
          - host: dashboard.local
            paths:
              - path: /
                pathType: Prefix
```

### Staging Applications — `clusters/staging/apps.yaml`

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m0s
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/staging
  prune: true
  wait: true
  timeout: 5m0s
```

### Staging Infrastructure — `clusters/staging/infrastructure.yaml`

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-controllers
  namespace: flux-system
spec:
  interval: 1h
  retryInterval: 1m
  timeout: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/controllers
  prune: true
  wait: true
```

### Production Applications — `clusters/production/apps.yaml`

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m0s
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/production
  prune: true
  wait: true
  timeout: 5m0s
```

### Production Infrastructure — `clusters/production/infrastructure.yaml`

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-controllers
  namespace: flux-system
spec:
  interval: 1h
  retryInterval: 1m
  timeout: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/controllers
  prune: true
  wait: true
```

### Staging Cluster Configuration — `staging-info.yaml`

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 8888
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
```

### Production Cluster Configuration — `production-info.yaml`

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
```

## Key Concepts Explained

### Why Monorepo Structure?

A monorepo pattern organizes all infrastructure code in a single repository, making it easy to:
- Track changes across all environments in one place
- Ensure consistency between staging and production
- Manage dependencies between applications
- Share base configurations and reduce duplication

### Kustomize Base and Overlays

- **Base**: The common configuration for an application (e.g., `apps/base/apache`)
- **Overlays**: Environment-specific customizations (e.g., `apps/staging`, `apps/production`)

This pattern allows you to maintain one source of truth for each application while applying environment-specific changes without duplication.

### Flux CD Kustomization Resource

The Flux CD Kustomization resource (`kustomize.toolkit.fluxcd.io/v1`) tells Flux CD to:
- Reconcile Kustomize manifests at a specified path in the repository
- Check for changes at a regular interval (e.g., every 10 minutes)
- Prune resources from the cluster if they are removed from the repository
- Wait for resources to be healthy before considering the reconciliation complete

### Applications versus infrastructure

The split is not cosmetic. `apps/` is deployed per environment, so staging and
production can diverge. `infrastructure/controllers/` is deployed identically to every
cluster, because an ingress controller is not something you want to be different in
staging. Each cluster gets one Flux Kustomization resource for each.

### Port Mapping for Multiple Clusters

Since both staging and production clusters run on the same machine (localhost), they must use different ports:
- **Staging**: Port 8888 (HTTP), 8443 (HTTPS)
- **Production**: Port 80 (HTTP), 443 (HTTPS)

This prevents port conflicts while allowing you to test both environments simultaneously.

## Accessing Applications

After both clusters are running, you can reach them through their ingress controllers:

- **Staging applications**: `http://localhost:8888` or `https://localhost:8443`
- **Production applications**: `http://localhost` or `https://localhost`

Both answer with the Apache default page. The HTTPS addresses use the ingress
controller's own self-signed certificate, so your browser will warn about it.

The Flux dashboard is served by name rather than on the root path, so add
`127.0.0.1 dashboard.local` to your `/etc/hosts` and then:

- **Staging dashboard**: `http://dashboard.local:8888`
- **Production dashboard**: `http://dashboard.local`

## Further Reading

- [Flux CD Kustomization Documentation](https://fluxcd.io/docs/components/kustomize/)
- [Kustomize Overlays and Bases](https://kubectl.docs.kubernetes.io/guides/introduction/kustomize/#bases-and-overlays)
- [Kustomization API Reference](https://fluxcd.io/docs/components/kustomize/api/)
- [Kind Cluster Configuration](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [Ways of Structuring Your Repositories](https://fluxcd.io/flux/guides/repository-structure/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
