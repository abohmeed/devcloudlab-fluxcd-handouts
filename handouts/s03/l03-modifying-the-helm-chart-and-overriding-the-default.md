---
title: "Modifying the Helm chart and overriding the default values"
kicker: "FLUX CD · SECTION 3 · LECTURE 3"
description: "This lecture demonstrates how to override Helm chart default values using Flux CD's HelmRelease custom resource. You'll create a ConfigMap template in your Helm chart to"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Modifying the Helm chart and overriding the default values

*Section 3, Lecture 3 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Override a Helm chart's default values from a HelmRelease's inline `spec.values` block
- Add a ConfigMap template to a chart and mount it into a Deployment to serve custom content
- Choose between inline values and `spec.chart.spec.valuesFiles`, and where each resolves its paths from
- Bump a chart's version to signal Flux CD that a chart change needs deploying
- Diagnose common failures — stale CRDs, missing ConfigMap mounts, and an Ingress left disabled from an earlier lecture

## Overview

This lecture demonstrates how to override Helm chart default values using Flux CD's HelmRelease custom resource. You'll create a ConfigMap template in your Helm chart to supply a custom HTML welcome page for Nginx, and then inject that custom value through the HelmRelease manifest. This workflow shows the GitOps approach to managing Helm deployments: chart templates and value overrides are version-controlled, and Flux CD continuously reconciles the desired state in Git with the actual state in the cluster.

## Key Concepts

**Helm Values:** Every Helm chart defines default values for its templates. Values are injected into template placeholders (using the `{{ .Values.<key> }}` syntax) to generate Kubernetes manifests. You can override these defaults at deployment time.

**ConfigMap for Configuration:** A ConfigMap is a Kubernetes object that stores non-sensitive configuration data as key-value pairs. In this example, we create a ConfigMap containing custom HTML content that Nginx will serve.

**HelmRelease Custom Resource:** Flux CD's HelmRelease resource defines how and when to deploy a Helm chart. It allows you to specify value overrides inline (using `spec.values`) or from separate files (using `spec.chart.spec.valuesFiles`).

**Inline vs File-Based Values:** The `spec.values` field (at the top level of `spec`) lets you define values directly in the manifest. If you prefer to manage values in separate YAML files, use `spec.chart.spec.valuesFiles`, which accepts a list of file paths relative to the **root of the Git repository the chart comes from** — not to the chart directory. Later files in the list override earlier ones. Both approaches achieve the same result—providing custom values to the chart.

## Commands Used

**Create and switch branches:**
```bash
git checkout main          # Switch to the main branch
git pull                   # Pull the latest changes from remote
git checkout -b "custom-welcome-page"  # Create and switch to a new branch
```

**Stage, commit, and push changes:**
```bash
git add -A                 # Stage all modified and new files
git commit -m "message"    # Create a commit with a descriptive message
git push --set-upstream origin custom-welcome-page  # Push the branch and set upstream tracking
```

**Reconcile Flux resources to immediately apply changes:**
```bash
flux reconcile kustomization flux-system --with-source  # Sync the Kustomization and fetch new chart versions
flux reconcile helmrelease nginx -n default             # Apply the latest HelmRelease configuration to the cluster
```

**Verify resources in the cluster:**
```bash
kubectl get configmap -n default              # List all ConfigMaps in the default namespace
kubectl describe pod -n default                # Show detailed info about pods
kubectl logs -n default <pod-name>             # View logs from a specific pod
```

## Complete Manifest Files

### ConfigMap Template (charts/nginx/templates/configmap.yaml)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-index-html
data:
  index.html: |
    {{ .Values.indexHtml | nindent 4 }}
```

**Explanation:**
- The ConfigMap is named using `{{ .Release.Name }}-index-html` to ensure uniqueness when multiple releases exist.
- The `index.html` key contains the HTML content, pulled from `{{ .Values.indexHtml }}` defined in the HelmRelease.
- The `nindent 4` filter indents the HTML content correctly for valid YAML formatting.

### Updated Deployment Template (charts/nginx/templates/deployment.yaml)

The chart that `helm create` scaffolds wraps every optional block in `{{- with .Values.X }}`, and it already ships `volumeMounts` and `volumes` blocks driven from values. Because the ConfigMap we mount is named after the release, a values file cannot supply it — so we replace those two blocks with literal ones. Only the pod spec is shown; everything else in the deployment stays as scaffolded, including the probes and the `resources` block:

```yaml
    spec:
      containers:
        - name: {{ .Chart.Name }}
          {{- with .Values.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.port }}
              protocol: TCP
          {{- with .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          # replaces the scaffold's {{- with .Values.volumeMounts }} block
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
      # replaces the scaffold's {{- with .Values.volumes }} block
      volumes:
        - name: html
          configMap:
            name: {{ .Release.Name }}-index-html
```

**Explanation:**
- `volumeMounts` tells the container to mount the ConfigMap data at `/usr/share/nginx/html`.
- `volumes` defines the source: a ConfigMap named by the release (e.g., `nginx-index-html`).
- Nginx will serve files from this directory, so our custom `index.html` will replace the default welcome page.

### Chart Version (charts/nginx/Chart.yaml)

```yaml
apiVersion: v2
name: nginx
description: A Helm chart for Kubernetes
type: application
version: 0.2.0
appVersion: "1.16.0"
```

**Explanation:**
- The chart version increments from `0.1.0` (what `helm create` scaffolds) to `0.2.0` — a **minor bump**, the middle digit. This signals to Flux CD that the chart has changed and should be redeployed.
- Helm uses semantic versioning: `MAJOR.MINOR.PATCH`.
- `appVersion` describes the application packaged by the chart, not the chart itself, so it is left unchanged.

### HelmRelease (clusters/my-cluster/nginx-helm-release.yaml)

The HelmRelease must live under the path Flux was bootstrapped against — here `clusters/my-cluster/`. A HelmRelease placed outside that path is never reconciled. This lecture adds one key, `indexHtml`, to the `values:` block the previous lecture created:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx
  namespace: default
spec:
  interval: 10m
  chart:
    spec:
      chart: ./charts/nginx
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  values:
    replicaCount: 1
    image:
      repository: nginx
      tag: latest
    service:
      type: ClusterIP
      port: 80
    indexHtml: |-
      <!doctype html>
        <html>
        <head>
          <title>My Custom Page</title>
        </head>
        <body>
          <h1>Welcome to my custom Nginx page!</h1>
        </body>
        </html>
```

**Explanation:**
- `apiVersion: helm.toolkit.fluxcd.io/v2` specifies the HelmRelease API version used by Flux CD.
- `spec.interval: 10m` tells Flux how often to re-evaluate this HelmRelease on its own.
- `spec.chart.spec.sourceRef` points to the GitRepository containing the chart.
- `spec.values` provides inline value overrides. The key `indexHtml` matches the value used in the ConfigMap template.
- The `|-` symbol denotes a literal block scalar in YAML—whitespace and newlines are preserved, making it ideal for HTML.

### Alternative: Using valuesFiles

If you prefer to store values separately, you can use `spec.chart.spec.valuesFiles` instead. Put `values-custom.yaml` at the **root** of your repository — that is where Flux will look for it:

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
      valuesFiles:
        - values-custom.yaml
```

**Explanation:**
- `spec.chart.spec.valuesFiles` takes a list of paths to YAML files. These paths are relative to the **root of the Git repository** the chart is read from, not to the chart directory — so listing `values.yaml` here would look for `values.yaml` at the repository root, not `charts/nginx/values.yaml`, and the HelmChart would fail to build.
- The chart's own `values.yaml` is always loaded as the base; you do not list it.
- Flux merges values from multiple files, with later files overriding earlier ones.
- This approach is useful when managing many environment-specific value overrides.

## Step-by-Step Workflow

1. **Prepare the repository:** Check out main, pull latest, and create a feature branch.
2. **Add the ConfigMap template:** Create `charts/nginx/templates/configmap.yaml` to hold custom HTML.
3. **Update the Deployment:** Replace the scaffold's value-driven `volumeMounts` and `volumes` blocks in `deployment.yaml` with literal ones that mount the ConfigMap.
4. **Bump the chart version:** Increment the version in `Chart.yaml` — `0.1.0` to `0.2.0` — to trigger reconciliation.
5. **Define values in HelmRelease:** Add `indexHtml` under `spec.values` to supply the HTML content from a single source of truth.
6. **Commit and merge:** Push the branch, create a merge request, and merge to main.
7. **Reconcile:** Run `flux reconcile` commands to apply changes immediately.
8. **Verify:** Refresh the Nginx welcome page in your browser to see the custom content.

## Common Issues and Solutions

**Error: "no matches for kind 'HelmRelease' in version 'helm.toolkit.fluxcd.io/v2beta1'"**
This occurs when your cluster has old Flux CRDs. Upgrade Flux with:
```bash
flux install --export | kubectl apply -f -
```

**ConfigMap not mounted in the pod:**
Verify the ConfigMap exists and is named correctly:
```bash
kubectl get configmap -n default
kubectl describe configmap nginx-index-html -n default
```
Check that the `volumeMounts` indentation is correct in the deployment template.

**Nginx pod stuck in CrashLoopBackOff:**
Inspect pod logs:
```bash
kubectl logs -n default -l app.kubernetes.io/name=nginx
```
Ensure the mount path `/usr/share/nginx/html` is correct and the HTML in the ConfigMap is valid.

**Changes not appearing after reconcile:**
Ensure the branch is merged to main and run reconcile with `--with-source` to pull the latest from Git:
```bash
flux reconcile kustomization flux-system --with-source
flux reconcile helmrelease nginx -n default
```

**The browser shows a 404 page with `nginx` in the footer:**
That is the ingress controller's default backend, which means no Ingress is routing to your release. The previous lecture enabled Ingress in the chart's own `values.yaml`; check it is still there:
```bash
kubectl get ingress -n default
grep -A 6 "^ingress:" charts/nginx/values.yaml
```
`ingress.enabled` must be `true` and `ingress.className` must match your controller (`nginx` for ingress-nginx). The ConfigMap change is unaffected by this — you can confirm the release itself is correct from inside the cluster:
```bash
kubectl run curltest --rm -it --restart=Never --image=curlimages/curl -- \
  curl -s http://nginx.default.svc.cluster.local/
```

## Further Reading

- [Flux HelmRelease documentation](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Helm Values Files documentation](https://helm.sh/docs/chart_template_guide/values_files/)
- [Helm Chart.yaml specification](https://helm.sh/docs/topics/charts/#the-chartyaml-file)
- [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Flux reconcile command reference](https://fluxcd.io/flux/cmd/flux_reconcile/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
