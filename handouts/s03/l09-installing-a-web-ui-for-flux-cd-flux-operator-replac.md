---
title: "Installing a web UI for Flux CD — Flux Operator replaces Weave GitOps"
kicker: "FLUX CD · SECTION 3 · LECTURE 9"
description: "Flux CD is powerful from the command line, but sometimes a visual interface is helpful for understanding your deployments at a glance. The Flux Operator, maintained by"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Installing a web UI for Flux CD — Flux Operator replaces Weave GitOps

*Section 3, Lecture 9 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Install the Flux Operator web UI as a Flux CD HelmRelease with `serverOnly: true`
- Expose the dashboard through an Ingress, or fall back to `kubectl port-forward` on its port 9080
- Navigate the dashboard's Resources, Workloads, Events and Favorites views to inspect Flux-managed objects
- Read a HelmRelease's Specification and Status tabs as the equivalent of `kubectl get -o yaml`
- Recognize the dashboard's read-only default and lack of authentication as suited to private, internal clusters

## Overview

Flux CD is powerful from the command line, but sometimes a visual interface is helpful for understanding your deployments at a glance. The Flux Operator, maintained by ControlPlane in close collaboration with the Flux project, provides a web dashboard for Flux CD. It allows you to:

- View all deployed applications (Helm releases and Kustomizations)
- See the status and details of each resource
- View event logs for reconciliation and errors
- Inspect YAML manifests as they exist in the cluster
- Understand application dependencies
- Monitor Flux controller health

This lecture covers installing the Flux Operator web UI as a Flux HelmRelease with an Ingress endpoint, making it accessible across your cluster.

## Prerequisites

- A Kubernetes cluster with Flux v2.9 or later installed
- An ingress controller configured (Nginx or similar)
- `kubectl` configured to access your cluster

## Important Licensing and Security Information

The Flux Operator is licensed under **AGPL-3.0**, a free and open-source license. You have full access to the source code and can use it freely. For private internal use, this poses no restriction. If you modify the software or distribute it as part of a service, you would need to release those changes under AGPL as well. For most cluster deployments, this is not a concern. ControlPlane offers a commercial license if AGPL is incompatible with your requirements.

**Authentication:** The Flux Operator web UI ships with **no authentication enabled by default**. This is appropriate for clusters on private networks behind ingress controllers on private clouds. If your dashboard is exposed to the internet or untrusted networks, you should configure authentication or ensure it remains internal only. For this course lab, running without authentication is acceptable in a development environment.

**Metrics:** The dashboard shows CPU and memory usage for your workloads, and that requires the `metrics-server` addon. Most production Kubernetes clusters have it installed. KinD, used in this course's labs, does not include it by default, so instead of usage figures the Resource Usage tab on a resource reads "No usage data available. Workload metrics require the Kubernetes Metrics API." This does not affect the dashboard's core functionality.

## Installation Steps

### 1. Create the HelmRepository

The Flux Operator chart is hosted in an OCI registry. Create a HelmRepository resource that points to it:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: flux-operator
  namespace: flux-system
spec:
  interval: 1h0m0s
  type: oci
  url: oci://ghcr.io/controlplaneio-fluxcd/charts
```

The chart registry is maintained by ControlPlane and is kept in sync with the latest Flux Operator releases.

### 2. Create the HelmRelease

Deploy the Flux Operator web server using a HelmRelease resource:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: flux-web
  namespace: flux-system
spec:
  chart:
    spec:
      chart: flux-operator
      version: 0.60.0
      sourceRef:
        kind: HelmRepository
        name: flux-operator
  interval: 1h0m0s
  values:
    installCRDs: true
    web:
      enabled: true
      serverOnly: true
      ingress:
        enabled: true
        className: nginx
        hosts:
          - host: dashboard.local
            paths:
              - path: /
                pathType: Prefix
```

**Pin the chart version.** `version: 0.60.0` is the release this lesson was recorded against. Without it, Flux installs whatever is newest in the registry, and a later chart may not look or behave like the one in the video.

**`installCRDs: true`** is required whenever you add the web UI to a cluster you bootstrapped with the Flux CLI, as we did: the Flux Operator's own CRDs must exist for the UI to work. It is the chart's default today, but declare it rather than rely on a default.

**Critical setting: `serverOnly: true`** ensures that the Flux Operator deploys ONLY the web server. The operator does not take over managing your Flux installation. Your bootstrap process remains in control. This is why this approach is appropriate for this course.

### 3. Commit and Deploy

Commit both resources to your Git repository:

```bash
git add ./clusters/my-cluster/flux-operator-dashboard.yaml
git commit -m "Install Flux Operator web UI with serverOnly mode"
git push origin main
```

Flux automatically detects and applies the change. You can manually reconcile to speed it up:

```bash
flux reconcile source git flux-system
flux reconcile kustomization flux-system
```

## Accessing the Dashboard

Once the HelmRelease is deployed:

1. Verify the pod is running:
   ```bash
   kubectl get pods -n flux-system | grep flux-web
   ```

2. Verify the ingress was created:
   ```bash
   kubectl get ingress -n flux-system
   ```

3. Make the hostname resolve. `dashboard.local` is not a real DNS name — it only works because you add it to the `hosts` file of the machine running the **browser**, pointing at whatever address reaches your ingress controller:

   - Browser on the same machine as the cluster (a local KinD cluster with port 80 published): `127.0.0.1 dashboard.local`
   - Browser on your laptop, cluster on a remote VM or server: `<that machine's IP address> dashboard.local`

   On macOS or Linux:

   ```bash
   echo "127.0.0.1 dashboard.local" | sudo tee -a /etc/hosts
   ```

4. Navigate to `http://dashboard.local` in your browser.

5. There is no login page. You are on the dashboard immediately. You should see the Flux Status page.

## Dashboard Tour

There is **no left menu**. The UI is a top bar above one long scrolling home page. The top bar holds the **Flux Status** logo (your way back home), a **Search** box, a folder icon tooltipped *Browse Resources*, and a user icon. The browse pages add a tab row of their own under the header: **Favorites · Resources · Workloads · Events**.

### The home page

A column of cards:

- **All Systems Operational** — one green banner for the whole cluster
- **Cluster Info** — Kubernetes version and node count, the Flux Operator version, the Flux distribution version, the platform and the controller-pod count
- **Cluster Sync** — the Kustomization that syncs the cluster, its Git URL, its path and the revision currently applied
- **Flux Components** — every Flux controller (source-controller, kustomize-controller, helm-controller, notification-controller) with its image version and whether it is Ready
- **Flux Resources** — a count tile per Flux CRD, grouped **Appliers**, **Sources**, **Notifications** and **Image Automation**. Each tile links into the resource list filtered to that kind

### Resources

One list of everything Flux manages: HelmReleases, Kustomizations, HelmCharts, and your sources — GitRepositories and HelmRepositories — together rather than on separate pages. Each row shows:
- A kind badge (`HR`, `KS`, `GITREPO`, `HELMREPO`, `HELMCHART`), coloured by status
- `namespace/name`
- The object's own status message
- How long ago it reconciled

Filters across the top: name, namespace, kind and status.

Click a row to open its details. A HelmRelease detail is three cards, each tabbed:
- **Reconciler** — Overview · History · Events · Values · Specification · Status
- **Managed Objects** — Overview · Graph · Inventory · Resource Usage. The inventory is every Kubernetes object that resource created: the Deployment, Service, Ingress, ServiceAccount, NetworkPolicy, RBAC and any CRDs
- **Source** — the HelmRepository or GitRepository it came from

### Workloads

The Deployments running in the cluster and which Flux object manages each. A workload's own detail page opens with a provenance chain across the top — HelmRepository → HelmRelease → Deployment → Pods.

### Events

A log of Flux reconciliation events: successful syncs, errors and failures, and the reconciliations Flux performs on its own schedule.

### Favorites

The resources you have starred to keep at hand — useful on a cluster with more in it than a lab has.

### The manifest view

There is no tab called "YAML". Open a resource and the **Specification** tab on its Reconciler card holds the `spec` as stored in the cluster, with **Status** beside it holding the rest — together, the object `kubectl get -o yaml` would print for you. On a narrow window the tab abbreviates to **Spec**.

### Metrics

CPU and memory usage for deployed workloads requires the `metrics-server` addon. Usage lives on the **Resource Usage** tab of a resource's *Managed Objects* card, not on the Workloads list. In development environments like KinD without metrics-server, that tab reads "No usage data available. Workload metrics require the Kubernetes Metrics API." and can be safely ignored; everything else in the UI works.

### What the UI will not do by default

The web UI is **read-only** out of the box. There are no sync, suspend or resume buttons, because write actions need both an authenticated identity and the `web.userActions` values configured — neither of which this installation has. Use `flux reconcile` and `flux suspend` from the CLI.

## Complete Manifest Example

Here's the complete YAML for installing the Flux Operator web UI:

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: flux-operator
  namespace: flux-system
spec:
  interval: 1h0m0s
  type: oci
  url: oci://ghcr.io/controlplaneio-fluxcd/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: flux-web
  namespace: flux-system
spec:
  chart:
    spec:
      chart: flux-operator
      version: 0.60.0
      sourceRef:
        kind: HelmRepository
        name: flux-operator
  interval: 1h0m0s
  values:
    installCRDs: true
    web:
      enabled: true
      serverOnly: true
      ingress:
        enabled: true
        className: nginx
        hosts:
          - host: dashboard.local
            paths:
              - path: /
                pathType: Prefix
```

## Important Notes

- **Flux Operator is officially maintained**: It's developed in collaboration with the Flux project maintainers by ControlPlane.
- **Web UI is declarative**: Like any other Helm release, the dashboard is managed by Flux through a GitOps workflow. You commit YAML to Git, and Flux deploys it.
- **CLI equivalence**: Everything you can see in the Flux Operator dashboard is also available through `kubectl` and `flux` CLI commands. The dashboard is a convenience, not a requirement.
- **The dashboard is another workload**: Like any other application in your cluster, the dashboard itself is managed by Flux. You can suspend, update, or remove it just like any other HelmRelease.
- **No authentication by default**: Unlike Weave GitOps (which is now in maintenance mode), this one ships without login by default, which is appropriate for private networks and acceptable for lab environments. Authentication is added through SSO — the operator documents OIDC providers such as Dex, Keycloak and Entra ID.
- **Which UI is "the" UI**: the Flux project lists several UIs in its ecosystem page and does not crown one. The Flux Operator is the one built by ControlPlane, the company the Flux maintainers work at, and it is the one this course uses.

## Troubleshooting

**HelmRelease not ready:**
Check the HelmRelease status with:
```bash
kubectl describe helmrelease flux-web -n flux-system
```

**Can't access the dashboard:**
First check that `dashboard.local` resolves on the machine running the browser (`grep dashboard.local /etc/hosts`), then that the ingress controller is running:
```bash
kubectl get pods -n ingress-nginx
```

Alternatively, skip the hostname and the ingress entirely with a port-forward:
```bash
kubectl port-forward -n flux-system svc/flux-web-flux-operator 8080:9080
```
Then open `http://localhost:8080`. The web UI listens on Service port **9080**; port 8080 on that same Service is the metrics endpoint, and there is no port 80 — `8080:80` fails with `Service flux-web-flux-operator does not have a service port 80`.

**Resource Usage tab is empty:**
Ensure metrics-server is installed:
```bash
kubectl get deployment metrics-server -n kube-system
```

If it's not installed and you need metrics, install it. For development, this is optional.

## Further Reading

- [Flux CD official documentation](https://fluxcd.io/flux/)
- [Flux Operator on GitHub](https://github.com/controlplaneio-fluxcd/flux-operator)
- [Flux API references](https://fluxcd.io/flux/components/helm/api/)
- [Helm integration with Flux](https://fluxcd.io/flux/use-cases/helm/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
