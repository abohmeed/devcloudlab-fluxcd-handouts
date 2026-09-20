---
title: "Installing and bootstrapping Flux CD"
kicker: "FLUX CD · SECTION 2 · LECTURE 3"
description: "Install the Flux CLI, verify your cluster with flux check --pre, and bootstrap Flux CD against a GitHub or GitLab repository"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Installing and bootstrapping Flux CD

*Section 2, Lecture 3 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Install the Flux CLI on macOS, Linux, or Windows
- Confirm a cluster is ready for Flux with `flux check --pre`
- Lay out the Git repository structure Flux expects before you bootstrap
- Create the personal access token Flux needs to write to your repository
- Bootstrap Flux against a GitHub or GitLab repository, and read exactly what the bootstrap commit adds

## Install the Flux CLI

Flux ships as a single **Go** binary, so installing it is just fetching the right build for your platform — nothing is installed on your cluster at this step.

```bash
# macOS or Linux, with Homebrew
brew install fluxcd/tap/flux

# macOS or Linux, without Homebrew (installs to /usr/local/bin)
curl -s https://fluxcd.io/install.sh | sudo bash

# Windows, with Chocolatey
choco install flux
```

Confirm it installed:

```bash
flux --version
```

## Check the cluster before you touch anything

Before creating any files, point `kubectl` at the target cluster and run Flux's pre-flight check:

```bash
flux check --pre
```

This confirms the CLI can reach the Kubernetes API through your current `kubectl` context, and that the cluster is running a **Kubernetes** version Flux supports. Resolve anything it flags — a failing `flux check --pre` means the bootstrap step later will fail too.

> **Since this video was recorded:** the video quotes a minimum of Kubernetes 1.23. Flux's minimum supported version moves forward as older Kubernetes releases reach end of life, so treat that number as stale — the [installation page](https://fluxcd.io/flux/installation/) lists the current minimum, and `flux check --pre` tells you definitively whether your own cluster qualifies.

## Lay out the Git repository

Flux is entirely declarative — even Flux's own installation is described by YAML files that live in a Git repository, the same repository that will later hold your application manifests.

Create an empty repository on GitHub or GitLab, clone it locally, then create the directory Flux will read from:

```bash
cd my-flux-repo
mkdir -p clusters/my-cluster/flux-system
cd clusters/my-cluster/flux-system
touch gotk-components.yaml gotk-sync.yaml kustomization.yaml
```

> **Note:** `my-cluster` names the **Flux configuration**, not the Kubernetes cluster you're pointing it at. The same configuration path can be bootstrapped onto several clusters, so the directory name is arbitrary — pick something that describes the environment (`production`, `staging`) rather than a literal cluster hostname.

`gotk-components.yaml` and `gotk-sync.yaml` stay empty for now — Flux generates their contents during bootstrap. The only file you write by hand is `kustomization.yaml`, which tells Flux where to find the other two:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
```

Commit and push before bootstrapping:

```bash
git add -A
git commit -m "Initial commit"
git push
```

## Create a personal access token

Bootstrap needs to push generated files back to your repository on your behalf, so it authenticates with a **personal access token (PAT)** rather than your own login session.

**GitLab:** go to your profile's Access Tokens settings and create a token scoped to `api`. Copy the value immediately — GitLab shows it exactly once, and if you lose it you have to create a new one.

**GitHub:** create a fine-grained personal access token scoped to the target repository, with:

| Permission | Access needed |
|---|---|
| Contents | Read and write |
| Administration | Read-only |
| Metadata | Read-only (granted automatically) |

> **Note:** treat the token like a password — never commit it, never share it — and set yourself a reminder before it expires. An expired token doesn't error loudly; Flux's reconciliation just quietly stops being able to push or pull, which makes it one of the more annoying failures to track down if you've forgotten you set an expiry.

Export the token so the CLI can read it:

```bash
# GitLab
export GITLAB_TOKEN=<your-token>

# GitHub
export GITHUB_TOKEN=<your-token>
```

## Bootstrap

`flux bootstrap <provider>` does four things in one run: it connects to your repository, downloads the `flux-system` directory, generates the contents of `gotk-components.yaml` and `gotk-sync.yaml`, commits and pushes that change back to the repository using your token, then applies everything to the cluster using the `kustomization.yaml` you wrote.

**GitLab:**

```bash
flux bootstrap gitlab \
  --owner=<your-gitlab-username-or-group> \
  --repository=<your-repo-name> \
  --branch=main \
  --path=clusters/my-cluster \
  --token-auth \
  --personal
```

**GitHub:**

```bash
flux bootstrap github \
  --owner=<your-github-username-or-org> \
  --repository=<your-repo-name> \
  --branch=main \
  --path=clusters/my-cluster \
  --token-auth \
  --personal
```

A few flags worth knowing precisely, because getting one wrong is a common source of a bootstrap that silently targets the wrong thing:

| Flag | What it does |
|---|---|
| `--token-auth` | Use the PAT you exported instead of Flux's default SSH deploy key |
| `--personal` | Tells Flux `--owner` is an individual account — drop it when bootstrapping into an organization (GitHub) or group (GitLab) repository |
| `--path` | Must match the directory you created earlier; this is the path Flux will keep in sync |
| `--branch` | The branch Flux commits to and reconciles from |

Flux also bootstraps natively against **Bitbucket Server** and any generic Git server over HTTPS or SSH — the provider-specific subcommands exist for the hosts that offer a token/API integration; check the [installation docs](https://fluxcd.io/flux/installation/) for the exact command on a host not covered here.

## What the bootstrap commit actually writes

Once bootstrap finishes, look at the commit it pushed to your repository:

| File | What bootstrap wrote into it |
|---|---|
| `gotk-components.yaml` | The full manifest for every Flux controller and CRD — this is what actually gets applied to the cluster |
| `gotk-sync.yaml` | A `GitRepository` and a `Kustomization` object that point back at this same repository, branch, and path — this is what makes Flux self-managing |
| `kustomization.yaml` | Untouched — this is the file you wrote by hand |

From this point on, any change you push to `clusters/my-cluster/flux-system/` — or to any path a `Kustomization` you add later points at — gets reconciled onto the cluster automatically.

Confirm the controllers are running:

```bash
kubectl get pods -n flux-system
```

You'll see four pods, one per controller — **source**, **kustomize**, **helm**, and **notification** — and, notably, none of them is named `flux`. Flux has no single control-plane pod; it's a set of controllers that each reconcile a slice of Git state onto the cluster.

## Bootstrapping more than one cluster

Because Flux has no central control plane, adding a second cluster to the same setup is the same `flux bootstrap` command run against the new cluster's `kubectl` context — pointed at the same repository, branch, and path, or a different path if you want it running a different configuration. There's no separate registration step on a management cluster, which is the main operational difference from tools like Argo CD, where a hub cluster must be told about every cluster it manages before it can deploy to it.

## Further reading

- [Flux installation](https://fluxcd.io/flux/installation/)
- [Flux bootstrap for GitHub](https://fluxcd.io/flux/installation/bootstrap/github/)
- [Flux bootstrap for GitLab](https://fluxcd.io/flux/installation/bootstrap/gitlab/)
- [`flux check` command reference](https://fluxcd.io/flux/cmd/flux_check/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
