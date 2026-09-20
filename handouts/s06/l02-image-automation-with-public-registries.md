---
title: "Image automation with public registries"
kicker: "FLUX CD · SECTION 6 · LECTURE 2"
description: "Build a complete Flux CD image automation pipeline against a public registry: ImageRepository, ImagePolicy, and an ImageUpdateAutomation that commits to Git."
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Image automation with public registries

*Section 6, Lecture 2 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Enable Flux's image-reflector and image-automation controllers with `--components-extra` on bootstrap
- Create an **ImageRepository** that scans a public container registry for available tags
- Write an **ImagePolicy** that selects the latest tag inside a semantic-versioning range
- Mark a Deployment's image line so Flux knows which policy governs it, then generate an **ImageUpdateAutomation** that commits the resolved tag back to Git
- Verify the full loop end to end, from a new tag in the registry to an updated Deployment in the cluster

## Overview

Flux's image automation watches a container registry, decides which tag is "latest" according to a policy you define, and pushes that decision into your Deployment manifest as a Git commit — no `kubectl set image`, and no one editing YAML by hand. Three resources do the work:

1. **ImageRepository** scans the registry and records which tags exist.
2. **ImagePolicy** filters those tags down to the one that matches your rule.
3. **ImageUpdateAutomation** rewrites the marked image line in Git and pushes the commit.

This lecture builds all three against a **public** registry — GitHub Container Registry, in this case — so there is no authentication to configure. The [next lecture](l03-image-automation-with-private-registries.md) adds the Secret and `secretRef` a private registry needs; everything else carries over unchanged.

## Enable the Two Extra Controllers

The image-reflector-controller and image-automation-controller are **not** part of a default `flux bootstrap`. Skip this step and every command below fails silently or reports resources that never become ready — nothing in this lecture works without it.

Bootstrapping also needs to know your Git token has **write** access, since the automation pushes commits. If your cluster was bootstrapped without `--read-write-key`, delete the Secret Flux stores its token in so bootstrap recreates it correctly:

```bash
kubectl delete secret flux-system -n flux-system
```

`flux bootstrap` is idempotent — running it again against a cluster that is already bootstrapped does not break anything, it simply reconciles to the same desired state, now including the extra components:

```bash
flux bootstrap github \
  --owner=<your-github-username> \
  --repository=<your-repository> \
  --path=clusters/staging \
  --personal \
  --read-write-key \
  --components-extra=image-reflector-controller,image-automation-controller
```

`GITHUB_TOKEN` must be exported in your shell before you run this. Pull afterward, since bootstrap may have committed changes on the remote:

```bash
git pull
```

Confirm the two new controllers are running:

```bash
kubectl get pods -n flux-system
```

You should see an `image-reflector-controller-...` pod and an `image-automation-controller-...` pod alongside the existing Flux controllers.

## Deploy the Application You'll Automate

This lecture automates [podinfo](https://github.com/stefanprodan/podinfo), pulled from `ghcr.io/stefanprodan/podinfo` — GitHub's public container registry, no credentials required. Add a Deployment for it under your tenant path (here, `tenants/base/dev/sync.yaml`), pinned to an old tag on purpose:

```yaml
# tenants/base/dev/sync.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: podinfo
  namespace: apps
spec:
  selector:
    matchLabels:
      app: podinfo
  template:
    metadata:
      labels:
        app: podinfo
    spec:
      containers:
        - name: podinfod
          image: ghcr.io/stefanprodan/podinfo:5.0.0
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 9898
              protocol: TCP
```

Commit, push, and reconcile the chain of Kustomizations that leads to it:

```bash
git add tenants/base/dev/sync.yaml
git commit -m "Deploy podinfo 5.0.0 for image automation"
git push

flux reconcile kustomization flux-system --with-source
flux reconcile kustomization tenants --with-source
flux reconcile kustomization dev --with-source
```

Confirm the pod is running and note the current image tag — you'll compare it after automation runs:

```bash
kubectl get pods -n apps | grep podinfo
kubectl get deployment/podinfo -n apps -o yaml | grep 'image:'
```

## Create an ImageRepository

An **ImageRepository** tells Flux which registry image to scan and how often. Generate one with the Flux CLI and export it to a file instead of applying it directly, so it goes through Git like everything else Flux manages:

```bash
flux create image repository podinfo \
  --image=ghcr.io/stefanprodan/podinfo \
  --interval=5m \
  --export > podinfo-registry.yaml
```

```yaml
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImageRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  image: ghcr.io/stefanprodan/podinfo
  interval: 5m
```

No `secretRef` — the registry is public, so the image-reflector-controller needs no credentials to list its tags. Commit the file to a path your Flux Kustomization reconciles, then reconcile:

```bash
git add podinfo-registry.yaml
git commit -m "Add ImageRepository for podinfo"
git push

flux reconcile kustomization flux-system --with-source
```

Check that the scan succeeded:

```bash
flux get image repository podinfo
kubectl get imagerepository -n flux-system
```

A `Ready=True` status with a tag count means Flux successfully connected to `ghcr.io` and listed the available tags. You can see the same list yourself by visiting the registry page for [ghcr.io/stefanprodan/podinfo](https://github.com/stefanprodan/podinfo/pkgs/container/podinfo) in a browser.

## Create an ImagePolicy

An **ImageRepository** only lists tags — it does not decide which one is "latest." That's the job of an **ImagePolicy**. Suppose your application isn't ready for podinfo's next major version: you want Flux to track the newest tag from `5.0.0` up to, but excluding, `6.0.0`.

```bash
flux create image policy podinfo \
  --image-ref=podinfo \
  --select-semver='>=5.0.0 <6.0.0' \
  --export > podinfo-policy.yaml
```

```yaml
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImagePolicy
metadata:
  name: podinfo
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: podinfo
  policy:
    semver:
      range: '>=5.0.0 <6.0.0'
```

`imageRepositoryRef` links the policy to the ImageRepository you already created — the policy filters that repository's tag list, it doesn't scan the registry itself. Commit and reconcile:

```bash
git add podinfo-policy.yaml
git commit -m "Add ImagePolicy for podinfo"
git push

flux reconcile kustomization flux-system --with-source
```

```bash
flux get image policy podinfo
```

The output shows the tag the policy resolved to. If podinfo's registry has moved past `6.0.0`, the policy still reports the highest `5.x.x` release — the constraint is doing exactly what it's for.

## Mark the Deployment for Automatic Updates

Flux now knows which tag is "latest" according to your policy, but it doesn't yet know which line in your manifests to update. You tell it with a marker comment next to the image field:

```yaml
image: ghcr.io/stefanprodan/podinfo:5.0.0 # {"$imagepolicy": "flux-system:podinfo"}
```

The marker format is `{"$imagepolicy": "namespace:policy-name"}` — it must be a YAML comment (the leading `#`), since the Kubernetes API doesn't understand this string and would reject it as a real field. `flux-system:podinfo` names the namespace and the ImagePolicy you created above.

Edit `tenants/base/dev/sync.yaml` to add the marker, then commit:

```bash
git add tenants/base/dev/sync.yaml
git commit -m "Mark podinfo image for automatic updates"
git push
```

## Create an ImageUpdateAutomation

The last resource, **ImageUpdateAutomation**, is what actually watches marked manifests, rewrites the tag, and commits the change to Git.

```bash
flux create image update flux-system \
  --interval=30m \
  --git-repo-ref=flux-system \
  --git-repo-path="./tenants/base/dev" \
  --checkout-branch=main \
  --push-branch=main \
  --author-name=fluxcdbot \
  --author-email=fluxcdbot@users.noreply.github.com \
  --commit-template='{{range .Changed.Changes}}{{println .OldValue "->" .NewValue}}{{end}}' \
  --export > flux-system-automation.yaml
```

> **Since this video was recorded:** the video's commit template uses
> `{{range .Updated.Images}}{{println .}}{{end}}`. Flux 2.9 removed the `.Updated` field —
> an automation built with it is created but sits at `Ready=False` with
> `template uses removed '.Updated' field. Please use '.Changed' instead.` The command
> above uses the current `.Changed.Changes` field, where each entry carries `.OldValue`,
> `.NewValue` and `.Setter`.

```yaml
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImageUpdateAutomation
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 30m
  sourceRef:
    kind: GitRepository
    name: flux-system
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxcdbot@users.noreply.github.com
        name: fluxcdbot
      messageTemplate: '{{range .Changed.Changes}}{{println .OldValue "->" .NewValue}}{{end}}'
    push:
      branch: main
  update:
    path: ./tenants/base/dev
    strategy: Setters
```

`git-repo-path` (`update.path` in the YAML) is the directory Flux scans for marker comments — it must contain the manifest you just edited. `author-name` is deliberately not your own username: a distinct identity like `fluxcdbot` makes it obvious in `git log` which commits were made by a human and which were made by the automation.

Commit and reconcile:

```bash
git add flux-system-automation.yaml
git commit -m "Add ImageUpdateAutomation for podinfo"
git push

flux reconcile kustomization flux-system --with-source
```

## Verify the Loop End to End

Give the automation a moment, then pull:

```bash
git pull
git log --oneline -3
```

You should see a new commit authored by `fluxcdbot`. Confirm the manifest itself changed:

```bash
cat tenants/base/dev/sync.yaml
```

The image tag should now be the highest `5.x.x` release the ImagePolicy resolved — no longer `5.0.0`. That commit is in Git, not yet in the cluster; bring it down immediately instead of waiting for the Kustomization's own interval:

```bash
flux reconcile kustomization flux-system --with-source
```

Check the running Deployment:

```bash
kubectl get deployment/podinfo -n apps -o yaml | grep 'image:'
```

From here, the loop runs on its own. Whenever a new tag lands in `ghcr.io/stefanprodan/podinfo` that fits the policy's semver range, the image-reflector-controller finds it on its next scan, the ImagePolicy resolves it as the new latest, the ImageUpdateAutomation commits the change, and the existing Flux/Kustomization reconciliation applies it — all as ordinary GitOps commits, with no one ever hand-editing a tag or running the `latest` label as a stand-in for version tracking.

## Further reading

- [Flux Image Automation Documentation](https://fluxcd.io/flux/components/image/)
- [ImageRepository Reference](https://fluxcd.io/flux/components/image/imagerepositories/)
- [ImagePolicy Reference](https://fluxcd.io/flux/components/image/imagepolicies/)
- [ImageUpdateAutomation Reference](https://fluxcd.io/flux/components/image/imageupdateautomations/)
- [ImageUpdateAutomation commit message template](https://fluxcd.io/flux/components/image/imageupdateautomations/#commit-message-template-data)
- [Flux bootstrap github command](https://fluxcd.io/flux/cmd/flux_bootstrap_github/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
