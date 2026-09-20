---
title: "Secrets encryption with HashiCorp Vault (and OpenBao)"
kicker: "FLUX CD · SECTION 5 · LECTURE 6"
description: "This lecture demonstrates how to securely encrypt Kubernetes secrets in a Git repository using HashiCorp Vault's Transit Secret Engine as an encryption backend for Mozilla"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Secrets encryption with HashiCorp Vault (and OpenBao)

*Section 5, Lecture 6 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Explain how Vault's Transit Secret Engine provides encryption as a service for SOPS without exposing key material
- Compare HashiCorp Vault's BUSL license against OpenBao's MPL-2.0, API-compatible alternative
- Configure a Vault address that Flux can reach from inside the cluster, not just from your own shell
- Encrypt a Kubernetes Secret with `sops --hc-vault-transit` and commit it safely to Git
- Configure a Flux Kustomization's `decryption.secretRef` so it decrypts Vault-encrypted Secrets automatically

## Overview

This lecture demonstrates how to securely encrypt Kubernetes secrets in a Git repository using HashiCorp Vault's Transit Secret Engine as an encryption backend for Mozilla SOPS. We also covered the licensing aspects of both Vault and its open-source alternative, OpenBao.

### Key Concepts

**Secret Engines**: Components in Vault that handle specific kinds of secrets or provide secret management capabilities. Examples include AWS, database, SSH, and Transit engines.

**Transit Secret Engine**: Provides Encryption as a Service, allowing cryptographic operations without exposing sensitive key material. Ideal for encrypting data without storing encryption keys locally.

**SOPS (Secrets Operations)**: A tool that acts as an adapter between different encryption backends (Vault, GPG, Age, etc.) while allowing you to specify which fields in a file should be encrypted.

**Vault Token**: A credential that grants access to Vault and its secrets. Treat it as a sensitive credential equivalent to a password or API key.

### Licensing Considerations

HashiCorp Vault transitioned to the Business Source License (BUSL) in August 2023. This means:

- **For internal use**: Unrestricted. Teams using Vault internally on AWS, Kubernetes, or for their own infrastructure have no licensing concerns.
- **For embedded use**: If you embed Vault into a competing commercial product, you need a commercial license from HashiCorp.
- **Open-source alternative**: OpenBao is an MPL-2.0 licensed fork maintained by the Linux Foundation. It is API-compatible with pre-BUSL Vault, so the integration steps with Flux CD and SOPS work identically.

Choose based on your organization's licensing requirements and open-source policies.

---

## Step-by-Step Instructions

### Start Vault

Generate a root token straight into an environment variable, so it never appears on your screen or in your shell history:

```bash
export VAULT_TOKEN=$(openssl rand -base64 24 | tr -d '=' | head -c 32)
```

Run Vault in a Docker container to avoid installing it in your cluster:

```bash
docker run --cap-add=IPC_LOCK -d -e VAULT_DEV_ROOT_TOKEN_ID="$VAULT_TOKEN" -p 8200:8200 hashicorp/vault:latest
```

- `--cap-add=IPC_LOCK`: Allows the container to lock memory for sensitive data, preventing it from being swapped to disk.
- `-e VAULT_DEV_ROOT_TOKEN_ID`: Sets the root token for authentication. Never hard-code a token into a command you save, share or commit.
- `-p 8200:8200`: Publishes Vault's API on port 8200 of the host.

### Configure the Vault address — the one detail that catches everybody

SOPS writes the Vault address it encrypted with **into the encrypted file**. Later it is Flux, running inside your cluster, that reads that address back and calls Vault to decrypt. Inside a pod, `127.0.0.1` is the pod itself — so a Secret encrypted against `http://127.0.0.1:8200` fails every reconcile with `dial tcp 127.0.0.1:8200: connect: connection refused`.

Use an address your cluster can reach. On a local KinD cluster, that is the gateway of the `kind` Docker network:

```bash
export VAULT_ADDR="http://$(docker network inspect kind -f '{{range .IPAM.Config}}{{println .Gateway}}{{end}}' | grep -E '^[0-9]+\.' | head -1):8200"
echo $VAULT_ADDR
```

That normally prints `http://172.18.0.1:8200`. On a managed cluster, use the DNS name or load-balancer address of your Vault instance instead. The address is not a secret — only the token is.

### Verify Vault Health

```bash
curl -s --header "X-Vault-Token: $VAULT_TOKEN" --request GET $VAULT_ADDR/v1/sys/health
```

Expected response: one line of JSON showing Vault's status — look for
`"initialized":true` and `"sealed":false`. (`-s` keeps curl from painting its transfer
progress meter over the response.)

### Enable the Transit Secret Engine

```bash
curl -s --header "X-Vault-Token: $VAULT_TOKEN" --request POST --data '{"type":"transit"}' $VAULT_ADDR/v1/sys/mounts/transit
```

This enables the Transit secret engine at the `/transit` path. Vault answers 204, so
no output indicates success.

### Create the Encryption Key

```bash
curl -s --header "X-Vault-Token: $VAULT_TOKEN" --request POST $VAULT_ADDR/v1/transit/keys/my-encryption-key
```

This one does answer: a JSON description of the new key, carrying
`"name":"my-encryption-key"` and `"type":"aes256-gcm96"`. There is no key material in
it — that stays inside Vault. From here on, `my-encryption-key` is the only thing you
ever hand to SOPS.

### Create the Auth Secret

First, retrieve the MySQL root password that was auto-generated:

```bash
kubectl get secret --namespace "apps" weatherapp-auth-mysql -o jsonpath="{.data.mysql-root-password}" | base64 --decode
```

Create a `auth.yaml` file with the database credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: auth
  namespace: apps
stringData:
  values.yaml: |
    mysql:
      auth:
        rootPassword: <paste-the-root-password-you-just-decoded>
        username: staging_user
        password: staging_pass
        database: weatherapp_staging
        createDatabase: true
```

Use `stringData` to avoid double base64-encoding.

### Encrypt with SOPS and Vault

```bash
sops --hc-vault-transit $VAULT_ADDR/v1/transit/keys/my-encryption-key --encrypt --encrypted-regex '^(data|stringData)$' --in-place auth.yaml
```

- `--hc-vault-transit`: Specifies Vault's Transit engine as the encryption backend.
- `--encrypt`: Encrypts the file.
- `--encrypted-regex`: Only encrypts fields matching the pattern (data or stringData).
- `--in-place`: Overwrites the file with encrypted content.

After encryption, the stringData field is masked, and SOPS adds metadata for decryption.

### Create and Encrypt the API Key Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: api-key
  namespace: apps
stringData:
  values.yaml: |
    apikey: <your-rapidapi-key>
```

Encrypt it:

```bash
sops --hc-vault-transit $VAULT_ADDR/v1/transit/keys/my-encryption-key --encrypt --encrypted-regex '^(data|stringData)$' --in-place api-key.yaml
```

### Add Secrets to the Release Manifest

Both files are encrypted now, so they are safe to commit. Copy them — **as they are after encryption**, `ENC[...]` blobs and `sops:` blocks included — into `kustomize/base/release.yaml`, each as its own YAML document separated by `---`:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: api-key
  namespace: apps
stringData:
  values.yaml: ENC[AES256_GCM,data:...,type:str]
sops:
  hc_vault:
  - vault_address: http://172.18.0.1:8200
    engine_path: transit
    key_name: my-encryption-key
  # ... the rest of the SOPS metadata
---
apiVersion: v1
kind: Secret
metadata:
  name: auth
  namespace: apps
stringData:
  values.yaml: ENC[AES256_GCM,data:...,type:str]
sops:
  hc_vault:
  - vault_address: http://172.18.0.1:8200
    engine_path: transit
    key_name: my-encryption-key
  # ... the rest of the SOPS metadata
```

If an earlier lecture left an Age-encrypted version of the same `api-key` Secret in this file, delete that whole document while you are here. Once the Kustomization stops referencing the Age key, that document can no longer be decrypted and the entire reconciliation fails — not just that one Secret.

Remove the temporary plaintext-then-encrypted working files:

```bash
rm auth.yaml api-key.yaml
```

### Update the Helm Release Patch

Modify `kustomize/staging/auth-patch.yaml` to reference the secret instead of hardcoding values:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: weatherapp-auth
  namespace: apps
spec:
  valuesFrom:
    - kind: Secret
      name: auth
```

Note the apiVersion: `helm.toolkit.fluxcd.io/v2`. The v2 API went GA in Flux 2.3.0, and the old `v2beta1` was removed entirely in Flux 2.7.0 — on any current Flux, `v2beta1` manifests simply fail to apply.

### Configure Flux CD for Vault Decryption

Create a Kubernetes secret containing the Vault token:

```bash
echo $VAULT_TOKEN | kubectl create secret generic sops-hcvault --namespace=apps --from-file=sops.vault-token=/dev/stdin
```

The key name `sops.vault-token` is what tells Flux CD this is a HashiCorp Vault credential rather than an Age or GPG key. Create it in the **same namespace as the Kustomization that will use it** — Flux resolves `decryption.secretRef` in the Kustomization's own namespace, not in `flux-system`.

**One Secret, several backends.** A Kustomization decrypts through the one Secret its `secretRef` names, but that Secret can carry keys for several backends at the same time. `identity.agekey`, `identity.asc`, `sops.aws-kms`, `sops.azure-kv`, `sops.gcp-kms` and `sops.vault-token` are all recognised keys, and Flux's own documentation shows an Age identity and a Vault token side by side in a single Secret. So switching a repository to Vault does not force you to re-encrypt everything: you can add `sops.vault-token` to the Secret you already have. In this lecture we re-encrypt the API-token Secret anyway, to keep the whole repository on one backend.

Update the dev kustomization in `sync.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dev
  namespace: apps
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-hcvault
  interval: 1m0s
  path: ./kustomize/staging
  prune: true
  serviceAccountName: dev
  sourceRef:
    kind: GitRepository
    name: dev
```

### Commit and Reconcile

In the Flux repository:

```bash
git add .
git commit -m "Enable Vault encryption for secrets"
git push
```

In the weather app repository:

```bash
git add .
git commit -m "Enable Vault-encrypted secrets"
git push
```

Reconcile the kustomizations:

```bash
flux reconcile kustomization tenants --namespace=flux-system --with-source
flux reconcile kustomization dev --namespace=apps --with-source
```

### Verify Decryption

Check that Flux CD decrypted the secret correctly:

```bash
kubectl edit secret auth --namespace=apps
```

Decode the values to verify:

```bash
kubectl get secret auth --namespace=apps -o jsonpath="{.data.values\.yaml}" | base64 --decode
```

The output should show the unencrypted MySQL credentials.

---

## Common Commands Reference

| Command | Purpose |
|---------|---------|
| `docker run --cap-add=IPC_LOCK -d -p 8200:8200 hashicorp/vault:latest` | Start a Vault container |
| `curl -s -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/sys/health` | Check Vault health |
| `curl -s -H "X-Vault-Token: $VAULT_TOKEN" -X POST $VAULT_ADDR/v1/transit/keys/<key-name>` | Create a Transit encryption key |
| `sops --hc-vault-transit $VAULT_ADDR/v1/transit/keys/<key-name> --encrypt --in-place <file>` | Encrypt a file with Vault |
| `kubectl create secret generic sops-hcvault --from-file=sops.vault-token=/dev/stdin` | Store Vault token in Kubernetes |
| `flux reconcile kustomization <name> --namespace=<ns> --with-source` | Trigger Flux reconciliation, fetching the latest commit first |

---

## Final YAML Manifests

### auth.yaml (after encryption)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: auth
  namespace: apps
stringData:
  values.yaml: ENC[AES256_GCM,data:...,type:str]
sops:
  kms: []
  gcp_kms: []
  azure_kv: []
  hc_vault:
  - vault_address: http://172.18.0.1:8200
    engine_path: transit
    key_name: my-encryption-key
    created_at: '2026-01-01T00:00:00Z'
    enc: vault:v1:...
  pgp: []
  encrypted_regex: ^(data|stringData)$
  version: 3.8.1
  mac: ENC[AES256_GCM,data:...,type:str]
  lastmodified: '2026-01-01T00:00:00Z'
```

The exact encrypted values and metadata will vary based on your Vault instance and encryption timestamp.

---

## Further Reading

- [HashiCorp Vault Official Documentation](https://www.vaultproject.io/docs)
- [OpenBao Project on Linux Foundation](https://openbao.org/)
- [Flux CD Secrets Management](https://fluxcd.io/docs/security/)
- [Mozilla SOPS Documentation](https://github.com/mozilla/sops)
- [Good Practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
