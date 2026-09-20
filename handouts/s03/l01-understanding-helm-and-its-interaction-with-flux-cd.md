---
title: "Understanding Helm and its interaction with Flux CD"
kicker: "FLUX CD · SECTION 3 · LECTURE 1"
description: "How Helm's chart, release, and values model works, and how Flux CD's HelmRepository and HelmRelease objects replace running helm install by hand"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Understanding Helm and its interaction with Flux CD

*Section 3, Lecture 1 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- What a Helm chart, release, and values file are, and how they relate to each other
- Why running `helm install` by hand and GitOps don't mix
- What the HelmRepository and HelmRelease custom resources actually do
- How Flux CD keeps a Helm-managed deployment in sync with Git, and corrects drift automatically

## Helm: the package manager for Kubernetes

**Helm** plays the same role for Kubernetes that `apt`, `yum`, or `npm` play for Linux packages and Node.js libraries: it gives you a higher-level way to install, version, and configure applications instead of hand-writing every Kubernetes manifest.

Three terms carry the rest of this lecture:

| Term | What it is |
|---|---|
| **Chart** | A packaged, templated set of Kubernetes manifests (Deployments, Services, ConfigMaps, and so on) that describe an application |
| **Values** | The configuration you layer on top of a chart's defaults — image tag, replica count, resource limits, ingress host, and anything else the chart exposes as a variable |
| **Release** | A specific, named, installed instance of a chart with a particular set of values, running in a cluster |

You can install the same chart twice, with different values, and get two independent releases. A chart can describe anything from a single web app to a multi-component service made up of a database, a cache, and an API.

## From manual `helm install` to GitOps

Left on its own, Helm is a client-side tool: you run `helm install`, `helm upgrade`, or `helm rollback` from your terminal, and the cluster ends up in whatever state that command left it in. Nothing records *why* a release changed, and nothing notices if someone runs `kubectl edit` afterward and the live state quietly drifts away from what you last deployed.

**Flux CD** closes that gap by applying GitOps to Helm. In the GitOps model, your Git repository is the single source of truth for your system's state — so instead of running `helm install` yourself, you commit the chart source (or a reference to it) and the values you want, and Flux CD applies them to the cluster on your behalf. If the live cluster ever diverges from what's declared in Git, Flux CD brings it back in line automatically, without anyone running a Helm command by hand.

## The custom resources that connect Helm to Git

Flux CD implements this through two custom resources (CRDs), reconciled by its Helm and Source controllers:

| Resource | apiVersion | Purpose |
|---|---|---|
| `HelmRepository` | `source.toolkit.fluxcd.io/v1` | Points Flux at a chart source — an HTTP Helm repository, an OCI registry, or a Git repository — and tells it how often to check for new chart versions |
| `HelmRelease` | `helm.toolkit.fluxcd.io/v2` | Declares the desired state of a release: which chart, which version, which values, and how upgrades, rollbacks, and tests should behave |

A minimal pair looks like this:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 10m
  url: https://stefanprodan.github.io/podinfo
```

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
  namespace: default
spec:
  interval: 10m
  chart:
    spec:
      chart: podinfo
      version: "6.x"
      sourceRef:
        kind: HelmRepository
        name: podinfo
        namespace: flux-system
  values:
    replicaCount: 2
```

The `HelmRepository` is the address book entry — where the chart lives and how often to re-check it. The `HelmRelease` is the instruction — which chart from that address book to install, at what version, with what values, into which namespace. Commit both to Git, and Flux CD's controllers do the rest: pulling the chart, rendering it with your values, and applying the result to the cluster.

> **Since this video was recorded:** Flux's Helm APIs have moved on. `helm.toolkit.fluxcd.io/v2beta1` and `v2beta2` have both been removed — `HelmRelease` now uses `helm.toolkit.fluxcd.io/v2`, as shown above. `HelmRepository` has moved from `source.toolkit.fluxcd.io/v1beta2` to `source.toolkit.fluxcd.io/v1`. If the video refers to a `v2beta1`/`v2beta2` or `v1beta2` group, treat the versions on this page as the current ones.

## Automated upgrades, not just automated installs

Because the desired chart version lives in the `HelmRelease` object, Flux CD can also watch for new chart releases upstream and apply them automatically once you allow it to — the same reconciliation loop that corrects drift also picks up a newer chart version from the `HelmRepository` and rolls it out. That turns "keep this application up to date" from a recurring manual task into a policy you set once.

## Putting it together

- **Helm** defines *what* gets deployed: a chart, templated, with values layered on top, producing a release.
- **Git** defines the desired state: which chart, which version, which values — committed and version-controlled like any other code.
- **Flux CD** defines *how* that desired state reaches the cluster: continuously reconciling `HelmRepository` and `HelmRelease` objects, applying changes when Git changes, and correcting the cluster when it drifts.

The result is a Helm deployment workflow that is fully declarative and auditable: every change to what's running in your cluster traces back to a commit.

## Further reading

- [Helm charts](https://helm.sh/docs/topics/charts/)
- [Flux HelmRelease reference](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Flux HelmRepository reference](https://fluxcd.io/flux/components/source/helmrepositories/)
- [Flux Helm guide](https://fluxcd.io/flux/guides/helmreleases/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
