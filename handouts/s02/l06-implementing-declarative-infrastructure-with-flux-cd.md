---
title: "Implementing declarative infrastructure with Flux CD"
kicker: "FLUX CD · SECTION 2 · LECTURE 6"
description: "How Flux CD turns manifests, Helm releases and Kustomize overlays committed to Git into a continuously reconciled cluster state."
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Implementing declarative infrastructure with Flux CD

*Section 2, Lecture 6 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- The difference between declarative and imperative infrastructure, and why Flux CD is built entirely around the declarative model
- How Flux's controllers continuously reconcile your cluster's actual state with the desired state stored in Git
- What bootstrapping does to a cluster and why it is the first step of any Flux setup
- How to declare infrastructure three ways — plain Kubernetes manifests, Helm releases, and Kustomize overlays
- What Image Automation does and why it removes a class of manual manifest edits

## Declarative vs. imperative

In an **imperative** model, you tell the system exactly what to do, step by step: run this command, then that one. In a **declarative** model, you describe the state you want, and something else is responsible for making it real and keeping it that way.

| | Imperative | Declarative |
|---|---|---|
| You specify | The steps to reach a state | The desired end state |
| Who acts | You, one command at a time | A controller, continuously |
| Example | `kubectl scale deployment/web --replicas=3` | `replicas: 3` committed to Git |
| Drift | Nothing corrects it automatically | Detected and reconciled automatically |
| Source of truth | Whatever command ran last | The Git repository |

Flux CD is a **declarative** tool: you never tell it what to do. You tell it what you want, and its controllers figure out how to get there — and how to stay there.

## How Flux reconciles state

Flux's controllers run a continuous reconciliation loop: they watch the live state of your cluster and compare it against the state defined in your Git repository. When the two disagree, a controller acts to close the gap.

For example, say a `Deployment` manifest in Git specifies three replicas, but the running Pod count drops to two — a node was rescheduled, someone ran a manual `kubectl scale`, whatever the cause. Flux's **Source Controller** notices the Git state hasn't changed, but the **Kustomize Controller** notices the live cluster has drifted from it, and reapplies the manifest, bringing the replica count back to three. You never told Flux to "fix the replica count" — you told it, once, what the count should be, and it enforces that continuously.

## Bootstrapping Flux

Before Flux can manage anything, it has to be installed on the cluster and pointed at a Git repository. This is **bootstrapping**:

```bash
flux bootstrap github \
  --owner=<your-github-user-or-org> \
  --repository=<your-repo-name> \
  --branch=main \
  --path=clusters/production \
  --personal
```

Bootstrapping installs Flux's CRDs and controllers into the cluster, then commits the resulting configuration into the target repository and path. From that point on, anything you commit under that path is a candidate for Flux to apply — the repository becomes the cluster's desired state.

## Declaring infrastructure

Once Flux is bootstrapped, you describe your infrastructure in Git using one of three approaches, and Flux keeps the cluster in sync with whichever you choose.

**Plain Kubernetes manifests.** For something like an NGINX deployment, you write an ordinary `Deployment` manifest and commit it. Flux's Source Controller detects the new commit; the Kustomize Controller applies the manifest. Change the image tag or the replica count in Git later, and Flux updates the live deployment to match — no `kubectl apply` from your side.

**Helm releases**, managed through the `HelmRelease` custom resource:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx
  namespace: default
spec:
  interval: 5m
  chart:
    spec:
      chart: nginx
      version: "15.x"
      sourceRef:
        kind: HelmRepository
        name: bitnami
  values:
    replicaCount: 3
```

Change a value or bump a chart version in this manifest, commit it, and the Helm Controller upgrades the release to match.

**Kustomize overlays**, for managing variations of the same manifests across environments. You keep a base configuration and layer environment-specific overlays — development, staging, production — on top of it:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./clusters/production
  prune: true
```

The Kustomize Controller applies the resolved output of base plus overlay to the cluster, so the same base manifests can produce different results per environment without duplicating YAML.

> **Note:** All three approaches share the same source of truth — the Git repository — and the same enforcement mechanism: Flux's reconciliation loop. Which one you pick depends on how the software you're deploying is packaged, not on any difference in how Flux treats them.

## Keeping images fresh: Image Automation

Even with everything else declarative, someone still has to bump the image tag in the manifest whenever a new container image is built. Flux's **Image Automation** feature closes this last gap: it watches a container registry, and when a new image matching your policy appears, it commits the updated tag to your Git repository itself. You still never touch the cluster directly — Flux just extends the same Git-as-source-of-truth model one step further back, into the build pipeline.

## Further reading

- [Flux Core Concepts](https://fluxcd.io/flux/concepts/)
- [Flux Get Started guide](https://fluxcd.io/flux/get-started/)
- [HelmRelease reference](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Kustomization reference](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Image Automation guide](https://fluxcd.io/flux/guides/image-update/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
