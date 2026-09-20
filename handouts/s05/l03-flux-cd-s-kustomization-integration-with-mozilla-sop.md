---
title: "Flux CD's Kustomization integration with Mozilla SOPS"
kicker: "FLUX CD · SECTION 5 · LECTURE 3"
description: "How SOPS integrates with GPG, AWS KMS, Azure Key Vault and Google Cloud KMS, and how the Flux Kustomization decryption field wires it in"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Flux CD's Kustomization integration with Mozilla SOPS

*Section 5, Lecture 3 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- What SOPS is, and why it exists alongside Sealed Secrets rather than replacing it
- How SOPS fits into an existing key management system — GPG, AWS KMS, Azure Key Vault, or Google Cloud KMS
- The shape of the `.sops.yaml` config file and a working `sops --encrypt` command
- How the Flux Kustomization `spec.decryption` field is structured, and how Flux finds the right decryption key
- What changed in the SOPS project and the Flux API since this video was recorded

## Sealed Secrets vs. SOPS

The previous lecture covered **Sealed Secrets**: a self-contained scheme where the private key lives inside the cluster and a matching public key encrypts locally. It works well, but it assumes you're happy generating and storing that key pair yourself. Some organizations already run a key management system and would rather plug into it than run a second one just for GitOps.

| | Sealed Secrets | SOPS |
|---|---|---|
| Key storage | Private key inside the cluster | External — GPG, AWS KMS, Azure Key Vault, GCP KMS, or HashiCorp Vault |
| Best fit | Self-contained clusters, no existing KMS | Organizations with an existing key management system |
| Encryption scope | Whole Secret object | Configurable — typically just `data` / `stringData` |

## What is SOPS

**SOPS** (Secrets OPerationS) is an open-source tool for encrypting, decrypting, and editing files that contain sensitive data. Instead of a bespoke workflow, SOPS lets you work with an encrypted file almost as if it were plaintext — it decrypts on open, re-encrypts on save, and can also decrypt a file for a script or CI job to read.

SOPS doesn't hold its own keys. It integrates with existing key management systems and encrypts each file's data with a data key, then encrypts that data key with one or more master keys from whichever backend you configure — GPG, AWS KMS, Azure Key Vault, or Google Cloud KMS.

> **Since this video was recorded:** SOPS is no longer a Mozilla project. It moved to
> the Cloud Native Computing Foundation and now lives at
> [github.com/getsops/sops](https://github.com/getsops/sops) rather than under the
> `mozilla` GitHub organization. The tool and its file formats are unchanged — only the
> home has moved. This lecture keeps the title "Mozilla SOPS" because that's the name
> used in the video.

## Configuring SOPS: `.sops.yaml`

SOPS reads its encryption rules from a `.sops.yaml` file at the root of the directory tree it's run against. The rules decide which files get encrypted, which fields inside them, and which key backend to use:

```yaml
creation_rules:
  - path_regex: .*\.yaml$
    encrypted_regex: ^(data|stringData)$
    pgp: <YOUR_GPG_FINGERPRINT>
```

`encrypted_regex` is the important line for Kubernetes Secrets: it tells SOPS to encrypt only the `data` and `stringData` fields, leaving `apiVersion`, `kind`, and `metadata` in plaintext. This matters for Flux, covered below.

Swap the `pgp:` line for the backend you actually use:

```yaml
kms: arn:aws:kms:us-east-1:111122223333:key/<key-id>        # AWS KMS
azure_kv: https://<vault-name>.vault.azure.net/keys/<key>   # Azure Key Vault
gcp_kms: projects/<project>/locations/global/keyRings/<ring>/cryptoKeys/<key>  # GCP KMS
```

## Encrypting a secret

With `.sops.yaml` in place, encrypting a file is a single command — SOPS reads the matching rule and picks the key backend for you:

```bash
sops --encrypt --in-place secret.yaml
```

Commit the resulting file to Git as usual. The `apiVersion`, `kind`, and `metadata` fields stay readable in diffs and pull requests; only `data`/`stringData` is ciphertext.

## Wiring SOPS into a Flux Kustomization

A Flux `Kustomization` has an optional `spec.decryption` field. When it's set, Flux decrypts the matching SOPS-encrypted files before applying them:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps/my-app
  sourceRef:
    kind: GitRepository
    name: my-app
  decryption:
    provider: sops
    secretRef:
      name: sops-keys
```

Two fields are required: `provider`, which today only accepts `sops`, and `secretRef.name`, the Kubernetes Secret that holds the decryption keys. `sops-keys` above is just an example name — call it whatever you like, as long as `secretRef.name` matches.

> **Since this video was recorded:** the `Kustomization` API used in this example is
> `kustomize.toolkit.fluxcd.io/v1`. Flux has since removed `v1beta2`, which is what
> older material — including this video — may show. If you're following along on a
> current Flux install, use `v1` as written above.

One detail worth remembering: `decryption` only works against SOPS-encrypted *values* inside a manifest, not against a manifest that is entirely ciphertext. That's exactly what the `encrypted_regex` in `.sops.yaml` controls — encrypt the whole file and Flux has nothing readable to parse as YAML; encrypt just `data`/`stringData` and it works.

## The decryption Secret: how Flux tells keys apart

The Secret named in `secretRef` holds one or more decryption keys, and Flux (through SOPS) identifies each key's type by its field name suffix:

| Key backend | Field name suffix | Example |
|---|---|---|
| GPG | `.asc` | `identity.asc` |
| AWS KMS | `sops.aws-kms` | `sops.aws-kms` |
| Azure Key Vault | `sops.azure-kv` | `sops.azure-kv` |
| GCP KMS | `sops.gcp-kms` | `sops.gcp-kms` |

For a GPG-backed setup, the Secret would look like this once created:

```bash
kubectl create secret generic sops-keys \
  --namespace=flux-system \
  --from-file=identity.asc=./private.asc
```

For AWS, Azure, or GCP, that Secret typically holds cloud credentials rather than a private key, and it's only needed when you're not using the cluster's own identity — a pod running under **IRSA** on EKS, or an equivalent workload identity on AKS/GKE, can authenticate to KMS without any static credential in the Secret at all. That IRSA path is covered in a later lecture.

## Where HashiCorp Vault fits

Vault isn't a SOPS backend in the same sense as GPG or a cloud KMS — SOPS doesn't talk to Vault directly. Organizations that standardize on Vault typically use it to generate and manage the GPG or KMS keys that SOPS does understand, so Vault sits one layer above this integration rather than inside it.

## What's next

Sealed Secrets and SOPS solve the same problem from different directions — pick whichever matches the key management your organization already has. The coming lectures build on this `decryption` field with hands-on setups for specific backends, including using AWS KMS through IRSA.

## Further reading

- [SOPS on GitHub](https://github.com/getsops/sops)
- [Flux Kustomization API — decryption](https://fluxcd.io/flux/components/kustomize/kustomizations/#decryption)
- [Flux guide: manage Kubernetes secrets with SOPS](https://fluxcd.io/flux/guides/mozilla-sops/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
