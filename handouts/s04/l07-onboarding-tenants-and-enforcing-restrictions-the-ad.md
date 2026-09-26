---
title: "Onboarding tenants and enforcing restrictions — the admin team"
kicker: "FLUX CD · SECTION 4 · LECTURE 7"
description: "This lecture covers how an admin team uses Flux CD to onboard development teams into a multi-cluster environment while enforcing access restrictions. The key concept is using"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Onboarding tenants and enforcing restrictions — the admin team

*Section 4, Lecture 7 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Generate tenant RBAC (namespace, service account, RoleBinding) with `flux create tenant`
- Create Git and Helm repository sources scoped to a tenant's namespace with `flux create source`
- Wire a tenant's Flux Kustomization to its own service account and Git repository with `flux create kustomization`
- Patch a tenant's Kustomization path per environment through a cluster-level `tenants.yaml`
- Verify a deployed tenant application by ingress hostname and HTTP status code

> **Replace `<your-gitlab-username>` with your own GitLab username** everywhere it
> appears below. The repositories used in the lecture are private, so use your own
> admin repository and your own copy of the weather app repository.

## Lecture Summary

This lecture covers how an admin team uses Flux CD to onboard development teams into a multi-cluster environment while enforcing access restrictions. The key concept is using Kubernetes RBAC combined with Flux CD Kustomization to:

1. Create isolated namespaces and service accounts for each tenant (development team)
2. Grant limited permissions to each tenant's service account
3. Deploy tenant applications from external Git repositories using Flux CD
4. Separate concerns between infrastructure (admin team) and applications (development teams)

## Key Concepts

### Multi-Tenancy in Flux CD

Multi-tenancy allows multiple teams to share Kubernetes clusters while remaining isolated from each other. Each team gets:
- A dedicated namespace
- A service account with limited permissions
- Access to deploy their own applications through Flux CD

### Role-Based Access Control (RBAC)

RBAC in Kubernetes controls who can do what. In this scenario:
- The dev team's service account has admin permissions **only in the "apps" namespace**
- They cannot access other namespaces or cluster-wide resources
- The admin team maintains control of the infrastructure

### Flux CD Kustomization Resource

The `Kustomization` resource from `kustomize.toolkit.fluxcd.io/v1` tells Flux CD:
- Which Git repository to watch for changes
- Which Kustomize patches to apply
- How often to reconcile (sync) changes

This is different from vanilla Kustomize (`kustomize.config.k8s.io/v1beta1`), which is a file template tool.

## Step-by-Step Walkthrough

### 1. Create Directory Structure

```bash
mkdir -p ./tenants/base/dev
mkdir -p ./tenants/staging
mkdir -p ./tenants/production
```

This creates:
- `tenants/base/dev/`: Base manifests shared across environments
- `tenants/staging/`: Staging cluster specific configuration
- `tenants/production/`: Production cluster specific configuration

### 2. Generate Tenant RBAC

```bash
flux create tenant dev --with-namespace=apps --export > ./tenants/base/dev/rbac.yaml
```

This command:
- Tells Flux CD to create a tenant named "dev"
- Constrains it to the "apps" namespace — the flag is `--with-namespace`, not
  `--namespace` (plain `--namespace` is the CLI's own request-scope flag, and using
  it here fails with `✗ with-namespace is required`)
- Exports the YAML instead of applying it to the cluster
- Redirects output to a file

**Generated rbac.yaml contents** (Flux v2.9.4):

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    toolkit.fluxcd.io/tenant: dev
  name: apps
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    toolkit.fluxcd.io/tenant: dev
  name: dev
  namespace: apps
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  labels:
    toolkit.fluxcd.io/tenant: dev
  name: dev-reconciler
  namespace: apps
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: gotk:apps:reconciler
- kind: ServiceAccount
  name: dev
  namespace: apps
```

Three objects, and no ClusterRole of their own: Flux references the `cluster-admin`
role that Kubernetes already ships. The second subject, `gotk:apps:reconciler`, is
a user subject that `flux create tenant` adds. The identity Flux actually acts as
when it reconciles on behalf of this tenant is the `dev` service account, because
the tenant's Kustomization sets `serviceAccountName: dev`.

**Key point:** `cluster-admin` is a cluster-wide role, but it is granted here by a
`RoleBinding` **inside the `apps` namespace**, not a `ClusterRoleBinding`. That one
choice is what confines the dev team's permissions to their own namespace.

### 3. Create Git Repository Source

```bash
flux create source git dev \
  --namespace=apps \
  --url=https://gitlab.com/<your-gitlab-username>/myweatherapp \
  --branch=main \
  --secret-ref=gitlab-auth \
  --export > ./tenants/base/dev/sync.yaml
```

This:
- Creates a `GitRepository` resource named "dev"
- Points to the dev team's weather app repository
- Uses the "gitlab-auth" secret for credentials
- Places it in the "apps" namespace

### 4. Create Helm Repository Source

```bash
flux create source helm gitlab \
  --namespace=apps \
  --url=oci://registry.gitlab.com/<your-gitlab-username>/myweatherapp \
  --secret-ref=gitlab-auth \
  --export >> ./tenants/base/dev/sync.yaml
```

This appends (using `>>`) a `HelmRepository` resource that:
- Points to the GitLab OCI (Open Container Initiative) registry
- Uses the same credentials secret
- Allows Helm charts to be pulled from GitLab's registry

### 5. Create Kustomization Resource

```bash
flux create kustomization dev \
  --namespace=apps \
  --service-account=dev \
  --source=GitRepository/dev \
  --path="./" \
  --export >> ./tenants/base/dev/sync.yaml
```

This appends a `Kustomization` resource that:
- Links the "dev" Git repository as the source
- Uses the "dev" service account to deploy resources
- Watches the root path `./` by default (to be overridden per environment)

**Generated sync.yaml (all three resources combined):**

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: dev
  namespace: apps
spec:
  interval: 1m0s
  ref:
    branch: main
  secretRef:
    name: gitlab-auth
  url: https://gitlab.com/<your-gitlab-username>/myweatherapp
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: gitlab
  namespace: apps
spec:
  interval: 1m0s
  secretRef:
    name: gitlab-auth
  type: oci
  url: oci://registry.gitlab.com/<your-gitlab-username>/myweatherapp
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dev
  namespace: apps
spec:
  interval: 1m0s
  path: ./
  prune: false
  serviceAccountName: dev
  sourceRef:
    kind: GitRepository
    name: dev
```

`prune` is `false` here because `--prune` was not passed to `flux create
kustomization`. The cluster-level `tenants` Kustomization further down *does* set
`prune: true`, which is the one that garbage-collects tenants removed from Git.

### 6. Create Base Kustomization File

```bash
cd ./tenants/base/dev
kustomize create --autodetect
cd -
```

This generates `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- rbac.yaml
- sync.yaml
```

This vanilla Kustomize file simply lists the manifests that belong together.

### 7. Create Staging Cluster Patch

```bash
cat > ./tenants/staging/dev-patch.yaml << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dev
  namespace: apps
spec:
  path: ./kustomize/staging
EOF
```

This creates a JSON Merge Patch that overrides the `path` field in the base Kustomization resource. It tells Flux CD to read the dev team's staging manifests from `./kustomize/staging` instead of the root.

### 8. Create Staging Kustomization File

```bash
cat > ./tenants/staging/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base/dev
patches:
  - path: dev-patch.yaml
EOF
```

This vanilla Kustomize file:
- References the base manifests in `../base/dev`
- Applies the patch `dev-patch.yaml` to override the path

### 9. Create Staging Cluster Configuration

```bash
cat > ./clusters/staging/tenants.yaml << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenants
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./tenants/staging
  prune: true
EOF
```

This Flux CD Kustomization resource:
- Lives in the flux-system namespace (admin space)
- Watches the `tenants/staging` directory in the admin repo
- Reconciles every 5 minutes
- Automatically prunes resources that are removed from Git

### 10. Create Authentication Secret

```bash
flux create secret git gitlab-auth \
  --url=https://gitlab.com/<your-gitlab-username>/myweatherapp.git \
  --username=<your-gitlab-username> \
  --password=<your-personal-access-token> \
  --namespace=apps
```

This command:
- Creates a Kubernetes Secret in the "apps" namespace
- Stores GitLab credentials for authentication
- The secret is not stored in Git (for security)
- Flux CD uses this secret to clone the dev team's repository and pull Helm charts

The weather service needs a second secret in the same namespace — its RapidAPI
key:

```bash
kubectl -n apps create secret generic api-key \
  --from-literal=values.yaml="apikey: <your-rapidapi-key>"
```

Use your own key from [rapidapi.com](https://rapidapi.com/) — subscribe to the
WeatherAPI.com API and paste the key in place of `<your-rapidapi-key>`. The dev
team's repository commits only that placeholder; the `weatherapp-weather`
HelmRelease reads this secret through `valuesFrom`, so the real key is created
against the cluster and never stored in Git — the same rule as `gitlab-auth`.

### 11. Repeat for Production

The process for the production cluster is nearly identical, with two changes:

**Production patch:**

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dev
  namespace: apps
spec:
  path: ./kustomize/production
```

**Production cluster configuration:**

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenants
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./tenants/production
  prune: true
```

## Complete File Structure

After all steps, your repository should have:

```
.
├── clusters/
│   ├── staging/
│   │   └── tenants.yaml
│   └── production/
│       └── tenants.yaml
└── tenants/
    ├── base/
    │   └── dev/
    │       ├── rbac.yaml
    │       ├── sync.yaml
    │       └── kustomization.yaml
    ├── staging/
    │   ├── dev-patch.yaml
    │   └── kustomization.yaml
    └── production/
        ├── dev-patch.yaml
        └── kustomization.yaml
```

## Testing the Deployment

### Verify GitRepository and HelmRepository

```bash
# List all sources in the apps namespace
flux get all -n apps

# Check detailed status of the git repository
flux get source git -n apps

# Check detailed status of the helm repository
flux get source helm -n apps
```

### Verify Helm Releases

```bash
# List all Helm releases created by the dev team
kubectl get helmrelease -n apps

# Get detailed information
kubectl describe helmrelease -n apps
```

### Access the Application

The KinD clusters already publish their ingress controllers on the host — staging
on port 8080, production on port 8081. **Do not run `kubectl port-forward` onto
those ports:** they are already bound, and the command fails with
`address already in use`.

The dev team's ingress rules match on a **hostname**, so a request to plain
`localhost` matches no rule and nginx answers with its default 404. Check what the
rule matches on:

```bash
kubectl config use-context kind-staging
kubectl get ingress -n apps
```

You should see host `weatherapp.staging` (and `weatherapp.production` on the other
cluster). Add one line to the `/etc/hosts` file of the machine running your
browser, pointing both names at the machine running the clusters — `127.0.0.1` if
that is the same machine, otherwise its IP address:

```bash
sudo sh -c 'echo "127.0.0.1 weatherapp.staging weatherapp.production" >> /etc/hosts'
```

Then open:

- staging: `http://weatherapp.staging:8080`
- production: `http://weatherapp.production:8081`

To prove the route without a browser — `302` is the app redirecting to `/login`,
`404` means the Host header matched no ingress rule:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: weatherapp.staging' http://localhost:8080/
```

## Important Differences: Flux CD vs Vanilla Kustomize

| Aspect | Vanilla Kustomize | Flux CD Kustomization |
|--------|-------------------|----------------------|
| **API Version** | `kustomize.config.k8s.io/v1beta1` | `kustomize.toolkit.fluxcd.io/v1` |
| **Purpose** | Template and patch manifests | GitOps automation and deployment |
| **When to Use** | Organizing and structuring files | Continuous reconciliation with Git |
| **Reconciliation** | Manual (`kustomize build`) | Automatic (every interval) |
| **Prune** | Not applicable | Can automatically delete resources |

In this lecture:
- **Vanilla Kustomize** files organize the base and environment-specific patches
- **Flux CD Kustomization** resources automate the deployment and continuous sync

## Further Reading

- [Flux CD Security and RBAC](https://fluxcd.io/flux/security/#controller-permissions)
- [Flux CD Multi-Tenancy](https://fluxcd.io/flux/installation/configuration/multitenancy/)
- [Flux CD Kustomization API Reference](https://fluxcd.io/docs/components/kustomize/kustomization/)
- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Kustomize Official Documentation](https://kustomize.io/)
- [Flux CD Documentation](https://fluxcd.io/flux/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
