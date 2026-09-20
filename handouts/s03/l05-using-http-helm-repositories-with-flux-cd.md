---
title: "Using HTTP Helm repositories with Flux CD"
kicker: "FLUX CD · SECTION 3 · LECTURE 5"
description: "This lecture covers how to configure Flux CD to deploy applications using Helm charts stored in HTTP-based Helm repositories. You learned how to create both a"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Using HTTP Helm repositories with Flux CD

*Section 3, Lecture 5 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Define a HelmRepository resource pointing at an HTTP-based Helm chart repository
- Authenticate Flux CD to a private HTTP repository with a Kubernetes Secret via `secretRef`
- Deploy a chart from that repository using a HelmRelease
- Explain why a HelmRepository URL must resolve inside the cluster's own DNS, not on your workstation
- Reconcile and verify a HelmRelease and its HelmRepository source with `flux` and `kubectl`

## Overview

This lecture covers how to configure Flux CD to deploy applications using Helm charts stored in HTTP-based Helm repositories. You learned how to create both a `HelmRepository` resource (to define the chart repository) and a `HelmRelease` resource (to deploy a chart from that repository).

## Key Concepts

**HelmRepository Resource:** Defines where Flux CD should look for Helm charts. It includes the repository URL, polling interval, and optional authentication credentials.

**HelmRelease Resource:** Instructs Flux CD to install or upgrade a Helm chart from a repository. It specifies which chart to use, the version, the interval for reconciliation, and values overrides.

**Authentication:** HTTP repositories can be public or private. For private repositories, Flux CD can reference a Kubernetes Secret containing authentication credentials.

**The URL is resolved inside the cluster, not on your machine.** The component that fetches the chart index is Flux CD's `source-controller`, and the component that pulls the chart archive is `helm-controller`. Both run as pods, so both resolve the hostname in `spec.url` through the cluster's DNS service. That service does not read your workstation's `/etc/hosts` file and does not see your `kubectl port-forward` tunnels: a URL that works perfectly in your own terminal can still be unreachable for Flux CD. If the HelmRepository stays `READY=False` with a message like `dial tcp 127.0.0.1:80: connect: connection refused`, this is why — the name resolved, but it resolved to the pod itself. Use a name the cluster can resolve, such as an in-cluster Service (`http://chartrepo-server.chartrepo.svc.cluster.local:8080`) or a real DNS record pointing at your ingress controller.

## Commands Used

**Create a new Git branch for your changes:**
```bash
git checkout -b local-http-helm-repo
```

**Stage and commit your changes:**
```bash
git add -A
git commit -m "Creates the Helm repository and release"
```

**Push your branch to GitLab:**
```bash
git push --set-upstream origin local-http-helm-repo
```

**Reconcile Flux to pick up changes from your GitOps repository:**
```bash
flux reconcile kustomization flux-system --with-source
```

**Reconcile a specific Helm release.** `flux` looks in the `flux-system` namespace unless you tell it otherwise, and this HelmRelease is in `default`:
```bash
flux reconcile helmrelease busybox -n default
```

**View all Helm releases in the cluster:**
```bash
kubectl get helmrelease
```

**View all Helm charts that Flux CD has fetched:**
```bash
kubectl get helmchart
```

**View pods in the default namespace:**
```bash
kubectl get pods
```

## Complete Manifests

### HelmRepository and Secret

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: myhelmrepo
  namespace: default
spec:
  interval: 5m0s
  url: http://chartrepo.local
  secretRef:
    name: myhelmrepo-secret
---
apiVersion: v1
kind: Secret
metadata:
  name: myhelmrepo-secret
  namespace: default
stringData:
  username: chartuser
  password: mypass
```

### HelmRelease

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: busybox
  namespace: default
spec:
  interval: 1m
  chart:
    spec:
      chart: busybox
      version: 0.1.0
      sourceRef:
        kind: HelmRepository
        name: myhelmrepo
        namespace: default
      interval: 1m
```

## API Version Reference

This lecture uses the current Flux CD API versions:
- `source.toolkit.fluxcd.io/v1` — for HelmRepository resources
- `helm.toolkit.fluxcd.io/v2` — for HelmRelease resources

These versions are current as of Flux CD v2.7.0 and later. The previous versions (`v1beta2` and `v2beta1`) were removed and are no longer supported.

## Further Reading

- [Flux CD Helm Integration](https://fluxcd.io/flux/components/helm/)
- [HelmRepository API Reference](https://fluxcd.io/flux/components/source/helmrepositories/)
- [HelmRelease API Reference](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Helm Charts](https://helm.sh/docs/topics/charts/)
- [Using Secrets in Flux CD](https://fluxcd.io/flux/components/helm/helmreleases/#authentication)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
