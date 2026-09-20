---
title: "Secrets encryption with Age"
kicker: "FLUX CD · SECTION 5 · LECTURE 5"
description: "Generate an Age key pair, encrypt a Kubernetes Secret with SOPS, and configure a Flux Kustomization to decrypt it for a Helm release."
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Secrets encryption with Age

*Section 5, Lecture 5 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Why **Age** is the recommended successor to GPG for SOPS-based Secret encryption
- How to generate an Age key pair with `age-keygen`
- How to store the private key in a Kubernetes Secret that Flux's Kustomization controller can use for decryption
- How to encrypt a Secret manifest with `sops --encrypt --age` and wire it into a Helm release's values
- How to configure a Kustomization's `spec.decryption` so Flux decrypts the Secret automatically on sync

## Why Age over GPG

Both are supported by SOPS and both work with Flux the same way at the Kustomization level, but they are not equivalent tools day to day:

| | **Age** | **GPG** |
|---|---|---|
| Key generation | One command, sane defaults | Interactive prompts, several parameters to choose |
| Key format | A single small text file holding both keys | A keyring; keys are usually exported/imported separately |
| Cryptography | X25519 (modern elliptic-curve) | Typically RSA (older, larger keys) |
| Key size | Short — a few dozen characters | Long — an RSA 4096 key is unwieldy to handle |
| Tooling | Written in Go, minimal dependencies | Mature but heavier, historically prone to configuration footguns |

A shorter key is not a weaker one. Age's X25519 keys are shorter than an RSA 4096 key because elliptic-curve cryptography reaches equivalent security with far less key material — the two are not comparable byte-for-byte. Age is generally recommended over GPG for new SOPS setups because of its simplicity, not because GPG is insecure.

## Generate an Age key pair

Install Age, then generate a key pair:

```bash
brew install age
age-keygen -o age.agekey
```

`age-keygen` writes both the private and public key into `age.agekey` — there is no separate export step. Open the file and you will see the public key on a comment line and the private key on the line below it:

```bash
cat age.agekey
```

```text
# created: 2026-09-20T10:00:00Z
# public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
AGE-SECRET-KEY-1QZX...
```

You will use the public key to encrypt, and the private key to let the cluster decrypt.

## Store the private key in a Kubernetes Secret

Flux's Kustomization controller decrypts SOPS-encrypted manifests using a key it reads from a Kubernetes Secret. Create that Secret directly from the key file, piping it through standard input rather than writing it to disk again:

```bash
cat age.agekey | kubectl create secret generic sops-age \
  --namespace=apps \
  --from-file=age.agekey=/dev/stdin
```

> **Note:** The key inside the Secret **must** be named `age.agekey`. Flux detects
> which decryption method to use — Age or GPG — by looking at the file extension
> of the key inside the Secret, not by any field you set explicitly. A key ending
> in `.agekey` is treated as an Age key; a key ending in `.asc` is treated as a
> GPG key.

The Secret lives in the `apps` namespace here because this key decrypts a Secret that belongs to an application team, not the cluster-wide `flux-system` namespace used for admin-level credentials.

## Point SOPS at your Age recipient with .sops.yaml

The video passes `--age=<public-key>` on every `sops` invocation. That works, but for a repository with more than one Secret to encrypt it is worth defining the recipient once in a `.sops.yaml` file at the repository root, so every future `sops --encrypt` call in that tree picks it up automatically:

```yaml
creation_rules:
  - path_regex: .*\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

`encrypted_regex` restricts encryption to the `data` and `stringData` fields only — SOPS and Flux both leave the rest of the manifest (`apiVersion`, `kind`, `metadata`, and so on) in plain text, so the encrypted file stays readable and diffable in Git while the actual secret values stay opaque.

## Create the Secret manifest

Write the Kubernetes Secret you want to encrypt as a plain YAML file:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: api-key
  namespace: apps
stringData:
  values.yaml: |
    apikey: ecbc396f46mshb65cbb1f82cf334p1fcc87jsna5e962a3c542
```

Two details matter here. First, this Secret is nested under a `values.yaml` key because that is the default key a Flux `HelmRelease` looks for when it pulls chart values from a Secret or ConfigMap — it can be changed, but leaving it at the default keeps things simple. Second, use `stringData`, not `data`. A plain Kubernetes Secret stores `data` values as base64, but SOPS/Flux decryption does not re-encode a value that is already base64 — so if you base64-encode the value yourself under `data`, Flux applies SOPS's own re-encoding on top of it and the application receives a double-encoded, unusable value. `stringData` takes plain text and lets Kubernetes handle the encoding exactly once.

## Encrypt with sops --encrypt --age

With a `.sops.yaml` in place, encrypting is one command:

```bash
sops --encrypt --in-place api-key.yaml
```

Without a `.sops.yaml`, pass the same information explicitly on the command line:

```bash
sops --age=age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p \
  --encrypt \
  --encrypted-regex '^(data|stringData)$' \
  --in-place api-key.yaml
```

`--in-place` rewrites the file itself rather than creating a new one. Open it afterward and only the values under `stringData` are ciphertext — everything else in the manifest is still readable YAML, safe to commit to Git.

## Wire the encrypted Secret into a Helm release

Copy the encrypted Secret to the top of the manifest file that defines your `HelmRelease` resources, then reference it from the release's `valuesFrom`:

```yaml
spec:
  # ...existing HelmRelease fields...
  valuesFrom:
    - kind: Secret
      name: api-key
```

When Flux's Helm controller reconciles this release, it reads the decrypted `api-key` Secret and merges its `values.yaml` content into the chart values — the manifest itself never carries the raw key.

## Tell Flux how to decrypt: Kustomization spec.decryption

The Secret is encrypted, so the Kustomization that applies it needs to know how to decrypt it. Add a `decryption` block to the Kustomization's spec, pointing at the `sops-age` Secret you created earlier:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dev
  namespace: flux-system
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

This is the same shape used for GPG decryption — only the Secret name changes. The `provider` is always `sops`; Flux inspects the referenced Secret's key name at decrypt time to decide whether to use its Age or GPG code path.

## Reconcile and confirm

Commit and push both repositories — the one holding the Kustomization change and the one holding the encrypted Secret and Helm release — then reconcile in dependency order:

```bash
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization tenants --with-source
flux reconcile kustomization dev --with-source -n apps
```

Confirm the Secret landed, decrypted, in the target namespace:

```bash
kubectl get secrets -n apps
kubectl get secret api-key -n apps -o jsonpath='{.data.values\.yaml}' | base64 -d
```

The decoded output is the original plain-text value — proof that Flux decrypted the Secret and that it was not double-encoded along the way.

## Further reading

- [Age (GitHub)](https://github.com/FiloSottile/age)
- [Mozilla SOPS (GitHub)](https://github.com/getsops/sops)
- [Flux — Manage Kubernetes secrets with Mozilla SOPS](https://fluxcd.io/flux/guides/mozilla-sops/)
- [Flux — Kustomization API reference](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Flux — HelmRelease API reference (valuesFrom)](https://fluxcd.io/flux/components/helm/helmreleases/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
