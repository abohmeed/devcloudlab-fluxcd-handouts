---
title: "Migrating off the removed Flux beta APIs"
kicker: "FLUX CD · SECTION 2 · LECTURE 7"
description: "If you've built Flux manifests using this course, they work fine on the Flux versions that shipped in 2024. But if you point those same Git repositories at a recent Flux"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Migrating off the removed Flux beta APIs

*Section 2, Lecture 7 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Identify which Flux beta APIs were removed in v2.7.0 and their stable replacements
- Migrate Git repository manifests to the new API versions using `flux migrate -f .`
- Migrate cluster-stored custom resources to the new API versions using `flux migrate`
- Sequence a Flux upgrade correctly — repository first, then cluster, then Flux itself
- Diagnose the silent-failure symptoms of removed API versions in `flux get kustomizations` and kubectl output

## Why This Matters

If you've built Flux manifests using this course, they work fine on the Flux versions that shipped in 2024. But if you point those same Git repositories at a recent Flux cluster (v2.7.0 or later, released September 2025), your reconciliation stops.

The problem is not a crash — it's silent failure. The namespace where your application should land remains empty. No errors appear in pod logs because no pods were created. The cluster is simply telling you it doesn't understand the API versions your manifests are asking for.

This is not a bug. It's a consequence of how Kubernetes API versioning works. When Flux first released version 2, most APIs were still in beta — a promise that the design was nearly final but might still change. Over time, those APIs graduated to stable versions. When stable APIs were released, the beta ones were eventually removed entirely.

## When It Happened

Flux removed these beta APIs in **version 2.7.0** (September 2025). The removals were:

- `helm.toolkit.fluxcd.io/v2beta1`
- `source.toolkit.fluxcd.io/v1beta2`
- `notification.toolkit.fluxcd.io/v1beta2`

These three groups changed. Your `Kustomization` objects on `kustomize.toolkit.fluxcd.io/v1` were already stable and never moved.

## What Changed: The API Mapping

Every manifest you wrote in this course uses one of the APIs listed below. You need to update each one to its new version.

| Kind | Old API | New API | When it moved |
|---|---|---|---|
| HelmRelease | `helm.toolkit.fluxcd.io/v2beta1` | `helm.toolkit.fluxcd.io/v2` | Flux v2.7.0 (Sept 2025) |
| HelmRepository | `source.toolkit.fluxcd.io/v1beta2` | `source.toolkit.fluxcd.io/v1` | Flux v2.7.0 (Sept 2025) |
| GitRepository | `source.toolkit.fluxcd.io/v1beta2` | `source.toolkit.fluxcd.io/v1` | Flux v2.7.0 (Sept 2025) |
| OCIRepository | `source.toolkit.fluxcd.io/v1beta2` | `source.toolkit.fluxcd.io/v1` | Flux v2.7.0 (Sept 2025) |
| Bucket | `source.toolkit.fluxcd.io/v1beta2` | `source.toolkit.fluxcd.io/v1` | Flux v2.7.0 (Sept 2025) |
| Alert | `notification.toolkit.fluxcd.io/v1beta2` | `notification.toolkit.fluxcd.io/v1beta3` | Flux v2.7.0 (Sept 2025) |
| Provider | `notification.toolkit.fluxcd.io/v1beta2` | `notification.toolkit.fluxcd.io/v1beta3` | Flux v2.7.0 (Sept 2025) |
| Receiver | `notification.toolkit.fluxcd.io/v1beta2` | `notification.toolkit.fluxcd.io/v1` | Flux v2.7.0 (Sept 2025) |
| Kustomization | `kustomize.toolkit.fluxcd.io/v1` | No change — already stable | Not applicable |

## The Good News: It's (Almost) Just an apiVersion Change

For every manifest in this course, migration is a single-line change: the `apiVersion` field at the top. No spec fields move, no field names change, nothing inside the spec needs editing.

The only exception is a field called `valuesFile` (singular) on HelmRelease, which became `valuesFiles` (plural, taking a list) in the v2 API. This course never uses it, so you won't encounter it.

**Example:**

Before:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: podinfo
spec:
  interval: 1m0s
  chart:
    spec:
      chart: podinfo
      sourceRef:
        kind: HelmRepository
        name: podinfo
  values:
    replicaCount: 2
```

After:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: podinfo
spec:
  interval: 1m0s
  chart:
    spec:
      chart: podinfo
      sourceRef:
        kind: HelmRepository
        name: podinfo
  values:
    replicaCount: 2
```

Only the first line changed.

## How to Migrate: The `flux migrate` Command

Flux provides a command to do this automatically. You don't have to edit manifests by hand.

### Migrating Your Git Repository

To update all manifests in your repository:

```bash
flux migrate -f . --dry-run
```

This previews the changes without writing anything to disk. It shows you every file it would touch and the old → new versions for each one. Read the output carefully. It should contain the files you expect and nothing surprising.

When you're satisfied with the preview, run the same command without `--dry-run`:

```bash
flux migrate -f .
```

The command will print the list again and ask for confirmation:

```
Are you sure you want to proceed with the above upgrades? [y/N]
```

Type `y` to proceed. This gives you a chance to cancel before rewriting files across your entire repository.

Afterward, review the changes with `git diff` to confirm only apiVersion lines changed:

```bash
git diff
```

Then commit and push like any other change:

```bash
git add -A
git commit -m "Migrate Flux manifests to the stable v1/v2 APIs"
git push
```

### Migrating Cluster Objects

Objects that Flux created before the upgrade are still stored in the cluster under their old API versions. You need to convert them too.

Run `flux migrate` with no flags or arguments:

```bash
flux migrate
```

This operates on the custom resources already in the cluster, not files on disk. It will walk through every resource and update them. This command may take a moment on large clusters.

After cluster migration, verify health:

```bash
flux check
flux get kustomizations
flux get helmreleases -A
```

All Kustomizations should show `Applied revision` and HelmReleases should show their installed revision.

### Command Reference

| Command | Purpose |
|---|---|
| `flux migrate -f . --dry-run` | Preview repository changes without writing |
| `flux migrate -f .` | Migrate all manifests in the current directory |
| `flux migrate -f <path>` | Migrate manifests in a specific directory |
| `flux migrate --dry-run` | Preview cluster object changes |
| `flux migrate` | Migrate all custom resources in the cluster |
| `flux migrate -y` or `flux migrate --yes` | Skip confirmation prompt (use in automation) |

## The Critical Order of Operations

The order you do this matters:

1. **Migrate your Git repository first** — update and commit the manifests
2. **Push the changes** — make sure your cluster can pull the new versions
3. **Migrate cluster objects** — update what's already stored in etcd
4. **Upgrade Flux** — if you're upgrading to a newer version

The reason is critical: if you upgrade Flux to a version that has removed these APIs while your repository still contains them, Flux will be unable to read your own manifests, and you'll be debugging under pressure.

Do not reverse this order.

## Recognizing the Failure

If reconciliation stops, you'll see one of two error messages.

**From Flux itself** — if you run `flux get kustomizations`:

```
HelmRepository/default/podinfo dry-run failed: no matches for kind "HelmRepository" in version "source.toolkit.fluxcd.io/v1beta2"
```

This clearly tells you the cluster doesn't recognize that API version. It's the right message to read first.

**From kubectl** — if you try applying a manifest manually:

```
error: resource mapping not found for kind "HelmRelease" in version "helm.toolkit.fluxcd.io/v2beta1"
ensure CRDs are installed first
```

That last line — "ensure CRDs are installed first" — is misleading. The CRDs ARE installed. They're just installed at newer versions than the one your manifest is asking for. Read the error above it, not below it. The cluster is telling you it has never heard of that API version.

## One More Thing

The lectures that follow this one still show manifests written with the older beta API versions. That's because they were recorded before the migration happened. Everything you learn from them about how Flux works — how sources reconcile, how Helm releases deploy, how Kustomize overlays work — is completely correct and hasn't changed.

When you build along with those lectures, either:

- Use the new API versions from the table above, or
- Build using the old versions and run `flux migrate` over your repository when you're done

The teaching is identical either way.

## Further Reading

- [Flux CD Migration Guide](https://fluxcd.io/flux/migration/) — official migration documentation
- [Flux CD API Versions](https://fluxcd.io/flux/components/) — see current stable versions for all resources
- [Kubernetes API Versioning](https://kubernetes.io/docs/reference/using-api/api-overview/#api-versioning) — deeper explanation of how API deprecation works
- [Flux Release Notes v2.7.0](https://github.com/fluxcd/flux2/releases/tag/v2.7.0) — what changed in the version that removed these APIs

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
