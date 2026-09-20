---
title: "GitOps and DevOps"
kicker: "FLUX CD · SECTION 1 · LECTURE 5"
description: "A side-by-side comparison of DevOps and GitOps, and why GitOps is one way of practicing DevOps rather than a replacement for it"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# GitOps and DevOps

*Section 1, Lecture 5 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- The core principles behind DevOps and behind GitOps, side by side
- Where the two actually differ: scope, tooling, configuration style and synchronization
- Why GitOps is best understood as one way of practicing DevOps, not a competing methodology
- Which lens to reach for depending on what problem you're solving

## DevOps, briefly

**DevOps** is a set of practices that aims to automate and integrate the processes of software development and IT operations. At its core, it is about breaking down the silo between Development and Operations teams and building a culture of shared responsibility.

Four principles anchor it:

- **Automation** — automate as much of the software lifecycle as possible
- **Collaboration** — foster communication between teams that used to work in isolation
- **Feedback loops** — monitor continuously and use what you learn to improve
- **Reliability** — keep systems available and performing well

DevOps doesn't prescribe a toolchain. A team can practice DevOps with almost any combination of CI system, deployment method or ticketing tool, as long as the culture and the feedback loops are in place.

## GitOps, briefly

**GitOps** is a narrower paradigm that puts Git at the center of the deployment pipeline, using it as the single source of truth for both application code and infrastructure state.

Its principles:

- **Declarative configuration** — the desired state of a system is described in config files, not in a sequence of imperative commands
- **Version control** — the Git repository *is* the source of truth for that desired state
- **Automated synchronization** — a controller continuously reconciles the live system with what Git says it should look like
- **Observability** — because every change is a Git commit, the current state and its history are always inspectable

## Where they differ

| Aspect | DevOps | GitOps |
|---|---|---|
| Scope | The entire software lifecycle — planning, building, testing, monitoring | Mainly deployment and operations |
| Tooling | No specific tool required | Centered on Git and a reconciling controller |
| Configuration style | Declarative or imperative, either is fine | Declarative only |
| Change control | Version control is encouraged, not required everywhere | Everything that defines state lives under version control |
| Synchronization | May be manual, may be automated | Continuous, automated reconciliation is the point |

## GitOps is a way of doing DevOps, not a replacement for it

It's tempting to treat these as competing methodologies, but they aren't at the same altitude. DevOps is the broader culture and set of goals — automate, collaborate, monitor, improve — applied across the whole lifecycle. GitOps is a specific, opinionated implementation of that culture for one slice of it: how changes reach a running system, particularly a Kubernetes-based one.

A team practicing GitOps is still doing DevOps. It has simply chosen a concrete, Git-centered answer to "how do deployments happen" instead of leaving that question open. That's why you'll see GitOps described as a *subset* or a *pattern within* DevOps rather than as its successor.

## Choosing the right lens

- **Reach for GitOps** when you need automated, consistent, auditable deployments — especially into a Kubernetes cluster, where a controller can continuously reconcile live state against Git.
- **Reach for the broader DevOps lens** when you're thinking about the whole picture: how work gets planned, built, tested and observed, not just how it gets deployed.

## What stays true either way

Whichever term describes your setup, the same discipline applies:

- **Collaborate** — communication between teams remains critical
- **Document** — keep documentation current, not just code
- **Monitor** — observe your systems continuously, not only after an incident
- **Iterate** — treat your processes as something you keep improving, not something you finish

## Further reading

- [OpenGitOps — Principles](https://opengitops.dev/)
- [Flux — Core Concepts](https://fluxcd.io/flux/concepts/)
- [Kubernetes — Declarative Management of Kubernetes Objects](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
