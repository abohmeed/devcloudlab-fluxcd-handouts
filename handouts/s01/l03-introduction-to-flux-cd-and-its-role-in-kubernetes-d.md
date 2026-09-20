---
title: "Introduction to Flux CD and its role in Kubernetes deployments"
kicker: "FLUX CD · SECTION 1 · LECTURE 3"
description: "What Flux CD is, the GitOps model it implements, the controllers it is built from, and how it keeps a cluster in sync with Git."
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Introduction to Flux CD and its role in Kubernetes deployments

*Section 1, Lecture 3 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- What GitOps means, and where Flux CD fits as an implementation of it
- The features that make Flux CD useful for real Kubernetes deployments
- The controllers Flux CD is actually built from, and what each one is responsible for
- The reconciliation loop Flux runs every time your Git repository changes

## What is GitOps?

**GitOps** is an operational model that uses Git as the single source of truth for a system's desired state. Instead of running commands against a cluster by hand, you describe the state you want — which workloads should exist, which versions, which configuration — as files in a Git repository. An automated process then makes the live system match what is in Git, continuously.

**Flux CD** is a tool that implements this model for Kubernetes. It runs inside your cluster, watches one or more Git repositories, and keeps the cluster's actual state aligned with the state those repositories describe. Nobody runs `kubectl apply` against production; they open a pull request instead.

## Key features

- **Automated deployment and synchronization.** Flux continuously compares the cluster's live state against your Git repository and applies whatever has changed, without a person triggering the deployment.
- **Multi-tenancy.** Flux can be configured so that different teams or namespaces each own their own Git sources and their own reconciliation, isolated from one another inside a shared cluster.
- **Git provider integration.** Flux works with GitHub, GitLab, Bitbucket, and any Git server reachable over HTTPS or SSH — it watches for commits and reconciles the cluster in response.
- **Helm support.** Flux can manage Helm chart releases directly from Git, so Helm-based applications go through the same GitOps workflow as plain Kubernetes manifests.

## How Flux CD is actually built

It is easy to picture "the Flux operator" as one process watching your cluster. In practice, Flux CD is a set of small, single-purpose controllers, installed together, that each own one part of the job. This set is called the **GitOps Toolkit**.

| Controller | What it does |
|---|---|
| **source-controller** | Fetches and verifies source artifacts — Git repositories, Helm repositories, OCI repositories, and plain buckets — and makes them available to the other controllers. |
| **kustomize-controller** | Applies the Kubernetes manifests from a source (plain YAML or Kustomize overlays) to the cluster, and reconciles any drift back to what Git defines. |
| **helm-controller** | Installs, upgrades, and rolls back Helm chart releases based on `HelmRelease` resources, using charts that source-controller has fetched. |
| **notification-controller** | Sends outbound alerts about reconciliation events (to Slack, Microsoft Teams, and similar destinations) and receives inbound webhooks that can trigger a reconciliation immediately. |
| **image-reflector-controller** | Scans container image repositories and records which tags exist, as a Kubernetes resource Flux can read. |
| **image-automation-controller** | Uses that tag information to commit updated image references back to Git automatically, closing the loop for automated image updates. |

Not every Flux installation runs all six — a simple setup may only need source-controller and kustomize-controller. Which controllers you install is itself a decision you make when you bootstrap Flux, which this course covers later.

## The reconciliation workflow

Flux runs essentially the same loop for every change:

1. **You define desired state in Git.** Workloads, their configuration, and their dependencies are committed as manifests to a repository.
2. **A controller watches that repository.** source-controller polls (or receives a webhook for) the Git repository and fetches the latest commit as an artifact.
3. **Flux reconciles.** kustomize-controller or helm-controller compares the artifact against what is actually running in the cluster and creates, updates, or deletes Kubernetes resources so the two match.
4. **You observe the result.** Flux exposes reconciliation status — successes, errors, and conflicts — through its CLI and through Kubernetes resources you can read with `kubectl`, so a deployment's state is never a mystery.

This loop is what makes Flux declarative rather than imperative: you never tell it *how* to change the cluster, only what the cluster should look like, and it works out the difference on every run.

## Why this matters

Because every desired-state change is a Git commit, deployments become predictable, auditable, and reviewable through the same pull-request workflow your team already uses for application code. The next lecture goes into these benefits — consistency, speed, rollback, collaboration, and observability — in more depth.

## Further reading

- [Flux Documentation — Core Concepts](https://fluxcd.io/flux/concepts/)
- [Flux Documentation — Components](https://fluxcd.io/flux/components/)
- [GitOps Principles](https://www.gitops.tech/)
- [Kubernetes Documentation — Controllers](https://kubernetes.io/docs/concepts/architecture/controller/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
