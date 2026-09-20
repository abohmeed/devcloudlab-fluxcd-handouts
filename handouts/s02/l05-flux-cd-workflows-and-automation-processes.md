---
title: "Flux CD workflows and automation processes"
kicker: "FLUX CD · SECTION 2 · LECTURE 5"
description: "How Flux CD's source, synchronization and reconciliation stages fit together into a loop, and how Image Automation keeps that loop image-aware"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Flux CD workflows and automation processes

*Section 2, Lecture 5 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- The three stages every Flux CD workflow moves through: source control, synchronization, and reconciliation
- Which controller owns each stage, and which Kubernetes object it produces or consumes
- What actually triggers a reconciliation — and why there is no single, global answer to "how often"
- How Image Automation closes the loop between a new container image and a new Git commit

## The workflow, in three stages

A Flux CD workflow is not one big reconciliation — it's a pipeline of three distinct stages, each owned by a different controller:

| Stage | What happens | Controller |
|---|---|---|
| Source control | Watches your Git repository for changes | `source-controller` |
| Synchronization | Stores the fetched state as a Kubernetes object | `source-controller` |
| Reconciliation | Applies that state to the cluster | `kustomize-controller` / `helm-controller` |

Each stage hands off a concrete Kubernetes object to the next, which is what makes the pipeline inspectable — you can query the object at any stage with `kubectl` and see exactly what Flux currently believes is true.

### Stage 1: Source control

Flux follows the **GitOps** model: Git is the single source of truth for your cluster's desired state. Any change that matters — a new image tag, an edited `Deployment`, an updated `Service` — starts as a commit.

The `source-controller` is the component responsible for this stage. It watches the repositories you've pointed it at and fetches whatever has changed, whether that change lives in plain Kubernetes manifests, a Helm chart, or a Kustomize overlay.

### Stage 2: Synchronization

Once `source-controller` fetches an update, it doesn't hand raw Git contents straight to the cluster. It stores what it fetched as a **`GitRepository`** object — a Flux custom resource that holds a snapshot of your repository's state inside the cluster itself:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: my-app
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/example/my-app
  ref:
    branch: main
```

This is the intermediary stage. Having the latest desired shape already sitting in the cluster, as a `GitRepository`, means the controllers that act on it in the next stage never need to talk to Git directly.

### Stage 3: Reconciliation

This is where the other controllers take over. Watching the `GitRepository` object for changes, the `kustomize-controller` or `helm-controller` reconciles the *actual* state of the cluster against the desired shape it just read.

- **`kustomize-controller`** applies `Kustomization` objects — it's what lets you layer environment-specific overlays on top of a shared base.
- **`helm-controller`** manages `HelmRelease` objects — installing and upgrading the Helm charts your applications are packaged as.

## The reconciliation loop, precisely

The lecture calls this "a loop," and it's worth being exact about what drives it, because it's not just "Flux notices a Git change and reacts."

Every object in this pipeline — the `GitRepository`, and every `Kustomization` or `HelmRelease` that reads from it — carries a required `spec.interval` field, as shown above. That field is what turns the pipeline into an actual loop: on each interval, the relevant controller re-checks its object regardless of whether anything changed, and re-applies it if the live cluster state has drifted from the desired one.

> **Note:** There is no single default reconciliation interval across Flux. `interval` is set per resource — a `GitRepository` might poll every minute while a `Kustomization` reconciles every ten. Read the `spec.interval` on the specific object you're working with rather than assuming a course-wide default.

So a reconciliation happens for either of two reasons: a new commit landed and was picked up at the next poll, or the interval simply elapsed and Flux is re-asserting the desired state — which is also what makes Flux self-healing against manual `kubectl` edits, not just Git-reactive.

## Automating image updates

Source control, synchronization and reconciliation keep the cluster matching Git. **Image Automation** closes the other half of the loop: keeping Git itself current when a new container image ships.

Without it, a new image push to a registry is only half the job — someone still has to hand-edit the image tag in a manifest and commit it. Image Automation removes that manual step. Flux's image-automation components continuously scan configured container registries for new tags and, when one matches your selection criteria, write the updated image reference back to the Git repository as a commit — which then flows through the same three-stage pipeline you just learned, and lands in the cluster automatically.

The result is a genuinely closed loop: a new image triggers a Git commit, and that Git commit triggers reconciliation, with no manual step in between.

## Further reading

- [Flux core concepts](https://fluxcd.io/flux/concepts/)
- [GitRepository source](https://fluxcd.io/flux/components/source/gitrepositories/)
- [Kustomization reconciliation](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [HelmRelease reconciliation](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Image update automation guide](https://fluxcd.io/flux/guides/image-update/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
