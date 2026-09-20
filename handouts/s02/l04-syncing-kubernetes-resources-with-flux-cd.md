---
title: "Syncing Kubernetes resources with Flux CD"
kicker: "FLUX CD · SECTION 2 · LECTURE 4"
description: "How Flux CD's GitRepository and Kustomization resources connect a cluster to Git, and how to add a second repository as a GitOps source"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Syncing Kubernetes resources with Flux CD

*Section 2, Lecture 4 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- How the `GitRepository` custom resource tells Flux CD's controllers which Git repository to watch, and how to inspect one with `kubectl`
- How Flux CD authenticates to a private repository using a token stored in a Kubernetes Secret
- Which `ClusterRoleBinding`s let Flux CD's controllers apply manifests to the cluster
- How to point Flux CD at a second Git repository using a `GitRepository` and `Kustomization` pair
- How to watch a sync complete and reach the deployed application through `kubectl port-forward`

## Flux CD is controllers, not a pod you talk to

There is no single "Flux CD pod" that you configure directly. When Flux is bootstrapped into a cluster, it installs several **custom resource definitions (CRDs)** and a set of controllers that watch for objects of those types and reconcile the cluster to match them.

One of those CRDs is `GitRepository`. It answers the question of which Git repository Flux CD should watch. List the `GitRepository` objects in the `flux-system` namespace:

```bash
kubectl get gitrepos -n flux-system
```

The bootstrap process creates one automatically, usually named `flux-system`. Its `url` field points at the repository holding your Flux configuration, and its `status` field carries the commit hash of the branch it last synced — the branch itself was set during bootstrap (`main` by default) and can be changed later by editing the `GitRepository` object, though there's rarely a reason to for the repository that holds Flux's own configuration.

Whether that same repository also holds your application manifests, or you keep application manifests in a separate repository, is a design choice — both are valid GitOps patterns.

## Authenticating to a private repository

If the Git repository is private, Flux CD needs credentials to pull from it. A personal access token created during bootstrap is stored as a Kubernetes Secret so the controllers can use it:

```bash
kubectl get secrets -n flux-system
```

You can reveal the token itself if you need to:

```bash
kubectl get secret flux-system -n flux-system -o jsonpath='{.data.password}' | base64 -d
```

> **Note:** This token typically has read and write access to the repository. Everything in the `flux-system` namespace should be restricted to cluster administrators — regular users should have no access to it.

## Who is allowed to apply changes

Flux CD's controllers need permission to create and modify resources across the cluster. Bootstrap creates two `ClusterRoleBinding`s for this:

```bash
kubectl get clusterrolebindings | grep flux
```

| Binding | Purpose | Access level |
|---|---|---|
| Cluster reconciler | Applies the manifests Flux CD pulls from Git | `cluster-admin` |
| CRD controller | Manages Flux CD's own custom resources | Scoped to Flux's CRDs |

## Adding a second Git repository as a source

To have Flux CD deploy an application, you point it at the repository holding that application's manifests. This example uses [podinfo](https://github.com/stefanprodan/podinfo), a small cloud-native app that displays information about the pod serving the request. Its `kustomize` directory contains a Deployment, a Service, a HorizontalPodAutoscaler, and a `kustomization.yaml` that references them — no patches or overlays.

Pointing Flux CD at it takes two resources, both created in the repository holding your Flux configuration (not in podinfo's repository).

**1. A `GitRepository`**, telling Flux CD the new repository exists:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 30s
  ref:
    branch: master
  url: https://github.com/stefanprodan/podinfo
```

`interval` is how often Flux CD polls Git for new commits. `ref.branch` is the branch to track. Note the `namespace` is `flux-system` — a common mistake is putting this under the namespace you eventually want the *application* to run in, but this object is Flux CD's own configuration and belongs in `flux-system` regardless of where podinfo ends up.

**2. A `Kustomization`**, telling Flux CD what to do once it sees a change:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./kustomize
  prune: true
  sourceRef:
    kind: GitRepository
    name: podinfo
  targetNamespace: default
```

This `interval` is separate from the `GitRepository`'s — it's how often Flux CD re-checks that the live cluster state still matches what's in the `path`, and corrects drift if it doesn't (for example, if someone manually edits the Deployment's replica count). `prune: true` enables garbage collection: resources removed from Git are also removed from the cluster. `sourceRef` links this `Kustomization` back to the `GitRepository` above by name. `targetNamespace` is the one field in this file that is *not* `flux-system` — it's where the podinfo pods themselves will run.

> **Note:** `source.toolkit.fluxcd.io/v1` and `kustomize.toolkit.fluxcd.io/v1` are the current, stable API versions for `GitRepository` and `Kustomization` — nothing here needs updating.

## Pushing and watching the sync

Commit and push both files to your Flux configuration repository:

```bash
git add -A
git commit -m "Add the podinfo GitRepository and Kustomization"
git push
```

If Flux CD has committed to this repository on its own (for example, during an earlier bootstrap), pull those changes first so your push doesn't conflict:

```bash
git pull
```

Flux CD polls for changes every 30 seconds by default. Watch the sync with the Flux CLI:

```bash
flux get kustomizations --watch
```

Once the podinfo `Kustomization` shows `Ready` with `Suspended: False`, the application is installed. Confirm the pods exist:

```bash
kubectl get pods
```

Then forward a local port to reach it:

```bash
kubectl port-forward <pod-name> 9898:9898 --address 0.0.0.0
```

`--address 0.0.0.0` makes the forwarded port listen on every network interface rather than only `localhost` — useful when you're running this on a remote VM rather than your own machine. Open `http://<server-address>:9898` in a browser to see the podinfo UI.

This is more setup than running `kubectl apply -k` against the same directory directly. The payoff is that from here on, changes to the cluster go through Git — reviewed, versioned, and automatically reconciled — rather than through one-off commands.

## Further reading

- [Flux GitRepository reference](https://fluxcd.io/flux/components/source/gitrepositories/)
- [Flux Kustomization reference](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Flux CLI: flux get](https://fluxcd.io/flux/cmd/flux_get/)
- [Kubernetes: kubectl port-forward](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#port-forward)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
