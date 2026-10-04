---
title: "Secrets encryption with Bitnami's Sealed Secrets"
kicker: "FLUX CD · SECTION 5 · LECTURE 2"
description: "How to securely manage Kubernetes secrets in a Git repository using Bitnami's Sealed Secrets, which encrypts your secret data so it can be safely committed to version control while keeping to GitOps principles."
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Secrets encryption with Bitnami's Sealed Secrets

*Section 5, Lecture 2, from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Explain how Sealed Secrets' public/private key model keeps encrypted Secrets safe to commit to Git
- Install the `kubeseal` CLI and deploy the Sealed Secrets controller into a Flux-managed cluster
- Encrypt a Kubernetes Secret with `kubeseal` and commit the result through a GitOps workflow
- Verify that the controller decrypted a SealedSecret and troubleshoot common failures
- Apply best practices for backing up and rotating Sealed Secrets encryption keys

## Overview

This lecture covers how to securely manage Kubernetes secrets in a Git repository using Bitnami's Sealed Secrets. Sealed Secrets encrypts your secret data so it can be safely committed to version control while maintaining GitOps principles.

## Prerequisites

- A running Kubernetes cluster (or KinD clusters for local development)
- kubectl configured with cluster access
- Flux CD v2.9.4 or later installed
- Git repository configured for Flux CD

## Installation

### Install the kubeseal CLI

On Linux, install the binary from the project's release page:

```bash
curl -L -o /tmp/kubeseal.tar.gz https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.39.1/kubeseal-0.39.1-linux-amd64.tar.gz
tar -xzf /tmp/kubeseal.tar.gz -C /tmp kubeseal
sudo install -m 755 /tmp/kubeseal /usr/local/bin/kubeseal
kubeseal --version
```

On macOS, `brew install kubeseal` installs the same tool. Every release is listed at
https://github.com/bitnami-labs/sealed-secrets/releases. Pick the archive that matches
your operating system and CPU architecture.

### Install the Sealed Secrets Controller

The Sealed Secrets controller is deployed using a manifest from the official GitHub releases:

```bash
curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.39.1/controller.yaml -o sealed-secrets-manifest.yaml
```

Add this to your `infrastructure/controllers/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: flux-system
resources:
  - sealed-secrets-manifest.yaml
```

The `namespace: flux-system` line matters. The upstream release manifest declares
`namespace: kube-system` for every resource it contains; this line is a Kustomize
namespace transformer, and it rewrites them all to `flux-system` before Flux applies
them. That is why the controller pod, and every `kubeseal` and `kubectl` command in
this handout, looks in `flux-system` rather than in `kube-system`.

Commit and reconcile with Flux CD:

```bash
git add .
git commit -m "Add Sealed Secrets controller"
git push origin main

kubectl config use-context kind-staging
flux reconcile kustomization infrastructure-controllers --with-source
kubectl get pods -n flux-system | grep sealed
```

Sealed Secrets is a standard infrastructure component, so apply it on the production cluster too:

```bash
kubectl config use-context kind-production
flux reconcile kustomization infrastructure-controllers --with-source
kubectl get pods -n flux-system | grep sealed
```

## How Sealed Secrets Works

### The Public/Private Key Model

Sealed Secrets uses asymmetric encryption:

- **Public Key**: Used to encrypt secrets. Can be freely shared with team members.
- **Private Key**: Used to decrypt secrets. Stays inside the cluster in the Sealed Secrets controller.

### Workflow

1. Extract the public key from the cluster
2. Encrypt your secret locally using the public key (with kubeseal)
3. Commit the encrypted secret to Git
4. Flux CD applies the encrypted secret to the cluster
5. The Sealed Secrets controller detects it and decrypts it using the private key
6. A regular Kubernetes Secret is created for your application to use

## Common Tasks

### Extract the Public Keys

Sealed Secrets is installed on every cluster, and each cluster's controller generates its own key pair. Fetch the public key from each cluster and keep both in the repository so every team member can encrypt with them.

Store them in a `sealed-secrets-keys` directory at the repository root, next to `clusters` and `infrastructure` and outside both. It sits outside the paths Flux reads and applies because the files are PEM-encoded keys, not YAML manifests: if Flux tried to apply them to the cluster, the reconcile would fail.

```bash
mkdir -p sealed-secrets-keys
cd sealed-secrets-keys

kubectl config use-context kind-staging
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=flux-system \
  > staging.pem

kubectl config use-context kind-production
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=flux-system \
  > production.pem

ls -la *.pem
```

You now have two different public keys, `staging.pem` and `production.pem`. A SealedSecret can only be unsealed by the controller whose public key sealed it, so seal with the key of the cluster you are targeting.

### Create and Encrypt a Secret

Switch back to staging and recreate the `gitlab-auth` Secret from the earlier tenant-onboarding lecture as a YAML file. Everything in angle brackets is yours to replace: the repository in the lecture is the instructor's, not one you can pull from:

```bash
kubectl config use-context kind-staging

flux create secret git gitlab-auth \
  --url=https://gitlab.com/<your-gitlab-username>/<your-repo>.git \
  --username=<your-gitlab-username> \
  --password=<your-gitlab-token> \
  -n apps \
  --export > secret.yaml
```

Open `secret.yaml` and look before you go further: `flux` writes the credentials under
`stringData:` as raw, readable text (not even base64). This file must never be
committed.

Encrypt the secret with the staging cluster's public key:

```bash
kubeseal --format=yaml --cert=staging.pem < secret.yaml > gitlab-auth-sealed.yaml
cat gitlab-auth-sealed.yaml
```

The result is a `SealedSecret` whose `spec.encryptedData` holds long encrypted blobs. Nothing in it traces back to your credentials.

### Apply Encrypted Secrets via GitOps

Append the SealedSecret to the dev team's sync file, `tenants/base/dev/sync.yaml`. It already holds several YAML documents, so add the `---` document separator first:

```bash
echo '---' >> ../tenants/base/dev/sync.yaml
cat gitlab-auth-sealed.yaml >> ../tenants/base/dev/sync.yaml
```

Before you commit, delete the existing `gitlab-auth` Secret by hand. It was created directly with `kubectl` before Sealed Secrets was in place, and the controller will not take over a Secret it did not create:

```bash
kubectl get secrets -n apps
kubectl delete secret gitlab-auth -n apps
kubectl get secrets -n apps | grep gitlab
```

The last command prints nothing for `gitlab-auth`: the Secret is gone.

Now commit the sync file and the two public keys. Add the `.pem` files by name. Never run `git add sealed-secrets-keys/` on the whole directory: it also holds `secret.yaml`, the plain-text secret, and committing that is exactly the mistake Sealed Secrets exists to prevent.

```bash
cd ..
git add tenants/base/dev/sync.yaml sealed-secrets-keys/staging.pem sealed-secrets-keys/production.pem
git commit -m "Add encrypted gitlab-auth secret for dev team"
git push origin main
```

Reconcile so Flux pulls and applies the change immediately:

```bash
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization tenants
```

After a few seconds the `gitlab-auth` Secret is back. This time the Sealed Secrets controller created it from the SealedSecret stored in Git.

### Verify Decryption

Check that the secret was created and decrypted:

```bash
kubectl get secrets -n apps
kubectl get secret gitlab-auth -n apps -o yaml
```

## Advanced Topics

For environments where multiple teams share a cluster, the Sealed Secrets project documentation provides guidance on configuring namespace-scoped controllers so each team can have isolated encryption keys. Visit the [official Sealed Secrets repository](https://github.com/bitnami-labs/sealed-secrets) for detailed instructions on advanced multi-tenant setups.

## Troubleshooting

### "cannot get sealed secret service" Error

`kubeseal` looks in `kube-system` unless you tell it otherwise. Name the controller and
its namespace on every call, and check the controller is running where you expect:

```bash
kubectl get pods -n flux-system | grep sealed
kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=flux-system
```

### Secret Not Being Decrypted

Check that the SealedSecret landed in the same namespace the secret was sealed for, then
read the controller's log. The controller's pods carry the label
`name=sealed-secrets-controller`:

```bash
kubectl get sealedsecret -n apps
kubectl logs -n flux-system -l name=sealed-secrets-controller | tail -20
```

A successful unseal appears in the log as `SealedSecret unsealed successfully`.

### Controller Failing to Start

Check the deployment and that the CRD was installed with it:

```bash
kubectl describe deployment sealed-secrets-controller -n flux-system
kubectl get crd | grep sealed
```

## Best Practices

- **Backup encryption keys regularly**: The private key cannot be recovered if lost. Regular backups to a secure location are essential.
- **Rotate keys periodically**: Plan for key rotation and have a process to re-encrypt secrets.
- **Never commit unencrypted secrets**: Always use kubeseal before committing secrets to Git.
- **Limit access to keys**: Restrict who can access the public/private key files.
- **Store public keys in your repository**: Share the public key with your team so they can encrypt secrets locally.

## Further Reading

- [Sealed Secrets Project on GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [Sealed Secrets releases (kubeseal binaries and controller manifests)](https://github.com/bitnami-labs/sealed-secrets/releases)
- [Flux CD Kustomization Documentation](https://fluxcd.io/flux/components/kustomize/kustomization/)
- [Kubernetes Secret Management Best Practices](https://kubernetes.io/docs/concepts/configuration/secret/)

## Summary

Sealed Secrets provides a practical and secure way to manage Kubernetes secrets within a GitOps workflow. By encrypting secrets with a public key and storing them in Git, you maintain the principles of version control and GitOps while keeping sensitive data protected. The private key remains in your cluster and is never exposed, ensuring that only the intended cluster can decrypt the secrets.

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses: Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
