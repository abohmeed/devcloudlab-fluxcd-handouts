---
title: "(Optional) Creating a private Helm repository"
kicker: "FLUX CD · SECTION 3 · LECTURE 4"
description: "This lecture covers how to set up ChartMuseum, an open-source Helm chart repository server, to create a private repository that requires authentication. You will deploy"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# (Optional) Creating a private Helm repository

*Section 3, Lecture 4 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Stand up ChartMuseum as a self-hosted, authenticated Helm chart repository using Docker
- Package a Helm chart with `helm package` and push it to a private repository over HTTP basic auth
- Add an authenticated repository to Helm and search it for a pushed chart
- Troubleshoot common ChartMuseum failures — permission-denied pushes, missing storage flags, and connection errors
- Tear down the ChartMuseum container and volume when finished

## Overview

This lecture covers how to set up ChartMuseum, an open-source Helm chart repository server, to create a private repository that requires authentication. You will deploy ChartMuseum using Docker, create a test Helm chart, package it, and push it to the repository.

## What is ChartMuseum?

ChartMuseum is a lightweight, self-hosted Helm chart repository server maintained by the Helm community. It allows you to:
- Host private Helm charts
- Require authentication for access
- Use various storage backends
- Manage chart versions

## Prerequisites

- Docker installed and running
- Helm CLI installed (version 3.0 or later)
- Familiarity with Helm charts

## Setting Up ChartMuseum

### Create a Docker volume for chart storage

```bash
docker volume create my-chartmuseum-storage
```

This volume persists your charts even if the container is stopped or removed.

### Run the ChartMuseum container

```bash
docker run -d \
  --name my-helm-repo \
  -p 8080:8080 \
  -v my-chartmuseum-storage:/charts \
  -u 0 \
  -e STORAGE=local \
  -e STORAGE_LOCAL_ROOTDIR=/charts \
  -e ALLOW_OVERWRITE=true \
  -e BASIC_AUTH_USER=chartuser \
  -e BASIC_AUTH_PASS=mypass \
  ghcr.io/helm/chartmuseum:v0.16.6
```

The image comes from the project's own GitHub Container Registry. The older
`chartmuseum/chartmuseum` repository on Docker Hub was last pushed in January 2021 and
still ships ChartMuseum 0.12.0, so do not use it.

This command runs ChartMuseum in the background. The key flags are:
- `-u 0`: run the server as root. Docker creates a brand-new named volume's mount point owned by `root`, and the ChartMuseum image has no `/charts` directory whose ownership it could copy — while the server itself runs as an unprivileged user. Without this flag the chart push below fails with `{"error":"open /charts/busybox-0.1.0.tgz: permission denied"}` and HTTP 500
- `ALLOW_OVERWRITE`: allow replacing existing chart versions (useful for development)
- `STORAGE` / `STORAGE_LOCAL_ROOTDIR`: REQUIRED — where charts are stored. Without them the container exits with `Missing required flags(s): --storage`
- `BASIC_AUTH_USER` / `BASIC_AUTH_PASS`: enable basic authentication with the credentials `chartuser` / `mypass`. Unauthenticated requests then get a `401`

## Creating and Pushing a Test Chart

### Create a Helm chart scaffold

```bash
helm create busybox
cd busybox
```

### Modify the deployment template

Edit `templates/deployment.yaml`. In the `spec.template.spec.containers` section, replace the container definition with:

```yaml
      containers:
        - name: {{ .Chart.Name }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command:
            - sleep
            - infinity
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

This changes the image from Nginx to BusyBox and adds a sleep command to keep the container running indefinitely.

### Update values.yaml

Edit `values.yaml` and replace the image section with:

```yaml
image:
  repository: busybox
  pullPolicy: IfNotPresent
  tag: "latest"
```

### Package the chart

```bash
helm package .
```

This creates `busybox-0.1.0.tgz`, a compressed archive of the chart.

### Push the chart to ChartMuseum

```bash
curl -u chartuser --data-binary "@busybox-0.1.0.tgz" http://localhost:8080/api/charts
```

When prompted, enter the password: `mypass`. The response confirms the chart was saved to the repository.

## Verifying Your Repository

### Add the repository to Helm

```bash
helm repo add my-helm-repo --username chartuser http://localhost:8080
```

When prompted, enter the password: `mypass`.

### Search for your chart

```bash
helm search repo busybox
```

Output shows the chart is available in the repository:

```text
NAME                  CHART VERSION  APP VERSION  DESCRIPTION
my-helm-repo/busybox  0.1.0          1.16.0       A Helm chart for Kubernetes
```

The APP VERSION comes from the `appVersion` field that `helm create` wrote into
`Chart.yaml` — we never changed it. A different Helm version may scaffold a different
default there, so do not be surprised if your number differs.

### Install the chart (example, Helm only)

To install the chart directly with Helm (not using Flux CD):

```bash
helm install mybusybox my-helm-repo/busybox
```

In the next lecture, you will use Flux CD to deploy this chart instead.

## Complete command reference

### Docker: Run ChartMuseum with basic authentication

```bash
docker run -d \
  --name my-helm-repo \
  -p 8080:8080 \
  -v my-chartmuseum-storage:/charts \
  -u 0 \
  -e STORAGE=local \
  -e STORAGE_LOCAL_ROOTDIR=/charts \
  -e ALLOW_OVERWRITE=true \
  -e BASIC_AUTH_USER=chartuser \
  -e BASIC_AUTH_PASS=mypass \
  ghcr.io/helm/chartmuseum:v0.16.6
```

### Helm: Create and package a chart

```bash
helm create busybox
cd busybox
helm package .
```

### Helm: Add an authenticated repository

```bash
helm repo add my-helm-repo --username chartuser http://localhost:8080
```

When prompted, enter: `mypass`

### Helm: Search and display available charts

```bash
helm search repo busybox
```

### Curl: Push a chart package to ChartMuseum

```bash
curl -u chartuser --data-binary "@busybox-0.1.0.tgz" http://localhost:8080/api/charts
```

Password: `mypass`

## Full manifest examples

### templates/deployment.yaml (container section)

```yaml
      containers:
        - name: {{ .Chart.Name }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command:
            - sleep
            - infinity
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

### values.yaml (image section)

```yaml
image:
  repository: busybox
  pullPolicy: IfNotPresent
  tag: "latest"
```

## Troubleshooting

**ChartMuseum image fails to pull**

Verify the official image is available:
```bash
docker pull ghcr.io/helm/chartmuseum:v0.16.6
```

The ChartMuseum project publishes its images on the GitHub Container Registry and no
longer updates the old `chartmuseum/chartmuseum` repository on Docker Hub. The GHCR
image needs no login to pull.

**Chart push fails with `permission denied` and HTTP 500**

```text
{"error":"open /charts/busybox-0.1.0.tgz: permission denied"}
```

The `-u 0` flag is missing from `docker run`. Remove the container and start it again
with the flag in place — the volume can stay:

```bash
docker rm -f my-helm-repo
```

**Chart push fails with connection refused**

Verify the container is running:
```bash
docker ps | grep my-helm-repo
```

Check the container logs:
```bash
docker logs my-helm-repo
```

**Authentication fails when adding the repository**

Verify credentials:
- Username: `chartuser`
- Password: `mypass`

These must match the environment variables `BASIC_AUTH_USER` and `BASIC_AUTH_PASS`.

**helm search repo returns no results**

Refresh the local repository index:
```bash
helm repo update
```

## Cleaning up

To remove ChartMuseum and reset your environment:

```bash
docker stop my-helm-repo
docker rm my-helm-repo
docker volume rm my-chartmuseum-storage
rm -rf ~/busybox
rm -f ~/busybox-0.1.0.tgz
helm repo remove my-helm-repo
```

## Further reading

- ChartMuseum on GitHub: https://github.com/helm/chartmuseum
- Helm chart repository documentation: https://helm.sh/docs/topics/chart_repository/
- Helm commands reference: https://helm.sh/docs/helm/
- Flux CD Helm integration: https://fluxcd.io/docs/components/helm/

## Next steps

With your private ChartMuseum repository running, you are ready to integrate it with Flux CD. In the next lecture, you will configure a HelmRepository resource to tell Flux CD about your private repository, and use a HelmRelease to deploy charts from it.

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
