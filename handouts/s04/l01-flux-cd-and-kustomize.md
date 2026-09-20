---
title: "Flux CD and Kustomize"
kicker: "FLUX CD · SECTION 4 · LECTURE 1"
description: "The conceptual foundation for this section: what Kustomize is, and how Flux's Kustomization resource builds on it to reconcile a cluster from Git"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Flux CD and Kustomize

*Section 4, Lecture 1 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- What **Kustomize** is and why it favors a base/overlay model over templating
- How `kubectl` uses Kustomize natively, and the command that invokes it
- What a **Flux Kustomization** is, and exactly how it differs from a plain `kustomization.yaml`
- How Flux's reconciliation loop turns a Git commit into a running, healthy cluster state

## Two things share a name — and that's the whole trap

This section leans on one component more than any other, and it has a naming
collision built in. Keep these two apart from the start:

| | **Kustomize** (the tool) | **Flux Kustomization** (the resource) |
|---|---|---|
| What it is | A CLI/library for customizing manifests | A Kubernetes custom resource: `kustomize.toolkit.fluxcd.io/v1` |
| Where it runs | On your machine, or as a `kubectl` plugin | Inside the cluster, driven by a Flux controller |
| Configured by | A `kustomization.yaml` file next to your manifests | A YAML object of `kind: Kustomization` that you apply to the cluster |
| Who triggers it | You, by running a command | Flux, automatically, on an interval or a Git change |
| Needs a source? | No — it just reads a local directory | Yes — it depends on a Flux source (a `GitRepository`, for example) that tells it where to pull from |
| Extra behavior | None — it only renders manifests | Health checks, garbage collection, and `dependsOn` ordering |

Every time you see the word "Kustomization" for the rest of this section, ask
which one is meant. Lowercase `kustomization.yaml` is always the tool's config
file. `kind: Kustomization` in a Flux manifest is always the custom resource.

## Kustomize: base and overlay, not templates

**Kustomize** is a standalone tool for customizing Kubernetes manifests in
place, without a templating language. Instead of parameterizing YAML with
`{{ .Values.something }}`-style placeholders, Kustomize works from a **base** —
a set of plain, valid manifests — and one or more **overlays** that patch that
base for a specific environment.

The practical benefit is reuse: one base configuration, several overlays
(staging, production, a specific tenant), no duplicated YAML and no templating
engine to learn. The base stays plain Kubernetes YAML the whole way through,
which also makes it easier to read and to review in a pull request.

Since Kubernetes 1.14, Kustomize has been built into `kubectl` itself, so you
do not need a separate binary to use it directly:

```bash
kubectl apply -k ./mydir
```

The `-k` flag tells `kubectl` to look for a `kustomization.yaml` in that
directory, build the manifests it describes, and apply the result.

## The Flux Kustomization resource

A **Flux Kustomization** is a custom resource that represents a Kustomize
overlay — but it does more than represent it. Where running `kubectl apply -k`
by hand is a one-off action, a Flux Kustomization is reconciled continuously by
a controller running inside the cluster. Given a source and a path, that
controller:

- pulls the manifests from the source it depends on,
- runs the Kustomize build against them,
- applies the result to the cluster,
- and then keeps checking that the result matches what it applied.

That last point is what separates it from the plain tool. A few capabilities
only exist at the Flux resource level:

- **Health checks** — after applying, Flux can wait for specific resources to
  report ready before considering the Kustomization successful.
- **Garbage collection** — resources that were applied by a Kustomization but
  are no longer present in Git get pruned automatically, so removing a
  manifest from your repository removes it from the cluster too.
- **Dependency ordering** — a Kustomization can declare `dependsOn` another
  Kustomization, so Flux applies things in the order your infrastructure
  actually needs (a namespace before the workloads that go in it, for
  example).

None of these exist in vanilla Kustomize, because vanilla Kustomize has no
concept of a running cluster to watch — it only renders YAML.

## Reconciliation: the loop underneath everything

**Reconciliation** is the process that keeps a cluster's actual state aligned
with the desired state declared in Git. For a Flux Kustomization, one pass
through the loop looks like this:

1. Flux fetches the latest revision of the manifests from the source it
   depends on (typically a `GitRepository`).
2. If the path points at a Kustomize base/overlay, Flux runs the Kustomize
   build to produce the final manifests.
3. Flux applies those manifests to the cluster.
4. Flux checks that the resulting resources are running and healthy.

This loop runs on a defined interval, and it can also be triggered manually
without waiting for the interval to elapse. Either way, the effect is the
same: a change committed to Git eventually — and automatically — becomes a
change in the cluster, with no one running `kubectl apply` by hand.

## Further reading

- [Flux Kustomization documentation](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Kustomize official documentation](https://kustomize.io/)
- [Kubernetes: Declarative Management of Kubernetes Objects Using Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
