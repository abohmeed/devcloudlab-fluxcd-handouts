---
title: "Different Git directory structuring methods"
kicker: "FLUX CD · SECTION 4 · LECTURE 2"
description: "How to lay out a Git repository for Flux CD and Kustomize: monorepo, per-environment, per-team, and per-application, and the trade-offs of each"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Different Git directory structuring methods

*Section 4, Lecture 2 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Why directory layout stops being a style choice and becomes a mechanism once Kustomize is in the picture
- The four common ways to structure a Flux CD repository: monorepo, repository-per-environment, repository-per-team, and repository-per-application
- How a `base` plus overlays pattern separates sane defaults from per-environment overrides
- The trade-offs between centralizing everything and splitting by team or environment
- How image automation and manual promotion fit differently into each structure

## Why structure matters more with Kustomize

With Helm, most environment differences can be pushed into `values.yaml` files, so the repository layout is mostly a matter of taste. **Kustomize** works differently: it resolves configuration by walking directories and applying overlays on top of a `base`, so the directory tree *is* the mechanism, not just an organizational convenience. Getting the structure right up front avoids a repository that fights the tool later.

The rest of this lecture compares four common ways teams lay out a Git repository for Flux CD with Kustomize.

## Method 1: the monorepo

In a **monorepo**, every Kubernetes manifest — applications and cluster infrastructure alike — lives in a single repository. Both `apps` and `infrastructure` are organized as a `base` (the sane defaults) with overlays per target.

```
.
├── apps
│   ├── base
│   ├── production
│   └── staging
├── infrastructure
│   ├── base
│   ├── production
│   └── staging
└── clusters
    ├── production
    └── staging
```

The `clusters` directory holds the target clusters — for example `dev`, `staging`, and `production`. A single-cluster setup works too: instead of multiple cluster directories, you'd have one cluster with a `namespaces` directory underneath it for `dev`, `staging`, and `production` namespaces. The difference only shows up at bootstrap time — a multi-cluster setup means running Flux's bootstrap process once per cluster to lay down its `flux-system` Kustomization.

Keeping `apps` and `infrastructure` separate lets you define an **execution order**. If an application depends on an infrastructure component — a network policy, an ingress controller, a certificate issuer — that component lives under `infrastructure` and is reconciled before the application that needs it.

**Change workflow in a monorepo.** Changes go through short-lived feature branches merged into `main` via pull requests; once merged, the branch is deleted. From there, promotion can follow two patterns:

- **Automatic, for lower environments.** Flux CD's image automation can detect a new application image and apply it straight to `staging`, the same way it can track new Helm chart versions within a version range.
- **Manual approval, for production.** Rather than applying a new image directly, Flux can open a pull or merge request against the production path so a human reviews and merges it through the normal Git flow before it is applied.

For tighter control on top of that, a progressive delivery tool like **Flagger** can implement deployment strategies such as canary releases, so changes promoted to production are exercised gradually rather than switched over all at once.

## Method 2: one repository per environment

Instead of one repository holding every environment, each environment — `dev`, `staging`, `production` — gets its **own repository**.

| | Monorepo | Repository per environment |
|---|---|---|
| Who can see production manifests | Anyone with access to the one repo | Only those granted access to the production repo |
| Promoting a change to production | Merge within the same repository | Requires copying or syncing changes across repositories |

The advantage is access control: production configuration is never exposed to everyone who can see `dev` or `staging`, which matters in high-security environments that require this kind of segregation. The drawback is the opposite side of the same coin — promoting a change to production is harder, because it now means moving a change across a repository boundary instead of merging within one.

## Method 3: one repository per team

Some organizations separate **platform concerns from application concerns** by repository. A dedicated platform (or admin) team owns a repository responsible for the cluster itself:

- Bootstrapping, patching, and updating the clusters
- Creating CRDs, controllers, admission webhooks, and policies
- Onboarding new application teams into the cluster via Flux's `GitRepository` resource

That team is not concerned with deploying or managing individual applications — that responsibility belongs to each application team, and **each team gets its own Git repository** to manage its own deployments, services, volumes, and Helm charts. Day-to-day application delivery inside a team's repository looks like the monorepo approach described above; what changes is the **separation of concerns**: the admin team reviews and merges changes to the cluster platform, while each application team reviews and merges changes to its own application.

## Method 4: one repository per application

The last method stores an application's source code and its Kubernetes configuration **in the same repository**. Everything related to the application lives in one place, and there's no duplication of configuration between an application repository and a separate cluster repository.

One way to wire this into Flux is to add a `GitRepository` resource, in the cluster's configuration directory, that points at the application's repository, paired with a `Kustomization` that specifies the exact directory inside it where the deployment manifests live. This combines the application code with its deployment manifests while keeping the Flux system configuration in its own, separate repository.

If the application is instead packaged as a Helm chart, a CI/CD pipeline can build a versioned chart and push it to a Helm repository; Flux then references it with a `HelmRepository` resource in the application's configuration directory rather than a `GitRepository` resource pointing at raw manifests.

## Comparing the four

| Structure | Where manifests live | Best fit | Main trade-off |
|---|---|---|---|
| **Monorepo** | One repository for apps and infrastructure | Small to mid-sized teams, simpler governance | Everyone with repo access sees every environment |
| **Repository per environment** | One repository per `dev`/`staging`/`production` | High-security environments that must isolate production | Promoting a change across repositories is harder |
| **Repository per team** | One cluster/platform repository, plus one repository per application team | Larger orgs that want a dedicated platform team | More repositories and `GitRepository` resources to manage |
| **Repository per application** | Application code and its manifests together | Teams that want zero duplication between app and deployment config | Cluster-wide conventions have to be enforced across many repos instead of one |

There is no single correct structure — the right one depends on team size, how much isolation production needs, and how much a platform team wants to own centrally. The next lecture in this section takes the repository built so far in this course and restructures it to follow one of these approaches.

## Further reading

- [Flux repository structure guide](https://fluxcd.io/flux/guides/repository-structure/)
- [Kustomize bases and overlays](https://kubectl.docs.kubernetes.io/guides/config_management/components/)
- [Flux image automation](https://fluxcd.io/flux/guides/image-update/)
- [Flagger progressive delivery](https://fluxcd.io/flagger/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
