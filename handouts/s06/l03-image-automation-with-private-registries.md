---
title: "Image automation with private registries"
kicker: "FLUX CD · SECTION 6 · LECTURE 3"
description: "Set up Flux CD image automation for a private container registry: a pull Secret, an ImageRepository with secretRef, an ImagePolicy and an ImageUpdateAutomation."
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Image automation with private registries

*Section 6, Lecture 3, from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Explain why authenticating to a private registry requires two separate Secrets in two separate namespaces
- Bootstrap Flux with the `image-reflector-controller` and `image-automation-controller` components
- Create an `ImageRepository` that scans a private registry for tags using a `secretRef`-linked Secret
- Configure an `ImagePolicy` to select tags by semantic version range
- Set up an `ImageUpdateAutomation` that commits new image tags back to Git using the `.Changed.Changes` template
- Diagnose common failures such as `ImagePullBackOff`, unauthorized scans, and manifests committed outside the reconciled path

## Overview

This lecture points Flux CD's image automation at a private container registry, one that requires authentication before it will list or serve images.

> **Two placeholders to replace.** Every image path below is written as
> `registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo`. Substitute your own
> GitLab username and project name. The paths are not public and will not work as printed.

## Key Concepts

### Private vs Public Registries

- **Public registries** (ghcr.io, docker.io) allow anyone to pull images without credentials
- **Private registries** (GitLab Container Registry, Amazon ECR, Azure ACR, Docker Registry, Harbor) require authentication, which is how most organizations control access to their own images

### The Authentication Pattern

When Flux CD accesses a private registry, the image-reflector-controller needs credentials. These credentials are stored in a Kubernetes Secret. The Secret contains your registry URL, username, and password (or token), all base64-encoded in Docker authentication format. The ImageRepository resource points to this Secret using `spec.secretRef`, so the controller knows where to find the credentials.

### Two Secrets, Two Jobs

Pulling a private image happens twice, in two different places:

1. **The image-reflector-controller** authenticates to the registry to *list the available tags*. It reads the Secret named by `spec.secretRef` on the ImageRepository, and that Secret must live in the ImageRepository's own namespace (normally `flux-system`).
2. **The kubelet** authenticates to the registry to *pull the image* when it starts your pod. It reads the Secret named by `imagePullSecrets` on the pod spec, and that Secret must live in the **application's** namespace.

They are two copies of the same credentials in two namespaces. Create only the first one and the tag scanning works perfectly while every pod sits in `ImagePullBackOff`.

### The Three Core Resources

1. **ImageRepository**: tells Flux which image to monitor, and scans the registry on an interval for tags, authenticating with the Secret named in `spec.secretRef`
2. **ImagePolicy**: filters those tags (semver, a pattern, release tags) and selects the "latest" one that matches
3. **ImageUpdateAutomation**: rewrites the image reference in your deployment YAML and commits the change to Git, so it is tracked and auditable

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

### Before You Start: Put Some Tags in the Registry

The ImageRepository can only scan tags that exist, so your private registry needs a few versions of podinfo before you begin. Log in to the GitLab registry with a personal access token that has the `write_registry` scope (the pull Secret in Step 1 needs only `read_registry`; pushing needs write):

```bash
docker login registry.gitlab.com -u <your-gitlab-username>
```

Paste the token when Docker asks for the password. Then copy three public podinfo versions into your project's registry:

```bash
for v in 5.0.1 5.0.2 5.0.3; do
  docker pull ghcr.io/stefanprodan/podinfo:$v
  docker tag ghcr.io/stefanprodan/podinfo:$v registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo:$v
  docker push registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo:$v
done
```

With those in place, the scan in Step 3 should find 3 tags, and the policy in Step 4 should resolve to `5.0.3`.

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

> **Do not commit that file as it stands.** Base64 is encoding, not encryption: the
> manifest is one `base64 --decode` away from your token in plain text. If you want the
> Secret in Git, encrypt it first with SOPS or a Sealed Secret, the way the security
> section of this course does it.

### Step 2: Create an ImageRepository Resource

Everything Flux applies has to sit under the path your Flux Kustomization reconciles. If you bootstrapped with `--path=./tenants`, that means somewhere under `tenants/`. Create a folder for this lecture's resources first:

```bash
mkdir -p tenants/image-automation
```

Then create an ImageRepository that points to your private registry image and references the Secret, saving it straight into that folder:

```bash
flux create image repository podinfo-private \
  --image=registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo \
  --interval=5m \
  --secret-ref=gitlab-registry \
  --export > tenants/image-automation/podinfo-private-registry.yaml
```

The YAML it writes is in Complete YAML Examples at the end of this page. The `secretRef` field tells the image-reflector-controller where to find your registry credentials. It takes a **name only** (there is no namespace field on it), so the Secret must exist in the same namespace as the ImageRepository.

Commit and push the file, then have Flux apply it now instead of after its interval:

```bash
git add tenants/image-automation/podinfo-private-registry.yaml
git commit -m "Add the ImageRepository for the private PodInfo registry"
git push
flux reconcile kustomization flux-system --with-source
```

A file committed outside the reconciled path is the quietest failure in Flux: the reconcile reports `✔ applied revision …` and the resource is simply never created.

### Step 3: Verify the ImageRepository

Check if the controller successfully authenticated and found available tags:

```bash
kubectl get imagerepository -n flux-system podinfo-private
kubectl describe imagerepository podinfo-private -n flux-system
```

Look for the `Ready` condition and the `Last Scan Result` block. If it is `True` with a `Tag Count` of 3 (the three tags you pushed before you started), the authentication succeeded. If you see an error, see Troubleshooting below.

### Step 4: Create an ImagePolicy

Define which tags from your repository you want to track:

```bash
flux create image policy podinfo-private \
  --image-ref=podinfo-private \
  --select-semver='>=5.0.0 <6.0.0' \
  --export > tenants/image-automation/podinfo-private-policy.yaml
```

The range is in single quotes so the shell does not read `>` and `<` as redirections. The YAML it writes is in Complete YAML Examples below.

Commit the policy, push it, and reconcile so Flux applies it now:

```bash
git add tenants/image-automation/podinfo-private-policy.yaml
git commit -m "Add the image policy for the private registry"
git push
flux reconcile kustomization flux-system --with-source
```

Check which tag it selected:

```bash
flux get image policy podinfo-private
```

It should resolve to `5.0.3`, the highest tag in the registry that matches the range. That is not the tag your application runs, and the gap between the two is what the automation will close.

### Step 5: Point Your Deployment at the Private Image

First, see what the application runs today:

```bash
kubectl get deployment podinfo -n apps -o yaml | grep image:
```

In this course it is `ghcr.io/stefanprodan/podinfo:5.0.0`, the public image.

Update your deployment manifest (in this course that is `tenants/base/dev/sync.yaml`; in your own repository it is wherever the Deployment lives) so that it pulls from the private registry, carries the pull secret, and marks the line the automation should rewrite:

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

Starting on `5.0.1`, an older version, is deliberate: it gives the automation something to update. The marker format is `{"$imagepolicy": "namespace:policy-name"}`. That one **is** namespaced, unlike `secretRef`, which is a name on its own.

Commit this change, push it, and reconcile:

```bash
git add tenants/base/dev/sync.yaml
git commit -m "Run PodInfo from the private registry with an image policy marker"
git push
flux reconcile kustomization flux-system --with-source
```

Check the deployment again, and list its pods:

```bash
kubectl get deployment podinfo -n apps -o yaml | grep image:
kubectl get pods -n apps
```

The image is now the private `podinfo:5.0.1`, and a new pod is `Running`. That proves the kubelet pulled from your private registry using the Secret in `apps`.

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
  --export > tenants/image-automation/podinfo-private-automation.yaml
```

The YAML it writes is in Complete YAML Examples below. Its `update.strategy` is `Setters`, the strategy that looks for the `$imagepolicy` marker you added in Step 5.

> **`.Updated` is gone.** Older examples on the internet use
> `{{range .Updated.Images}}…{{end}}`. Flux 2.9 removed that field: an automation using it
> is created but parks at `Ready=False` with
> `template uses removed '.Updated' field. Please use '.Changed' instead.` The template
> data is now `.Changed.Changes`, and each change has `.OldValue`, `.NewValue` and
> `.Setter`.

Commit the automation, push it, and reconcile:

```bash
git add tenants/image-automation/podinfo-private-automation.yaml
git commit -m "Add the image update automation"
git push
flux reconcile kustomization flux-system --with-source
```

### Step 7: Verify Everything Works

The automation runs as soon as Flux applies it. The policy picked `5.0.3` and the deployment is on `5.0.1`, so its first run already commits that change to Git. Check that it is ready:

```bash
flux get image update podinfo-automation
```

It should be `True` with the message `repository up-to-date`: it has nothing left to do. Now pull the commit it made, and look at it:

```bash
git pull
git log --oneline -3
```

The pull brings in a commit you did not make, changing one line in `tenants/base/dev/sync.yaml`. The newest commit is authored by `fluxcdbot`, and its message is the old image, an arrow, and the new image. The image line in `sync.yaml` now ends in `5.0.3`, and the `$imagepolicy` marker is still there, so the automation can do the same thing next time.

The automation writes to Git, not the cluster. If your last reconcile ran before its commit landed, reconcile once more, then check the deployment:

```bash
flux reconcile kustomization flux-system --with-source
kubectl get deployment podinfo -n apps -o yaml | grep image:
```

### Step 8: Push a New Tag and Watch It Flow

The point of all of this is that a new image is the only thing you have to do by hand. You are still logged in to the registry from the start, so the push needs no credentials:

```bash
docker pull ghcr.io/stefanprodan/podinfo:5.1.0
docker tag ghcr.io/stefanprodan/podinfo:5.1.0 registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo:5.1.0
docker push registry.gitlab.com/<your-gitlab-username>/<your-project>/podinfo:5.1.0
```

In a real project this push is your CI pipeline publishing the image it has just built. Then let the controllers run (or wait for their intervals) and watch the chain:

```bash
flux reconcile image repository podinfo-private
flux reconcile image policy podinfo-private
flux reconcile image update podinfo-automation
flux reconcile kustomization flux-system --with-source
```

The scan finds a fourth tag, the policy resolves to `5.1.0`, the automation commits the new
tag into `sync.yaml`, and the last reconcile brings that commit down so Flux rolls the
deployment. Check it:

```bash
git pull
kubectl get deployment podinfo -n apps -o yaml | grep image:
kubectl get pods -n apps
```

The deployment runs `podinfo:5.1.0` in a fresh, `Running` pod. Nobody ran `kubectl set image`.

Four reconciles, because there are two loops here and they are separate: the image loop
(repository → policy → automation) ends by writing to Git, and the Git loop
(GitRepository → Kustomization) is what carries it into the cluster. Left alone, both run
on their own intervals and the whole thing happens without you.

Finally, view all the image resources at once:

```bash
flux get images all
```

The ImagePolicy resolves to `5.1.0`, and its message says it was previously `5.0.3`. The ImageUpdateAutomation is ready, with the time of its last run.

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
- Check the image path. A path with a missing segment points at a project that does not exist, and the registry answers with an authentication error rather than a 404, so "unauthorized" is as often a typo as it is a credential problem
- Regenerate the Secret with the correct credentials if needed

### ImageRepository found no tags

**Problem:** The ImageRepository is `Ready=True` but the scan found zero tags.

**Solution:**
- Verify the image path is correct for your registry
- Check that the image actually exists in your registry (see Before You Start)
- For GitLab, the path has three segments: `registry.gitlab.com/<group-or-user>/<project>/<image>`

### The pod is in ImagePullBackOff even though the scan works

**Problem:** Tags are discovered and the automation commits, but the pod will not start. The event reads `failed to authorize` or `403 Forbidden`.

**Solution:** This is the two-Secrets problem above. The image-reflector-controller has credentials; the kubelet does not.
- ```bash
  kubectl get secret gitlab-registry -n apps
  ```
  must return a Secret, not `NotFound`
- The pod spec must carry `imagePullSecrets: [{name: gitlab-registry}]`

### ImageUpdateAutomation not updating the deployment

**Problem:** The automation is not ready, or it is ready but the deployment image isn't being updated.

**Solution:**
- If it is not ready and the message is `template uses removed '.Updated' field`, see the note in Step 6
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

## A Note for Production

Automatic updates straight to `main` suit staging. In production, push the automation's commits to a separate branch instead of main, so every update arrives as a merge request that someone reviews.

## Key Takeaways

- Private registries require a Kubernetes Secret to store authentication credentials
- The ImageRepository resource uses `secretRef` to reference the authentication Secret, by **name only**: the Secret has to be in the ImageRepository's own namespace
- A second copy of that Secret belongs in the application's namespace, referenced by `imagePullSecrets`, or the kubelet cannot pull the image even when the scan works
- Once authentication is set up, the rest of the image automation workflow is identical to public registries
- Everything Flux applies has to sit under the path its Kustomization reconciles. A manifest committed outside it is never created, and the reconcile still reports success
- Keep registry credentials in Kubernetes Secrets, and if a Secret goes into Git, encrypt it first: base64 is encoding, not protection

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses: Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
