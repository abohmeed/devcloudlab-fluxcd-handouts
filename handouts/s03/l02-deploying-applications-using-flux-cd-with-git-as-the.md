---
title: "Deploying applications using Flux CD with Git as the Helm chart source"
kicker: "FLUX CD · SECTION 3 · LECTURE 2"
description: "In this lecture, you learned how to deploy Helm Chart releases to Kubernetes using Flux CD with Git as the source of truth. We covered two approaches to Helm Chart"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Deploying applications using Flux CD with Git as the Helm chart source

*Section 3, Lecture 2 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Deploy a Helm chart from a Git repository using a HelmRelease that sources straight from a GitRepository
- Distinguish a HelmRelease's own reconciliation interval from its chart's interval
- Scaffold a Helm chart with `helm create` and enable Ingress in its values.yaml
- Commit a HelmRelease manifest to the cluster's bootstrap path and trigger reconciliation with `flux reconcile`
- Verify a Helm install completed by reading HelmRelease status and waiting for Ready

## Overview

In this lecture, you learned how to deploy Helm Chart releases to Kubernetes using Flux CD with Git as the source of truth. We covered two approaches to Helm Chart installation:

1. **Local Chart Source**: Managing your own chart files and deploying directly from a directory path
2. **Package Repository**: Using pre-built, tested charts from repositories like Bitnami

We demonstrated the first approach: creating a Helm Chart, packaging it in a Git repository, and letting Flux CD automatically deploy it using a HelmRelease resource.

## Key Concepts

### Why separate directories?
- Flux CD's Kustomization controller scans the `clusters/` directory for Kubernetes manifests
- Helm templates must be placed at the repository root or in a separate dedicated directory
- This prevents Flux from attempting to parse Helm templates as raw Kubernetes YAML

### HelmRelease Custom Resource
The HelmRelease custom resource tells Flux CD how and when to deploy a Helm Chart:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx
  namespace: default
spec:
  interval: 1m
  chart:
    spec:
      chart: ./charts/nginx
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
      interval: 1m
```

**What each field means:**
- `apiVersion: helm.toolkit.fluxcd.io/v2` — Specifies the Helm Toolkit API version for Flux v2
- `kind: HelmRelease` — Tells Flux to hand this manifest to the helm-controller
- `metadata.name` — The name of this Helm release
- `metadata.namespace` — Where the release will be installed
- `spec.interval` — How often Flux checks that the installed release still matches this HelmRelease, and corrects any drift
- `spec.chart.spec.chart` — Path to the Helm chart within the Git repository
- `spec.chart.spec.sourceRef` — Reference to the Git repository source
- `spec.chart.spec.interval` — How often Flux checks the chart source for a new chart

### Two Intervals
Understanding the difference is crucial:

- **HelmRelease interval** (`spec.interval`): How often Flux checks that the installed release still matches this HelmRelease, and corrects any drift. Edits to the HelmRelease file itself reach the cluster through the flux-system Kustomization, like any other file in the repository.
- **Chart interval** (`spec.chart.spec.interval`): How often Flux checks the chart source. By default, only a new `version` in `Chart.yaml` produces a new chart — editing a template or `values.yaml` without bumping the version is not picked up. A later lecture shows how to change that with `reconcileStrategy`.

The two intervals govern different things: one keeps the running release in line with its definition, the other watches for a new chart.

## Complete Working Example

### Step 1: Create the Helm Chart

```bash
mkdir charts
cd charts
helm create nginx
```

### Step 2: Customize Chart Values

Edit `charts/nginx/values.yaml` to enable Ingress:

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations: {}
  hosts:
    - host: ""
      paths:
        - path: /
          pathType: ImplementationSpecific
```

### Step 3: Create the HelmRelease Manifest

Create `clusters/my-cluster/nginx-helm-release.yaml`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx
  namespace: default
spec:
  interval: 1m
  chart:
    spec:
      chart: ./charts/nginx
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
      interval: 1m
```

### Step 4: Commit and Merge to Main

```bash
git checkout -b nginx-helm-release
git add -A
git commit -m "Adding the Nginx Helm chart and creating the Flux CD Helm Release resource"
git push --set-upstream origin nginx-helm-release
```

Then create and merge the MR on GitLab.

### Step 5: Trigger Reconciliation

```bash
flux reconcile kustomization flux-system --with-source
```

### Step 6: Verify Deployment

The Helm install takes a few seconds after the reconcile, so wait for the release to become Ready before reading its status:

```bash
kubectl wait --for=condition=Ready helmrelease/nginx -n default --timeout=2m
kubectl get helmrelease
kubectl get pods
```

`kubectl get helmrelease` then shows `READY` as `True` and a status of `Helm install succeeded for release default/nginx.v1 with chart nginx@0.1.0`. If you run it the instant the reconcile returns, `READY` is `Unknown` and the status reads `Running 'install' action` — that is the install still in progress, not a failure.

You should also see the Nginx pod running, along with a Service and Ingress in the default namespace.

## Common Commands

| Command | Purpose |
|---------|---------|
| `helm create <chart-name>` | Scaffold a new Helm chart with default templates |
| `kubectl get helmrelease` | List all HelmRelease resources |
| `kubectl describe helmrelease <name>` | Inspect a HelmRelease and its status |
| `flux reconcile kustomization flux-system --with-source` | Manually trigger Flux to check for changes |
| `flux logs --all-namespaces --follow` | View real-time Flux controller logs |

## Troubleshooting

**HelmRelease not creating?**
- Ensure the MR was merged and reconciliation ran
- Check with `kubectl get helmrelease -n default`
- Review events with `kubectl describe helmrelease nginx -n default`

**Chart files not found?**
- Verify chart directory exists at repository root: `git ls-files charts/`
- Ensure changes are committed and pushed

**Helm chart update not detected?**
- The chart reconciliation interval is the `spec.chart.spec.interval` you set — 1 minute here
- Flux names the generated HelmChart `<helmrelease-namespace>-<helmrelease-name>`, and creates it in the flux-system namespace. For this lesson that is `default-nginx`, so a forced check is `flux reconcile helmchart default-nginx -n flux-system`
- List them with `flux get helmcharts --all-namespaces` if you are not sure of the name

## Further Reading

- [Flux Helm Controller Documentation](https://fluxcd.io/docs/components/helm/)
- [Helm Chart Development](https://helm.sh/docs/chart_template_guide/)
- [GitOps with Flux CD](https://fluxcd.io/docs/gitops-toolkit/)
- [Flux Notification Controller](https://fluxcd.io/docs/components/notification/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
