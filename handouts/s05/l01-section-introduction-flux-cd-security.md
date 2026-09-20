---
title: "Section introduction — Flux CD security"
kicker: "FLUX CD · SECTION 5 · LECTURE 1"
description: "A map of this section: why secrets in Git are a problem, and which tool — Sealed Secrets, SOPS, GPG, Age, Vault or Cosign — to reach for and when"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Section introduction — Flux CD security

*Section 5, Lecture 1 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Why storing plain Kubernetes Secrets in Git is unsafe, even in a private repository
- The difference between **encrypting a secret** and **signing an artifact** — and why this section covers both
- Which tool in the GitOps ecosystem solves which part of the problem
- How the tools in this section combine into a layered security strategy, rather than competing with each other

## Why secrets in Git are a problem

GitOps works by making Git the single source of truth: everything the cluster runs is declared in a repository, and a controller like Flux reconciles the cluster to match it. That model breaks down for one specific type of object — the Kubernetes `Secret`. A `Secret` is not encrypted at rest in its plain form; it is base64-encoded, which is an encoding, not encryption, and reversible by anyone who can read the file. Commit one to Git and it is readable in the file itself, in every branch that touched it, and in the full commit history, even after you "fix" it in a later commit. A private repository does not solve this either — it only narrows who the leak reaches, not whether the secret is exposed in plaintext to everyone with read access, including CI systems, forks and backups.

The tools in this section exist to close that gap without breaking the GitOps model. Each one lets you commit *something* to Git — an encrypted blob, a reference to an external system — so the repository stays the complete, auditable record of what the cluster runs, while the actual secret value never sits in the repository unprotected.

## The toolkit this section covers

| Tool | What it protects | Where the secret lives | Reach for it when |
|---|---|---|---|
| **Sealed Secrets** | Kubernetes `Secret` objects | Encrypted in Git; decrypted only by the controller's private key inside the cluster | You want a Kubernetes-native, Flux-friendly encryption workflow with no external dependency |
| **SOPS** | Files — YAML, JSON, `.env`, and more | Encrypted in Git; decrypted with a key from a backend you choose | You need to encrypt more than just Kubernetes Secrets, or want one tool across several file types |
| **GPG** | The encryption key behind SOPS | A personal or team keypair, managed outside Git | You already manage PGP keys, or want a backend with no cloud dependency |
| **Age** | The encryption key behind SOPS | A small, modern keypair — no keyring required | You want a simpler alternative to GPG with less operational overhead |
| **HashiCorp Vault** | Secrets, plus dynamic credentials and access policies | A dedicated secrets-management server, outside Git entirely | Your organization needs centralized secret storage, rotation, and fine-grained access control across many systems, not just this cluster |
| **Cosign** | The integrity and origin of a Helm chart or container image | A signature attached to the artifact, verified against a public key | You need proof that what Flux is about to deploy is exactly what your pipeline built — not a secrets tool at all, but the artifact-integrity half of this section |

Notice that the table splits into two jobs. Sealed Secrets, SOPS, GPG, Age and Vault all answer *how do I keep a secret value out of plaintext in Git*. Cosign answers a different question — *how do I know this chart wasn't tampered with before Flux applied it* — which is why it closes out the section rather than opening it.

> **Since this video was recorded:** two of these projects changed under new ownership.
> Mozilla donated SOPS to the Cloud Native Computing Foundation, and the project is now
> simply called **SOPS** rather than Mozilla SOPS. Separately, HashiCorp relicensed Vault
> under the Business Source License (BUSL) in August 2023; the last fully open-source
> release was forked by the Linux Foundation as **OpenBao**, which stays under the
> original Mozilla Public License. Where this section says "Vault," check whether your
> use case needs HashiCorp's licensed product or whether OpenBao's open-source fork
> covers it.

## Further reading

- [Flux CD — Secrets management](https://fluxcd.io/flux/guides/mozilla-sops/)
- [SOPS on GitHub](https://github.com/getsops/sops)
- [Sealed Secrets on GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [Age encryption tool](https://github.com/FiloSottile/age)
- [HashiCorp Vault documentation](https://developer.hashicorp.com/vault/docs)
- [Sigstore Cosign documentation](https://docs.sigstore.dev/cosign/signing/overview/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
