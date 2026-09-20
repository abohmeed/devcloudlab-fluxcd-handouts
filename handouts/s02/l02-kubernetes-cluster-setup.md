---
title: "Kubernetes cluster setup"
kicker: "FLUX CD · SECTION 2 · LECTURE 2"
description: "How to prepare a local Kubernetes cluster with kind, Docker, kubectl, and an NGINX ingress controller for this course's hands-on labs"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Kubernetes cluster setup

*Section 2, Lecture 2 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- The trade-off between a managed Kubernetes service and a local cluster
- How to install Docker, kubectl, and kind on Ubuntu
- How to create a local **kind** cluster configured for HTTP/HTTPS ingress
- How to install and verify an NGINX ingress controller on that cluster

## Two ways to get a cluster

| Approach | Examples | Best for |
|---|---|---|
| Managed Kubernetes service | Amazon EKS, Google GKE, Azure AKS, DigitalOcean Kubernetes | Production-like environments — the provider runs and upgrades the control plane |
| Local cluster | **kind** (Kubernetes in Docker) | Fast, disposable clusters for development and for the labs in this course |

A managed service removes the operational burden of running Kubernetes yourself, but it costs money and takes longer to spin up. For the labs in this course, a local **kind** cluster is faster to create and destroy, and it's free.

## Installing Docker (Ubuntu)

kind runs each cluster node as a Docker container, so Docker has to be installed first. If Docker is already running on your machine, skip to [Installing kubectl](#installing-kubectl).

Install the prerequisite packages:

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
```

Add Docker's GPG key to a keyring, then register the repository:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

> **Since this video was recorded:** `apt-key add` and the `add-apt-repository` shorthand for third-party repositories were removed in Ubuntu 22.04+. The steps above are the current equivalent — the key is saved to `/etc/apt/keyrings/` and referenced with `signed-by` in the repository line; the video shows the older `apt-key`/`add-apt-repository` form.

Install Docker itself:

```bash
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
```

Let your user run `docker` without `sudo`, then confirm it works:

```bash
sudo usermod -aG docker ${USER}
newgrp docker
docker version
```

On Windows or macOS, install [Docker Desktop](https://www.docker.com/products/docker-desktop/) instead — it bundles the Docker engine and doesn't need the steps above.

## Installing kubectl

`kubectl` is the command-line client you use to talk to any Kubernetes cluster, local or remote.

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

The `curl -L -s https://dl.k8s.io/release/stable.txt` part resolves to the current stable Kubernetes release, so this always downloads a current `kubectl` build.

## Installing kind

```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
kind version
```

> **Note:** check the [kind releases page](https://github.com/kubernetes-sigs/kind/releases) for the current version number before running the first command — `v0.33.0` was current at the time of writing, and kind ships new releases regularly.

## Creating a cluster with ingress enabled

A plain `kind create cluster` gives you a working cluster with default settings. This course also needs ingress, which requires a config file so kind labels a node as ingress-ready and maps ports 80 and 443 from the container to your host.

Save this as `cluster.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
        kubeletExtraArgs:
          node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
```

Then create the cluster from it:

```bash
kind create cluster --config=cluster.yaml
```

kind automatically points `kubectl` at the new cluster, so you can use `kubectl` right away without any extra configuration.

## Installing the ingress controller

With the cluster running, install the NGINX ingress controller build that kind publishes for its own clusters:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

Wait for the controller pod to become ready before deploying anything that depends on it:

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

Once that command returns, the cluster can route `Ingress` objects to your services.

## Using a managed cluster instead

If you'd rather skip local cluster management and use Amazon EKS, Google GKE, Azure AKS, or DigitalOcean Kubernetes, kind isn't involved at all. Every provider has its own command to point `kubectl` at the cluster it created for you — for example, EKS uses `aws eks update-kubeconfig`. Follow your provider's documentation for that one step; everything else in this course works the same way once `kubectl` is pointed at a working cluster.

## Further reading

- [Docker Engine install guide for Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Install kubectl on Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
- [kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [kind: Ingress](https://kind.sigs.k8s.io/docs/user/ingress/)
- [Kubernetes Ingress concepts](https://kubernetes.io/docs/concepts/services-networking/ingress/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
