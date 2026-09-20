---
title: "Image automation with private registries"
kicker: "FLUX CD · SECTION 6 · LECTURE 3"
description: "This lecture shows you how to set up image automation in Flux CD for private container registries. Unlike public registries like Docker Hub or GitHub Container Registry"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Image automation with private registries

*Section 6, Lecture 3 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Explain why authenticating to a private registry requires two separate Secrets in two separate namespaces
- Bootstrap Flux with the `image-reflector-controller` and `image-automation-controller` components
- Create an `ImageRepository` that scans a private registry for tags using a `secretRef`-linked Secret
- Configure an `ImagePolicy` to select tags by semantic version range
- Set up an `ImageUpdateAutomation` that commits new image tags back to Git using the `.Changed.Changes` template
- Diagnose common failures such as `ImagePullBackOff`, unauthorized scans, and manifests committed outside the reconciled path

## Overview

This lecture shows you how to set up image automation in Flux CD for private container registries. Unlike public registries like Docker Hub or GitHub Container Registry, private registries require authentication. Flux CD uses a Kubernetes Secret to store registry credentials, and the ImageRepository resource references this Secret using the `secretRef` field.

> **Two placeholders to replace.** Every image path below is written as
> `registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo`. Substitute your own
> GitLab username and project name — the paths are not public and will not work as printed.

## Key Concepts

### Private vs Public Registries

- **Public registries** (ghcr.io, docker.io) allow anyone to pull images without credentials
- **Private registries** (GitLab Container Registry, Amazon ECR, Azure ACR, Docker Registry, Harbor) require authentication to pull images
- Most organizations use private registries to control access to company-owned container images

### The Authentication Pattern

When Flux CD accesses a private registry, the image-reflector-controller needs credentials. These credentials are stored in a Kubernetes Secret. The Secret contains your registry URL, username, and password (or token), all base64-encoded in Docker authentication format. The ImageRepository resource points to this Secret using `spec.secretRef`, so the controller knows where to find the credentials.

### Two Secrets, Two Jobs

This catches people out, so it is worth stating plainly. Pulling a private image happens twice, in two different places:

1. **The image-reflector-controller** authenticates to the registry to *list the available tags*. It reads the Secret named by `spec.secretRef` on the ImageRepository, and that Secret must live in the ImageRepository's own namespace — normally `flux-system`.
2. **The kubelet** authenticates to the registry to *pull the image* when it starts your pod. It reads the Secret named by `imagePullSecrets` on the pod spec, and that Secret must live in the **application's** namespace.

They are two copies of the same credentials in two namespaces. Create only the first one and the tag scanning works perfectly while every pod sits in `ImagePullBackOff`.

### The Three Core Resources

1. **ImageRepository** — Tells Flux which image to monitor in your registry
   - Contains `spec.secretRef` to reference the authentication Secret
   - Scans the registry on a regular interval to discover available tags
   - Stores the list of tags in its status

2. **ImagePolicy** — Defines which tags to consider
   - Filters the list of tags from the repository
   - Examples: semantic versioning tags, release tags, tags matching a pattern
   - Selects the "latest" tag that matches your policy

3. **ImageUpdateAutomation** — Automatically updates your deployment
   - Watches the ImagePolicy for new tags
   - Updates the image reference in your deployment YAML
   - Commits the change to Git so it's tracked and auditable

### Before Any of It Works: the Two Extra Controllers

The image-reflector-controller and image-automation-controller are **not** installed by a default `flux bootstrap`. Ask for them explicitly:

```bash
flux bootstrap gitlab \
  --owner=<your-gitlab-username> \
  --repository=<your-project> \
  --branch=main \
  --path=./tenants \
  --personal \
  --token-auth \
  --components-extra=image-reflector-controller,image-automation-controller
```

Check they are running:

```bash
kubectl get deployment -n flux-system | grep image
```

## Setting Up Private Registry Automation

### Step 1: Create a Registry Pull Secret

Create a Kubernetes Secret with your registry credentials, in the namespace where the ImageRepository will live:

```bash
kubectl create secret docker-registry gitlab-registry \
  --docker-server=registry.gitlab.com \
  --docker-username=<your-gitlab-username> \
  --docker-password=<your-personal-access-token> \
  -n flux-system
```

For GitLab, use a personal access token with `read_registry` scope instead of your password.

Create the same Secret in the namespace your application runs in, so the kubelet can pull the image:

```bash
kubectl create secret docker-registry gitlab-registry \
  --docker-server=registry.gitlab.com \
  --docker-username=<your-gitlab-username> \
  --docker-password=<your-personal-access-token> \
  -n apps
```

To see the manifest a Secret produces without creating anything, add `--dry-run=client -o yaml`:

```bash
kubectl create secret docker-registry gitlab-registry \
  --docker-server=registry.gitlab.com \
  --docker-username=REPLACE_ME \
  --docker-password=REPLACE_ME \
  -n flux-system --dry-run=client -o yaml
```

> **Do not commit that file as it stands.** Base64 is encoding, not encryption — the
> manifest is one `base64 --decode` away from your token in plain text. If you want the
> Secret in Git, encrypt it first with SOPS or a Sealed Secret, the way the security
> section of this course does it.

### Step 2: Create an ImageRepository Resource

Create an ImageRepository that points to your private registry image and references the Secret:

```bash
flux create image repository podinfo-private \
  --image=registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo \
  --interval=5m \
  --secret-ref=gitlab-registry \
  --export > podinfo-private-registry.yaml
```

Or manually write the YAML:

```yaml
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImageRepository
metadata:
  name: podinfo-private
  namespace: flux-system
spec:
  image: registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo
  interval: 5m
  secretRef:
    name: gitlab-registry
```

The `secretRef` field tells the image-reflector-controller where to find your registry credentials. It takes a **name only** — there is no namespace field on it — so the Secret must exist in the same namespace as the ImageRepository.

Commit the ImageRepository to a path your Flux Kustomization actually reconciles. If you bootstrapped with `--path=./tenants`, that means somewhere under `tenants/`:

```bash
mkdir -p tenants/image-automation
mv podinfo-private-registry.yaml tenants/image-automation/
git add tenants/image-automation/podinfo-private-registry.yaml
git commit -m "Add private registry setup for image automation"
git push
```

A file committed outside the reconciled path is the quietest failure in Flux: the reconcile reports `✔ applied revision …` and the resource is simply never created.

### Step 3: Verify the ImageRepository

Check if the controller successfully authenticated and found available tags:

```bash
kubectl get imagerepository -n flux-system podinfo-private
kubectl describe imagerepository podinfo-private -n flux-system
```

Look for the `Ready` condition and the `Last Scan Result` block. If it is `True` with a `Tag Count` and a list of `Latest Tags`, the authentication succeeded. If you see an error, check that:
- The Secret exists in the flux-system namespace
- The credentials are correct for your registry
- The image path is spelled correctly, including every path segment

### Step 4: Create an ImagePolicy

Define which tags from your repository you want to track:

```bash
flux create image policy podinfo-private \
  --image-ref=podinfo-private \
  --select-semver='>=5.0.0 <6.0.0' \
  --export > podinfo-private-policy.yaml
```

Or manually write the YAML:

```yaml
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImagePolicy
metadata:
  name: podinfo-private
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: podinfo-private
  policy:
    semver:
      range: '>=5.0.0 <6.0.0'
```

Commit the policy to Git, under the reconciled path again:

```bash
git add tenants/image-automation/podinfo-private-policy.yaml
git commit -m "Add image policy for private registry"
git push
```

Check which tag it selected:

```bash
flux get image policy podinfo-private
```

### Step 5: Point Your Deployment at the Private Image

Update your deployment manifest — in this course that is `tenants/base/dev/sync.yaml`; in your own repository it is wherever the Deployment lives — so that it pulls from the private registry, carries the pull secret, and marks the line the automation should rewrite:

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: gitlab-registry
      containers:
        - name: podinfo
          image: registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo:5.0.1 # {"$imagepolicy": "flux-system:podinfo-private"}
```

The marker format is `{"$imagepolicy": "namespace:policy-name"}`. That one **is** namespaced — unlike `secretRef`, which is a name on its own.

Commit this change:

```bash
git add tenants/base/dev/sync.yaml
git commit -m "Run PodInfo from the private registry with an image policy marker"
git push
```

### Step 6: Create an ImageUpdateAutomation Resource

Create the automation that watches the policy and updates your deployment:

```bash
flux create image update podinfo-automation \
  --interval=30m \
  --git-repo-ref=flux-system \
  --git-repo-path="./tenants/base/dev" \
  --checkout-branch=main \
  --push-branch=main \
  --author-name=fluxcdbot \
  --author-email=fluxcdbot@users.noreply.gitlab.com \
  --commit-template='{{range .Changed.Changes}}{{println .OldValue "->" .NewValue}}{{end}}' \
  --export > podinfo-private-automation.yaml
```

Or manually write the YAML:

```yaml
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImageUpdateAutomation
metadata:
  name: podinfo-automation
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
        email: fluxcdbot@users.noreply.gitlab.com
        name: fluxcdbot
      messageTemplate: '{{range .Changed.Changes}}{{println .OldValue "->" .NewValue}}{{end}}'
    push:
      branch: main
  update:
    path: ./tenants/base/dev
    strategy: Setters
```

> **`.Updated` is gone.** Older examples on the internet use
> `{{range .Updated.Images}}…{{end}}`. Flux 2.9 removed that field: an automation using it
> is created but parks at `Ready=False` with
> `template uses removed '.Updated' field. Please use '.Changed' instead.` The template
> data is now `.Changed.Changes`, and each change has `.OldValue`, `.NewValue` and
> `.Setter`.

Commit the automation to Git:

```bash
git add tenants/image-automation/podinfo-private-automation.yaml
git commit -m "Add image update automation"
git push
```

### Step 7: Verify Everything Works

Check that all three resources are ready:

```bash
flux get images all
```

Reconcile the three of them in order to trigger the automation immediately:

```bash
flux reconcile image repository podinfo-private
flux reconcile image policy podinfo-private
flux reconcile image update podinfo-automation
```

Wait a moment, then pull the latest Git changes:

```bash
git pull
git log --oneline -5
```

You should see a commit authored by `fluxcdbot` whose message names the old and new image references.

That commit is in **Git**, not yet in the cluster. The Kustomization has to reconcile it
before the deployment changes — either wait for its interval (10 minutes by default) or
pull it in now:

```bash
flux reconcile kustomization flux-system --with-source
```

Check that the deployment image was updated:

```bash
kubectl get deployment/podinfo -n apps -o yaml | grep 'image:'
kubectl get pods -n apps
```

### Step 8: Push a New Tag and Watch It Flow

The point of all of this is that a new image is the only thing you have to do by hand. Push one:

```bash
docker pull ghcr.io/stefanprodan/podinfo:5.1.0
docker tag ghcr.io/stefanprodan/podinfo:5.1.0 registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo:5.1.0
docker push registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo:5.1.0
```

Then let the controllers run — or wait for their intervals — and watch the chain:

```bash
flux reconcile image repository podinfo-private
flux reconcile image policy podinfo-private
flux reconcile image update podinfo-automation
flux reconcile kustomization flux-system --with-source
```

The scan finds a fourth tag, the policy resolves to `5.1.0`, the automation commits the new
tag into `sync.yaml`, and the last reconcile brings that commit down so Flux rolls the
deployment. Nobody ran `kubectl set image`.

Four reconciles, because there are two loops here and they are separate: the image loop
(repository → policy → automation) ends by writing to Git, and the Git loop
(GitRepository → Kustomization) is what carries it into the cluster. Left alone, both run
on their own intervals and the whole thing happens without you.

## Troubleshooting

### ImageRepository shows authentication error

**Problem:** The ImageRepository status shows `Ready=False` and the message mentions `UNAUTHORIZED` or `authentication required`.

**Solution:**
- Verify the Secret exists and is in the correct namespace:
  ```bash
  kubectl get secret gitlab-registry -n flux-system
  ```
- Check that your credentials (username/token) are correct
- For GitLab, ensure your token has the `read_registry` scope
- Check the image path. A path with a missing segment points at a project that does not exist, and the registry answers with an authentication error rather than a 404 — so "unauthorized" is as often a typo as it is a credential problem
- Regenerate the Secret with the correct credentials if needed

### ImageRepository found no tags

**Problem:** The ImageRepository is `Ready=True` but the scan found zero tags.

**Solution:**
- Verify the image path is correct for your registry
- Check that the image actually exists in your registry
- For GitLab, the path has three segments: `registry.gitlab.com/<group-or-user>/<project>/<image>`

### The pod is in ImagePullBackOff even though the scan works

**Problem:** Tags are discovered and the automation commits, but the pod will not start. The event reads `failed to authorize` or `403 Forbidden`.

**Solution:** This is the two-Secrets problem above. The image-reflector-controller has credentials; the kubelet does not.
- ```bash
  kubectl get secret gitlab-registry -n apps
  ```
  must return a Secret, not `NotFound`
- The pod spec must carry `imagePullSecrets: [{name: gitlab-registry}]`

### ImageUpdateAutomation is not ready

**Problem:** The automation exists but `flux get image update` shows `READY False`.

**Solution:**
- ```bash
  kubectl describe imageupdateautomation podinfo-automation -n flux-system
  ```
- If the message is `template uses removed '.Updated' field`, rewrite the message template to use `.Changed` — see the note in Step 6

### ImageUpdateAutomation not updating the deployment

**Problem:** The automation is ready but the deployment image isn't being updated.

**Solution:**
- Check that the image policy marker is present on the image line:
  ```bash
  grep '$imagepolicy' tenants/base/dev/sync.yaml
  ```
- Verify the policy name matches exactly: `flux-system:podinfo-private`
- Check that `update.path` on the automation contains the file you marked
- Check the automation status for errors:
  ```bash
  kubectl describe imageupdateautomation podinfo-automation -n flux-system
  ```

### Git push fails

**Problem:** The automation tries to update the deployment but fails to push to Git.

**Solution:**
- Check the credentials Flux holds for the repository. A cluster bootstrapped with `--token-auth` pushes with the token in the `flux-system` Secret; one bootstrapped with an SSH deploy key needs that key to have **write** access
- Verify the branch named in `spec.git.push.branch` is not protected against the identity Flux is using
- Check the image-automation-controller logs:
  ```bash
  kubectl logs -n flux-system deployment/image-automation-controller -f
  ```
  A successful run logs `pushed commit '…' to branch 'main'`

### The resources were committed but never created

**Problem:** `flux reconcile kustomization … --with-source` prints `✔ applied revision …`, and then `kubectl get imagerepository -n flux-system` says `No resources found`.

**Solution:** The files are outside the path the Kustomization reconciles. Check where it points, and move the files under it:

```bash
flux get kustomizations -A
kubectl get kustomization flux-system -n flux-system -o jsonpath='{.spec.path}'
```

## Complete YAML Examples

```yaml
---
# Registry credentials. Generate this with:
#   kubectl create secret docker-registry gitlab-registry \
#     --docker-server=registry.gitlab.com \
#     --docker-username=<your-gitlab-username> \
#     --docker-password=<your-personal-access-token> \
#     -n flux-system --dry-run=client -o yaml
# The value below is a placeholder and will not authenticate anywhere:
# it decodes to REPLACE_ME:REPLACE_ME.
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-registry
  namespace: flux-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: eyJhdXRocyI6eyJyZWdpc3RyeS5naXRsYWIuY29tIjp7InVzZXJuYW1lIjoiUkVQTEFDRV9NRSIsInBhc3N3b3JkIjoiUkVQTEFDRV9NRSIsImF1dGgiOiJVa1ZRVEVGRFJWOU5SVHBTUlZCTVFVTkZYMDFGIn19fQ==
---
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImageRepository
metadata:
  name: podinfo-private
  namespace: flux-system
spec:
  image: registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo
  interval: 5m
  secretRef:
    name: gitlab-registry
---
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImagePolicy
metadata:
  name: podinfo-private
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: podinfo-private
  policy:
    semver:
      range: '>=5.0.0 <6.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImageUpdateAutomation
metadata:
  name: podinfo-automation
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
        email: fluxcdbot@users.noreply.gitlab.com
        name: fluxcdbot
      messageTemplate: '{{range .Changed.Changes}}{{println .OldValue "->" .NewValue}}{{end}}'
    push:
      branch: main
  update:
    path: ./tenants/base/dev
    strategy: Setters
```

## Further Reading

- [Flux Image Automation Documentation](https://fluxcd.io/flux/components/image/)
- [ImageRepository Reference](https://fluxcd.io/flux/components/image/imagerepositories/)
- [ImagePolicy Reference](https://fluxcd.io/flux/components/image/imagepolicies/)
- [ImageUpdateAutomation Reference](https://fluxcd.io/flux/components/image/imageupdateautomations/)
- [ImageUpdateAutomation message template](https://fluxcd.io/flux/components/image/imageupdateautomations/#commit-message-template)
- [Flux Git Integration](https://fluxcd.io/flux/components/source/gitrepositories/)
- [Kubernetes Docker Registry Secrets](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)
- [GitLab Container Registry Documentation](https://docs.gitlab.com/user/packages/container_registry/)

## Key Takeaways

- Private registries require a Kubernetes Secret to store authentication credentials
- The ImageRepository resource uses `secretRef` to reference the authentication Secret, by **name only** — the Secret has to be in the ImageRepository's own namespace
- A second copy of that Secret belongs in the application's namespace, referenced by `imagePullSecrets`, or the kubelet cannot pull the image even when the scan works
- The image-reflector-controller scans the private registry using credentials from the Secret
- Once authentication is set up, the rest of the image automation workflow is identical to public registries
- Use ImagePolicy to select which tags to track, and ImageUpdateAutomation to update your deployments
- Always verify that the ImageRepository is ready and has discovered tags before relying on the automation
- Everything Flux applies has to sit under the path its Kustomization reconciles — a manifest committed outside it is never created, and the reconcile still reports success
- Keep registry credentials in Kubernetes Secrets, and if a Secret goes into Git, encrypt it first: base64 is encoding, not protection

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
