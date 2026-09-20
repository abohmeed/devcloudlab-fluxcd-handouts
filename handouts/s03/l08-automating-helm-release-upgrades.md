---
title: "Automating Helm Release upgrades"
kicker: "FLUX CD · SECTION 3 · LECTURE 8"
description: "This lecture explores how Flux CD automates Helm chart upgrades using"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Automating Helm Release upgrades

*Section 3, Lecture 8 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Choose between `reconcileStrategy: ChartVersion` and `Revision` depending on whether a chart's source is a Git repository
- Bound automatic upgrades from a Helm repository with a semantic-versioning constraint on `spec.chart.spec.version`
- Force a pod restart on a ConfigMap change with a checksum annotation on the Deployment template
- Pause and resume a HelmRelease's reconciliation with `suspend`
- Publish a new chart version to a private OCI registry and watch Flux CD pick it up

## Overview

This lecture explores how Flux CD automates Helm chart upgrades using two
different mechanisms, and how to pause either of them:

1. **Revision-based updates**: for a chart whose source is a **Git repository**,
   update the Helm release whenever the chart's source files change — no version
   bump needed.
2. **Version-based updates**: for a chart pulled from a **Helm repository**
   (HTTP or OCI), update when a new chart version is published, bounded by a
   semantic-versioning constraint.

You will also learn how to force a pod restart when a ConfigMap changes, using a
checksum annotation, and how to hold a release still with `suspend`.

> **The one rule that decides which mechanism you get.** `reconcileStrategy`
> applies to Git-sourced charts. `version` applies to Helm-repository-sourced
> charts — Flux ignores `spec.chart.spec.version` when the source reference is a
> `GitRepository` or a `Bucket`. Pick the source first, then the mechanism.

## Key Concepts

### Reconcile strategy

The `reconcileStrategy` field lives under `spec.chart.spec` in a HelmRelease and
decides when Flux CD produces a new chart artifact:

- **`ChartVersion`** (the default): a new artifact only when the `version` in
  `Chart.yaml` changes.
- **`Revision`**: a new artifact whenever the source revision changes — for a
  GitRepository, that means every commit that touches the chart.

### Semantic versioning (SemVer)

Semantic versioning uses three components: MAJOR.MINOR.PATCH

- **MAJOR**: incompatible API changes (breaking changes)
- **MINOR**: backward-compatible new functionality
- **PATCH**: backward-compatible bug fixes

In Flux CD, a constraint such as `>=9.0.0 <10.0.0` lets the release take every
9.x release published and stop before the next major.

### ConfigMap checksum annotation

Changing a ConfigMap does not restart the pods that mount it — that is
Kubernetes behaviour, not a Flux CD limitation. The usual fix is to make the
pod template itself change whenever the ConfigMap does:

```yaml
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

Put it under `spec.template.metadata.annotations` in the Deployment template,
**alongside the existing `labels:`**, not in place of them — the Service and the
Deployment's own selector match on those labels.

### The suspend parameter

`suspend: true` at the `spec` level of a HelmRelease stops Flux CD reconciling
it at all. No chart is resolved, no upgrade is attempted, whatever the source
publishes. Set it back to `false`, or delete the field, and the next
reconciliation catches up in one step.

## Common commands

### Git operations

```bash
# Check out the main branch and pull latest changes
git checkout main
git pull

# Create a new branch for your changes
git checkout -b branch-name

# Commit and push changes
git add -A
git commit -m "Your commit message"
git push --set-upstream origin branch-name

# Merge the branch back into main — Flux only watches the branch it was
# bootstrapped on, so work that stays on a feature branch never reaches it
git checkout main
git merge branch-name
git push origin main
```

### Flux CD operations

```bash
# Reconcile Flux CD to pick up changes immediately
flux reconcile kustomization flux-system --with-source

# The state of a Helm release, including whether it is suspended
flux get helmrelease <name> -n <namespace>

# Check Helm release status with Helm itself
helm list
helm list | grep <release-name>

# Get details of a specific Helm release
helm status <release-name>

# Uninstall a Helm release
helm uninstall <release-name> -n <namespace>
```

### Helm chart operations

```bash
# Package a Helm chart
helm package path/to/chart

# Log in to an OCI registry before pushing to it
helm registry login -u <your-username> registry.example.com

# Push a packaged chart to an OCI registry
helm push chart-name-version.tgz oci://registry.example.com/path

# Show a chart's values
helm show values <chart>

# Show a chart's metadata, resolving a version constraint
helm show chart oci://registry.example.com/path/mychart --version '>=9.0.0 <10.0.0'
```

## Complete example manifests

> Replace `<your-gitlab-username>` with your own GitLab username wherever it
> appears below.

### Nginx HelmRelease with the Revision strategy (Git source)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx
  namespace: default
spec:
  interval: 1m
  chart:
    spec:
      chart: ./charts/nginx
      version: 0.1.0
      reconcileStrategy: Revision
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
  values:
    indexHtml: |-
      <!doctype html>
      <html>
      <head>
        <title>Welcome to the page</title>
      </head>
      <body>
        <h1>Changing a ConfigMap should restart the pod</h1>
        <h2>This is the second line in the Welcome page</h2>
      </body>
      </html>
```

`name: flux-system` is the GitRepository that `flux bootstrap` creates. Unless
you have added another source of your own, it is the only one in the cluster.

### Nginx deployment template with the checksum annotation

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "nginx.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ include "nginx.name" . }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        app: {{ include "nginx.name" . }}
    spec:
      containers:
      - name: nginx
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        ports:
        - name: http
          containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: {{ include "nginx.fullname" . }}-html
```

### Nginx ConfigMap template

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "nginx.fullname" . }}-html
data:
  index.html: |
{{ .Values.indexHtml | indent 4 }}
```

The HelmRelease above sets `indexHtml`, this template reads it, and the
annotation in the Deployment hashes this rendered file. That is the whole chain:
change the value, the ConfigMap changes, the checksum changes, the pod restarts.

### MySQL: a public OCI Helm repository and a version range

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
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: mysql
  namespace: default
spec:
  interval: 1m
  chart:
    spec:
      chart: mysql
      version: '>=9.0.0 <10.0.0'
      sourceRef:
        kind: HelmRepository
        name: mysql
        namespace: default
      interval: 1m
  values:
    # Bitnami moved its images out of the free Docker Hub catalog in 2025, so
    # older charts point at tags that no longer resolve. The images are still
    # published under bitnamilegacy.
    global:
      security:
        allowInsecureImages: true
    image:
      repository: bitnamilegacy/mysql
    primary:
      persistence:
        enabled: false
    auth:
      username: "myuser"
      password: "mypassword"
      database: "mydatabase"
```

With that constraint, Flux resolves the newest chart inside major 9 — at the
time of recording, 9.23.0. Versions 10.0.0 and later exist in the same registry
and are skipped, which is the entire point of the constraint.

### Apache: a private OCI Helm repository and `suspend`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: apache
  namespace: default
spec:
  interval: 1m
  suspend: true
  chart:
    spec:
      chart: apache
      version: '>= 0.1.0 < 1.0.0'
      sourceRef:
        kind: HelmRepository
        name: gitlab
        namespace: default
      interval: 1m
```

The `gitlab` HelmRepository it refers to is the private OCI registry from the
earlier lecture:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: gitlab
  namespace: default
spec:
  type: oci
  interval: 5m0s
  url: oci://registry.gitlab.com/<your-gitlab-username>/myfluxrepo-2026
  secretRef:
    name: gitlab-credentials
```

Publishing a new chart version to it is two commands:

```bash
helm package .
helm push apache-0.1.1.tgz oci://registry.gitlab.com/<your-gitlab-username>/myfluxrepo-2026
```

While `suspend: true` is in place, that new version sits in the registry and
nothing happens. Change it to `suspend: false` — or remove the field — commit,
and the release moves to 0.1.1 on the next reconciliation.

## Further reading

- [Flux CD HelmRelease API reference](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Flux CD HelmChart API reference — where `version` and `reconcileStrategy` apply](https://fluxcd.io/flux/components/source/helmcharts/)
- [Semantic Versioning specification](https://semver.org/)
- [Helm chart best practices](https://helm.sh/docs/chart_best_practices/)
- [Kubernetes ConfigMaps documentation](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Flux CD Helm controller](https://fluxcd.io/flux/components/helm/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
