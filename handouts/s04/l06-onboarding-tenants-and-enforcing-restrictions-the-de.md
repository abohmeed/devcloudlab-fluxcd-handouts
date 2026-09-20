---
title: "Onboarding tenants and enforcing restrictions — the dev team"
kicker: "FLUX CD · SECTION 4 · LECTURE 6"
description: "This lecture demonstrates how a development team prepares Kubernetes manifests and Flux CD resources for deployment to a multi-tenant cluster. Using the weather app"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Onboarding tenants and enforcing restrictions — the dev team

*Section 4, Lecture 6 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Prepare a multi-service application's Helm Release manifests for deployment into a tenant-scoped namespace
- Structure the dev team's repository with a Kustomize base and per-environment patch overlays
- Patch chart versions and database credentials differently for staging and production HelmReleases
- Override an application's ingress hostname and enablement per environment through Kustomize patches
- Recognize where sensitive values belong outside Git, ahead of the security lecture

## Overview

This lecture demonstrates how a development team prepares Kubernetes manifests and Flux CD resources for deployment to a multi-tenant cluster. Using the weather app microservices application, we show how to:

- Structure a repository with Kustomize for environment-specific configuration
- Create Helm Releases that respect service accounts and cluster boundaries
- Use Kustomize overlays to customize Helm values per environment
- Secure sensitive values (with security best practices discussed separately)

## The Weather App Architecture

The weather app is a microservices application with three services and a database:

- **Authentication service**: Manages user signup and login; uses MySQL backend
- **Weather service**: Fetches current weather data from a third-party API
- **UI service**: Displays web pages and connects all services together
- **MySQL database**: Stores user credentials and application data

The application is packaged as three Helm charts, with the auth chart including the Bitnami MySQL chart as a dependency (four total charts to deploy).

## Repository Structure

```
<your-repo>/
└── kustomize/
    ├── base/
    │   ├── kustomization.yaml    # Makes base a kustomization root of its own
    │   └── release.yaml          # Unmodified Helm Release manifests
    ├── staging/
    │   ├── auth-patch.yaml       # Staging overrides for auth service
    │   ├── ui-patch.yaml         # Staging overrides for UI service
    │   └── kustomization.yaml    # Kustomize orchestration for staging
    └── production/
        ├── auth-patch.yaml       # Production overrides for auth service
        ├── ui-patch.yaml         # Production overrides for UI service
        └── kustomization.yaml    # Kustomize orchestration for production
```

## Key Concepts

### Multi-Tenancy and Service Accounts

In a multi-tenant Kubernetes cluster:
- The admin team manages cluster resources and namespaces
- Each application team gets a dedicated namespace and service account
- Flux CD uses the specified service account to deploy resources
- Each team controls its application values and Helm repositories via GitOps

### Kustomize Overlays

Kustomize allows us to:
- Maintain one base set of Helm Releases
- Override specific values for different environments (staging vs. production)
- Keep sensitive data separate from base manifests
- Apply patches without modifying the original manifests

## Step-by-Step Commands

### 1. Clone the repository

Work in your own GitLab account: replace `<your-gitlab-username>` and `<your-repo>`
with yours wherever they appear below.

```bash
git clone https://gitlab.com/<your-gitlab-username>/<your-repo>.git
cd <your-repo>
```

Creates a local copy of the development team's repository.

### 2. Create directory structure

```bash
mkdir -p kustomize/base kustomize/staging kustomize/production
```

Sets up the base directory for unmodified manifests and environment-specific overlay directories.

### 3. Verify the structure

```bash
cd kustomize
tree .
```

Displays the directory tree to confirm the structure is correct.

## Final Manifests

### Base Release Manifests (base/release.yaml)

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: weatherapp-auth
  namespace: apps
spec:
  serviceAccountName: dev
  interval: 5m
  chart:
    spec:
      chart: weatherapp-auth
      version: '0.1.0'
      sourceRef:
        kind: HelmRepository
        name: gitlab
        namespace: apps
      interval: 1m
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: weatherapp-ui
  namespace: apps
spec:
  serviceAccountName: dev
  interval: 5m
  chart:
    spec:
      chart: weatherapp-ui
      version: '0.1.0'
      sourceRef:
        kind: HelmRepository
        name: gitlab
        namespace: apps
      interval: 1m
  values:
    service:
      type: ClusterIP
      port: 3000
    ingress:
      enabled: false
      className: ""
      annotations: {}
      hosts: []
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: weatherapp-weather
  namespace: apps
spec:
  serviceAccountName: dev
  interval: 5m
  chart:
    spec:
      chart: weatherapp-weather
      version: '0.1.0'
      sourceRef:
        kind: HelmRepository
        name: gitlab
        namespace: apps
      interval: 1m
  values:
    service:
      type: ClusterIP
      port: 5000
    apikey: <your-rapidapi-key>
```

The weather service needs a RapidAPI subscription key. Put your own key in place of
`<your-rapidapi-key>` — and once the app is real, keep it out of Git altogether, using
one of the approaches in the security notes below.

These Helm Release manifests define how the application charts are deployed. Each specifies:
- The service account (`dev`) that must exist in the `apps` namespace
- The Helm chart name and version
- A reference to the Helm repository (created by the admin team)
- Default values for each service

### Base Kustomization (base/kustomization.yaml)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - release.yaml
```

This four-line file makes `base/` a kustomization root of its own. It is what lets each
overlay reference the **directory** `../base` rather than a file inside it — Kustomize
refuses to load a file that sits outside the root it was pointed at, and an overlay
that says `../base/release.yaml` fails with `security; file ... is not in or below ...`.

### Staging Patches

**staging/auth-patch.yaml**:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: weatherapp-auth
  namespace: apps
spec:
  chart:
    spec:
      version: ">=0.1.0"
  values:
    mysql:
      auth:
        username: authuserstaging
        password: authpasswordstaging
        database: weatherappstaging
        createDatabase: true
```

Allows Flux to install newer patch versions in staging for testing. Uses staging-specific database credentials.

**staging/ui-patch.yaml**:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: weatherapp-ui
  namespace: apps
spec:
  chart:
    spec:
      version: ">=0.1.0"
  values:
    ingress:
      enabled: true
      className: "nginx"
      annotations: {}
      hosts:
        - host: weatherapp.staging
          paths:
            - path: /
              pathType: ImplementationSpecific
```

Enables the ingress controller for the UI service in staging and sets the hostname.

**staging/kustomization.yaml**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
patches:
  - path: auth-patch.yaml
    target:
      kind: HelmRelease
      name: weatherapp-auth
  - path: ui-patch.yaml
    target:
      kind: HelmRelease
      name: weatherapp-ui
```

Orchestrates the base manifests and patches. Kustomize applies patches only to the HelmReleases they target.

### Production Patches

**production/auth-patch.yaml**:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: weatherapp-auth
  namespace: apps
spec:
  chart:
    spec:
      version: "0.1.0"
  values:
    mysql:
      auth:
        username: authuserprod
        password: authpasswordprod
        database: weatherappprod
        createDatabase: true
```

Locks the version to 0.1.0 in production for stability. Uses production-specific database credentials.

**production/ui-patch.yaml**:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: weatherapp-ui
  namespace: apps
spec:
  chart:
    spec:
      version: "0.1.0"
  values:
    ingress:
      enabled: true
      className: "nginx"
      annotations: {}
      hosts:
        - host: weatherapp.production
          paths:
            - path: /
              pathType: ImplementationSpecific
```

Locks the version and sets the production hostname.

**production/kustomization.yaml**:
Identical to the staging version—it references the same patch files.

## Workflow Summary

1. **Dev team creates base manifests**: The Helm Release definitions in `kustomize/base/release.yaml` describe how the application charts are deployed.

2. **Dev team creates overlays**: For each environment, the dev team defines Kustomize patches that customize Helm values (chart versions, credentials, ingress hosts).

3. **Dev team commits to GitLab**: All manifests are pushed to the dev team's repository.

4. **Admin team sets up infrastructure**: The admin team creates the `apps` namespace, the `dev` service account, and provisions a private Helm repository.

5. **Admin team points Flux CD to dev repo**: In the next lecture, the admin team configures Flux CD to read from the dev team's repository and deploy using the appropriate service account and environment.

## Important Notes on Security

The manifests shown here include database credentials directly. In a production environment, use one of these approaches instead:
- Sealed Secrets: Encrypt secrets at rest in Git
- External Secrets: Reference secrets from a vault
- Flux CD Secrets Management: Use Flux's native secret handling

See the security section of this course for detailed implementations.

## Helm Release API Version

This course uses Helm Toolkit Flux CD with `apiVersion: helm.toolkit.fluxcd.io/v2`, which is the current stable version. The older v2beta1 API is no longer supported in Flux v2.7.0 and later.

## Further Reading

- [Kustomize Documentation](https://kustomize.io/)
- [Flux CD Helm Controller](https://fluxcd.io/flux/components/helm/)
- [Helm Release API Reference](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Kustomize Patches](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches/)
- [Bitnami MySQL Helm Chart](https://github.com/bitnami/charts/tree/main/bitnami/mysql)
- [Flux CD Security Best Practices](https://fluxcd.io/flux/security/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
