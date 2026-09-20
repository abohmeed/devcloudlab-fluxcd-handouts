---
title: "Secrets encryption with GPG"
kicker: "FLUX CD · SECTION 5 · LECTURE 4"
description: "Generate a GPG key pair, store it as a Kubernetes Secret, and wire a Flux Kustomization to decrypt SOPS-encrypted manifests with it"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Secrets encryption with GPG

*Section 5, Lecture 4 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- What **GPG** (GNU Privacy Guard) is and why it's a natural fit for encrypting Secrets before they land in Git
- How to generate a passphrase-free GPG key pair non-interactively, for a controller that can never be asked for a password
- How to hand that key to Flux's `kustomize-controller` as a Kubernetes Secret
- How to write a `.sops.yaml` creation rule so Mozilla SOPS encrypts only the sensitive fields of a manifest, not the whole file
- How to point a Flux `Kustomization` at the key so it decrypts Secrets automatically during reconciliation

## Why GPG for GitOps Secrets

**GPG** is an implementation of the OpenPGP standard: a pair of keys, one public and one private. The public key encrypts; only the matching private key decrypts. GPG also generates a random per-message session key, encrypts the session key with the recipient's public key, and uses the session key to encrypt the actual payload — this is what makes public-key encryption practical for data of any size.

That key pair maps cleanly onto a GitOps problem. A Kubernetes `Secret` manifest checked into Git is plaintext by default, which defeats the point of storing it in Git in the first place. **Mozilla SOPS** (Secrets OPerationS) solves this by encrypting only the sensitive fields of a YAML or JSON file — the `data` and `stringData` keys of a Secret — and leaving the rest of the manifest readable and diffable. SOPS supports several encryption backends; this lecture uses GPG as the first one.

Flux's `kustomize-controller` is the component that decrypts SOPS-encrypted manifests during reconciliation, which means the **private** key has to live in the cluster, not on your laptop.

## Generate a GPG key pair for Flux

Install the tools first:

```bash
# Debian/Ubuntu
sudo apt install gnupg
brew install sops

# macOS
brew install gnupg sops
```

`gpg --full-generate-key` normally asks a series of interactive questions. Since this key will belong to a controller, automate the generation with a batch file instead of answering prompts by hand. Create `gpg.conf` (the filename here is arbitrary):

```
%no-protection
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Expire-Date: 0
Name-Comment: Flux secrets
Name-Real: staging
```

A few of these fields matter more than they look:

| Field | Meaning |
|---|---|
| `%no-protection` | No passphrase on the private key — required, because `kustomize-controller` has no way to supply one when it decrypts |
| `Key-Type: 1` / `Subkey-Type: 1` | RSA for both the master (identity) key and the encryption subkey |
| `Key-Length: 4096` | 4096-bit RSA, a reasonable strength for this use case |
| `Expire-Date: 0` | The key never expires |
| `Name-Real` | The key's identity — name it for the cluster or team it belongs to, since that's what you'll be rotating |

> **Note:** setting `Expire-Date: 0` is convenient for a lab, but on a real cluster you should set an expiration and rotate the key on a schedule. A key that never expires is a key you'll forget to rotate.

Generate the key pair from the batch file:

```bash
gpg --batch --full-generate-key gpg.conf
```

Then retrieve its fingerprint — the string that uniquely identifies the key:

```bash
gpg --list-secret-keys staging
```

## Store the private key as a Kubernetes Secret

Export the private key in ASCII-armored form and create a Kubernetes Secret from it. The filename's *extension* matters here: `kustomize-controller` inspects it to decide which decryption backend to use, and `.asc` signals GPG.

```bash
gpg --export-secret-keys --armor <fingerprint> > sops.asc

kubectl create secret generic sops-gpg \
  --namespace=flux-system \
  --from-file=sops.asc
```

If you'd rather not write the private key to disk at all, pipe both commands together. Keep the `sops.asc=` prefix on `--from-file` — it's the field name the Secret will store the value under, and `/dev/stdin` tells `kubectl` to read the value from the pipe instead of a file:

```bash
gpg --export-secret-keys --armor <fingerprint> | \
  kubectl create secret generic sops-gpg \
  --namespace=flux-system \
  --from-file=sops.asc=/dev/stdin
```

Once the key is in the cluster, delete the local copies — the config file and the exported key material:

```bash
rm sops.asc gpg.conf
gpg --delete-secret-keys <fingerprint>
```

`gpg` will prompt more than once to confirm the deletion. That's expected: without this key, anything encrypted with the matching public key becomes unrecoverable.

> **Note:** keep a backup of the private key somewhere durable — a dedicated secrets manager such as HashiCorp Vault or AWS KMS — before you delete every local copy. Losing this key means losing access to every Secret it encrypted.

## Publish the public key and the SOPS rule

Export the public key so it's available for encrypting Secrets, and commit it alongside the cluster it belongs to:

```bash
gpg --export --armor <fingerprint> > ./clusters/staging/.sops.pub.asc
```

Any teammate who needs to encrypt Secrets for this cluster imports it into their own keyring:

```bash
gpg --import ./clusters/staging/.sops.pub.asc
```

This setup uses one key pair per **cluster**, not per namespace or team — the trade-off is discussed further on: `kustomize-controller` decrypts directly, so there's no separate per-team controller to hand a separate key to the way Sealed Secrets does.

Now tell SOPS which files to encrypt, and which fields inside them. Create `.sops.yaml` at the root of the directory tree it should apply to — the rule cascades into every subdirectory below it, so it only needs to be written once:

```yaml
creation_rules:
  - path_regex: .*.yaml
    encrypted_regex: ^(data|stringData)$
    pgp: <fingerprint>
```

`path_regex` matches every YAML file in scope. `encrypted_regex` restricts SOPS to encrypting only lines under `data` or `stringData` — the actual secret payload — rather than the whole manifest, which is what keeps the rest of the file readable in a diff.

## Encrypt a Secret and wire up the Kustomization

With the rule in place, encrypting a Secret needs no extra flags — SOPS reads the nearest `.sops.yaml` automatically:

```bash
sops --encrypt --in-place secret.yaml
```

The result is no longer a valid Kubernetes manifest: `data`/`stringData` are now ciphertext plus a block of SOPS metadata, so `kubectl apply` can't consume it directly. Only Flux's `kustomize-controller` knows what to do with it. Commit the encrypted file as part of your normal sync path (for example, in place of a plaintext Secret inside a `Kustomization`'s resources).

The controller still needs to be told which key to decrypt with. Add a `decryption` block to the `Kustomization` that applies the encrypted manifest:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenants
  namespace: flux-system
spec:
  # ...existing fields...
  decryption:
    provider: sops
    secretRef:
      name: sops-gpg
```

`secretRef.name` points at the Secret created earlier — `sops-gpg` in the `flux-system` namespace — which holds the private key. From this point on, any encrypted manifest this `Kustomization` applies is decrypted transparently during reconciliation.

## SOPS/GPG vs Sealed Secrets

| | Sealed Secrets | SOPS + GPG |
|---|---|---|
| Decryption | A dedicated controller, installable independently of Flux | Flux's own `kustomize-controller` |
| Key scope | One key pair can be scoped per team/namespace | One key pair per cluster in this setup |
| Encrypted output | Still a valid custom resource (`SealedSecret`) | Not a valid Kubernetes manifest — only Flux can consume it |

A per-team key pair is achievable with SOPS too, by inserting an additional `Kustomization` between the cluster and each tenant — but that adds real complexity, and a single cluster-scoped key is the simpler default.

## Further reading

- [Flux — Manage Kubernetes secrets with Mozilla SOPS](https://fluxcd.io/flux/guides/mozilla-sops/)
- [Flux — Kustomization API reference](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [GnuPG documentation](https://www.gnupg.org/documentation/)
- [Kubernetes — Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
