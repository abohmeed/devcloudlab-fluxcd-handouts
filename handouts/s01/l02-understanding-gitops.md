---
title: "Understanding GitOps"
kicker: "FLUX CD · SECTION 1 · LECTURE 2"
description: "The core principles of GitOps, why teams adopt it, and how Flux CD implements it for Kubernetes."
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Understanding GitOps

*Section 1, Lecture 2 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- What GitOps means, and why Git sits at the center of it
- The four principles that make a deployment workflow "GitOps"
- How GitOps compares to a traditional push-based deployment pipeline
- Where Flux CD fits into the GitOps picture, and what it automates for you

## What is GitOps?

**GitOps** is a way of operating infrastructure and applications where a Git
repository is the single source of truth. Instead of running commands against
a cluster by hand, you describe the state you want — which workloads should
exist, which versions, which configuration — as files in Git, and a
controller running inside the cluster continuously makes the real world match
what Git says.

The name comes from applying the practices software teams already use for
code (pull requests, code review, commit history) to operations. If it isn't
in Git, it isn't the intended state of the system.

## Why teams adopt it

- **Version control.** Every change to the infrastructure is a commit, so
  rollbacks and audits become "check out an earlier commit" rather than
  reconstructing what changed by memory.
- **Collaboration.** Developers and operations work from the same repository
  and the same review process, instead of operations applying changes a
  developer can't see.
- **Automation.** Deployments happen automatically when the desired state in
  Git changes, which removes manual, inconsistent apply steps.

## The four core principles

GitOps is usually described by four properties a system must have before it
counts as GitOps rather than "we also keep some YAML in Git":

| Principle | What it means |
|---|---|
| **Declarative** | The desired state is described in configuration files (what should exist), not in a sequence of commands (how to get there). |
| **Versioned** | That configuration lives in a Git repository, so every change has a history, an author and a diff. |
| **Automated synchronization** | A controller compares the live state of the system to the state declared in Git and applies the difference — no one runs `kubectl apply` by hand. |
| **Observability** | The current state, and any drift from what Git declares, is easy to see rather than hidden inside a deployment script's output. |

## Push-based vs. GitOps (pull-based) deployment

A conventional CI/CD pipeline usually **pushes** changes into a cluster: a
pipeline job authenticates to the cluster and runs the deployment commands
itself. GitOps flips this around — a controller running **inside** the
cluster **pulls** the desired state from Git and reconciles toward it.

| | Push-based pipeline | GitOps (pull-based) |
|---|---|---|
| Who has cluster credentials | The CI/CD system, external to the cluster | Only the in-cluster controller |
| Source of truth | The pipeline's deploy step | The Git repository |
| Drift detection | Not automatic — the pipeline only runs on trigger | Continuous — the controller reconciles on a loop |
| Rollback | Re-run a pipeline job | Revert a Git commit |

## Where Flux CD fits in

**Flux CD** is a tool that implements GitOps for Kubernetes. It runs as a set
of controllers inside your cluster, watches one or more Git repositories, and
applies the manifests it finds there — without a pipeline needing standing
access to the cluster. Because it continuously reconciles rather than
deploying once and stopping, it naturally gives you:

- Automatic deployment of changes merged to the watched repository
- Rollback by reverting the offending commit
- Support for multiple namespaces and clusters from the same setup
- Policies that control what gets deployed and when

## Best practices to keep in mind

- **Keep configuration simple.** The easier a manifest is to read, the easier
  it is to review and to reason about when something drifts.
- **Review every pull request** that touches the Git repository Flux
  watches — it is now your deployment gate, not a formality.
- **Watch synchronization status**, not just whether a pull request merged.
  A merge that fails to reconcile is a deployment that didn't happen.
- **Secure the Git repository** itself, with SSH keys or access tokens scoped
  to what Flux needs — it is effectively cluster-admin credentials in
  disguise.

## Further reading

- [OpenGitOps — Principles](https://opengitops.dev/)
- [Flux CD — Core Concepts](https://fluxcd.io/flux/concepts/)
- [Flux CD — Get Started](https://fluxcd.io/flux/get-started/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
