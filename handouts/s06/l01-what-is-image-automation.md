---
title: "What is image automation"
kicker: "FLUX CD · SECTION 6 · LECTURE 1"
description: "The three resources behind Flux's image automation, the marker comment that ties them to a Git file, and the two controllers you must request explicitly"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# What is image automation

*Section 6, Lecture 1 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- The manual step in a typical release workflow that image automation removes
- The three resources that make up the feature — **ImageRepository**, **ImagePolicy**, and **ImageUpdateAutomation** — and what each one is responsible for
- The marker comment that tells Flux which line in a manifest to rewrite
- The three ways to decide which tag counts as "newest" — SemVer, alphabetical, and numerical — and when to reach for each
- Why the controllers behind this feature are not there by default, even after a normal `flux bootstrap`

## The manual step this feature removes

A typical release starts with a developer pushing code tagged with a new version — `1.0.1`, say, if `1.0.0` was the last release and this is a minor bump. A CI pipeline picks that up, runs tests, builds a Docker image carrying the same tag, and pushes it to a registry. From there the CI side of the pipeline is done and the CD side begins: getting that image into a running environment.

Staging (or QA, or UAT — the name varies, the role doesn't) usually wants to run the latest image at all times, so it can be updated automatically. Production is different. Deciding what ships to production is a judgment call, and it is normally made by hand: someone runs a `kubectl patch` against the Deployment, or a `helm upgrade --install --set image.tag=...`, and points the cluster at the version they've chosen to release.

Image automation is Flux CD's answer to that manual step for the environments that don't need a human in the loop. Flux watches a registry, decides — by a policy you define — which tag is the one to run, rewrites the manifest to reference it, and commits that change to Git. The cluster and the repository, which stays the single source of truth, move together.

## The two controllers behind it

Image automation is not part of a default Flux install. `flux bootstrap` on its own does not deploy it — you have to ask for it by name:

```bash
flux bootstrap github \
  --owner=<your-username> \
  --repository=<your-repo> \
  --path=./clusters/my-cluster \
  --components-extra=image-reflector-controller,image-automation-controller
```

Skip `--components-extra` and every resource described below will sit forever with no controller to reconcile it — the manifests apply cleanly and simply do nothing.

The two controllers split the work:

| Controller | Job |
|---|---|
| **image-reflector-controller** | Scans the registries you point it at, finds new tags, and — if your policy allows the tag — reflects that metadata into the cluster |
| **image-automation-controller** | Reads the policy's chosen tag, rewrites the image reference in your Git-tracked manifest, and pushes the commit |

## The three resources

Three custom resources carry this out, each with one job:

| Resource | Answers |
|---|---|
| **ImageRepository** | Which registry and image to scan, and how often |
| **ImagePolicy** | Given the tags that repository found, which one counts as "the new one" |
| **ImageUpdateAutomation** | Where in Git to write the winning tag, and how to commit that change |

They chain together: ImageRepository feeds the tag list to ImagePolicy, ImagePolicy resolves it to a single tag, and ImageUpdateAutomation writes that tag into your manifest and pushes it. None of the three touches the cluster directly — the write lands in Git, and your existing Flux Kustomization is what carries it from there into a running Deployment, the same as any other change.

## The marker comment

ImageUpdateAutomation needs to know exactly which line in a YAML file to rewrite. You mark it with a comment next to the image reference:

```yaml
containers:
  - name: podinfo
    image: ghcr.io/stefanprodan/podinfo:6.0.0 # {"$imagepolicy": "flux-system:podinfo"}
```

The value is `namespace:policy-name` — the namespace and name of the ImagePolicy that governs this line. Without that comment, the automation controller has no way to find the field it's supposed to update, and nothing changes.

## Three ways to define "newest"

An ImagePolicy needs a rule for choosing among the tags an ImageRepository found. Flux gives you three:

| Policy | Set on the tag | Works when |
|---|---|---|
| **SemVer** | `policy.semver.range`, e.g. `>=1.0.0` | Tags follow semantic versioning (`1.0.1`, `2.3.0`) |
| **Alphabetical** | `policy.alphabetical.order: asc` or `desc` | Tags are words or letters (`alpha`, `beta`, `alpha1`, `alpha2`) with no numeric meaning |
| **Numerical** | `policy.numerical.order: asc` or `desc` | Tags are plain numbers — a build counter or a timestamp like `20231028213000` |

SemVer is the one you'll already recognize if you've seen Helm chart update policies — the constraint syntax is identical, because it's the same idea applied to a different kind of artifact.

## When a tag is more than one thing at once

Real-world tags rarely stay this clean. The official Redis image, for example, ships tags like `7.2.2`, `7.2.2-alpine`, `7.2.2-alpine3.18`, and `7.0.14-bookworm` — a version number and an OS label combined in one string, which a plain SemVer policy can't parse on its own.

`filterTags` narrows the candidate list before a policy ever runs, using a regular expression against `spec.filterTags.pattern`:

```yaml
filterTags:
  pattern: '.*-bookworm$'
```

That keeps only the Bookworm-based tags before the policy sorts among them.

Some tags go further and embed the sortable part *inside* a longer string — a `release.<timestamp>` tag, say, where you only want to sort on the timestamp. `filterTags.extract` handles that with a named capture group in the pattern:

```yaml
filterTags:
  pattern: '^release\.(?P<ts>\d+)$'
  extract: '$ts'
```

The pattern matches the whole tag but only *captures* the timestamp; `extract` tells the policy to sort on that captured value rather than the full tag string. The numerical or alphabetical policy then sorts on exactly the part that carries meaning.

## Further reading

- [Flux — Image automation overview](https://fluxcd.io/flux/components/image/)
- [ImageRepository reference](https://fluxcd.io/flux/components/image/imagerepositories/)
- [ImagePolicy reference](https://fluxcd.io/flux/components/image/imagepolicies/)
- [ImageUpdateAutomation reference](https://fluxcd.io/flux/components/image/imageupdateautomations/)
- [Flux — bootstrap command reference](https://fluxcd.io/flux/cmd/flux_bootstrap/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
