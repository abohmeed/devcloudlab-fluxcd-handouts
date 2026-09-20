---
title: "Validating the integrity of Helm charts using Cosign"
kicker: "FLUX CD · SECTION 5 · LECTURE 7"
description: "How to sign OCI Helm charts with Cosign, how keyless signing differs from key pairs, and how to make Flux CD verify a chart before it installs it"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Validating the integrity of Helm charts using Cosign

*Section 5, Lecture 7 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Why HTTPS alone proves who served a Helm chart, not that its contents are untouched
- How to generate a Cosign key pair and sign a Helm chart after pushing it to an OCI registry
- The difference between key-pair signing and Sigstore's keyless signing
- How to make a HelmRelease's `verify` field reject any chart version Flux CD can't verify
- What Flux CD does when it encounters an unsigned or tampered chart

## Why signature verification matters

Since Helm 3.8.0, charts can be pushed to and pulled from **OCI registries**, the
same kind of registry that stores container images. That solves distribution, but
raises a separate question: when a chart is downloaded, is there proof its
contents weren't changed after the maintainer packaged it?

TLS answers a narrower question. If you pull a chart from
`registry.gitlab.com`, HTTPS proves you're really talking to that host — it says
nothing about whether the bytes inside the chart are the ones the publisher
intended. A registry, a mirror, or anything in between could still swap the
contents.

**Cosign** closes that gap. It hashes the chart's contents and signs that hash
with a private key. Change even one bit of the chart and the signature no
longer matches — so a chart passing signature verification is proof it's
byte-for-byte what the signer produced, not just that it arrived over a secure
connection.

## Install Cosign

```bash
brew install cosign
```

## Key-pair signing vs keyless signing

Cosign supports two ways to sign an artifact:

| | Key-pair signing | Keyless signing |
|---|---|---|
| **Key material** | A private/public key pair you generate and store | None — no key to protect, lose, or rotate |
| **How it signs** | `cosign sign --key cosign.key <ref>` | `cosign sign <ref>`, which opens an OIDC login (GitHub, Google, …) |
| **What proves identity** | Possession of the private key | A short-lived certificate Sigstore's Fulcio CA issues against your OIDC identity |
| **Where the signature is recorded** | The registry, next to the artifact | The registry, plus the public Rekor transparency log |
| **Verifying** | `cosign verify --key cosign.pub <ref>` | `cosign verify --certificate-identity=<you> --certificate-oidc-issuer=<issuer> <ref>` |

This lecture uses key-pair signing, since it maps directly onto a Secret Flux CD
can read inside the cluster. Keyless signing is worth knowing because it removes
key management entirely — the signer's identity comes from an OIDC provider
instead of a file you have to protect — and Flux CD can verify keyless-signed
charts too, by matching that recorded identity instead of a public key (see
**Configure Flux CD to verify the chart**, below).

## Generate a key pair

```bash
cosign generate-key-pair
```

This writes `cosign.key` (a password-protected private key — Cosign will prompt
you to set the password) and `cosign.pub` (the public key) into the current
directory. Only artifacts signed with the private key verify against the
matching public key, so keep `cosign.key` out of Git and treat it like any other
credential.

## Log in to the registry

Cosign pushes the signature it creates through Docker's registry client, which
is a separate credential store from Helm's own. Authenticate with both:

```bash
helm registry login registry.gitlab.com
docker login registry.gitlab.com
```

## Package and push the chart

Bump the chart version in `Chart.yaml` before packaging — you want a signed
version to exist alongside whatever version is already deployed, so you can
compare the two later.

```bash
helm package .
```

```bash
helm push weatherapp-auth-0.1.1.tgz oci://registry.gitlab.com/<your-namespace>/myweatherapp
```

`helm push` prints the SHA256 digest of the pushed artifact. Copy it — signing
needs it.

## Sign the chart

An OCI Helm chart is stored as a single layer, the same way a container image's
layers are stored. Cosign hashes that layer, signs the hash with your private
key, and pushes the resulting signature to the registry as its own artifact
next to the chart — which is why you sign *after* pushing, not before:

```bash
cosign sign --key cosign.key \
  registry.gitlab.com/<your-namespace>/myweatherapp/weatherapp-auth:0.1.1@sha256:<digest-from-the-push>
```

> **Note:** This only works for charts pulled as OCI artifacts. A chart served
> as a plain `.tgz` from a web server has no registry layer for Cosign to sign
> or for Flux CD to verify.

## Store the public key in the cluster

Whoever needs to verify the chart's integrity needs the public key, never the
private one. Put `cosign.pub` in a Secret in the namespace where the
HelmRelease lives:

```bash
kubectl create secret generic cosign-public-keys \
  --from-file=key1.pub=cosign.pub \
  --type=Opaque \
  -n apps
```

## Configure Flux CD to verify the chart

Add a `verify` block under `spec.chart.spec` on the HelmRelease. Flux CD
materializes this into the HelmChart object it actually reconciles, so the
verification runs every time it pulls a new version:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: weatherapp-auth
  namespace: apps
spec:
  serviceAccountName: dev
  interval: 5m
  chart:
    spec:
      chart: weatherapp-auth
      version: ">=0.1.0"
      sourceRef:
        kind: HelmRepository
        name: myweatherapp
      verify:
        provider: cosign
        secretRef:
          name: cosign-public-keys
```

> **Since this video was recorded:** the HelmRelease API has moved from
> `helm.toolkit.fluxcd.io/v2beta1` to `helm.toolkit.fluxcd.io/v2`, and the beta
> versions have since been removed — a manifest using `v2beta1` no longer
> applies. The manifest above uses the current `v2` apiVersion; the video
> shows the older `v2beta1` form. The `HelmRepository` this HelmRelease points
> to by name is declared elsewhere in the repository, and its own apiVersion
> has moved the same way: `source.toolkit.fluxcd.io/v1beta2` is now
> `source.toolkit.fluxcd.io/v1`.

To verify a keyless-signed chart instead, replace `secretRef` with
`matchOIDCIdentity`, naming the OIDC issuer and the identity that must have
signed it:

```yaml
      verify:
        provider: cosign
        matchOIDCIdentity:
          - issuer: "https://token.actions.githubusercontent.com"
            subject: "https://github.com/<org>/<repo>/.github/workflows/release.yaml@refs/heads/main"
```

`provider: cosign` is the only provider Flux CD's Helm verification supports.

## Commit, reconcile, and confirm

```bash
flux reconcile kustomization dev --with-source -n apps
flux reconcile helmrelease weatherapp-auth --with-source -n apps
```

```bash
helm list -n apps
```

`helm list` should show `weatherapp-auth` at the signed version. Now try
pointing the release constraint at an earlier, unsigned version and reconcile
again — Flux CD refuses to pull and apply it, and the HelmRelease reports a
signature verification failure instead of rolling back silently. The chart
only installs again once you either sign that version the same way, or move
the constraint back to a version that's already signed.

This is what makes the check worth having: a chart that isn't provably the one
the maintainer published never reaches the cluster, which is exactly the
software-supply-chain risk chart signing exists to close.

## Further reading

- [Flux CD — HelmReleases](https://fluxcd.io/flux/components/helm/helmreleases/)
- [Flux CD — HelmCharts](https://fluxcd.io/flux/components/source/helmcharts/)
- [Sigstore Cosign — signing overview](https://docs.sigstore.dev/cosign/signing/overview/)
- [Helm — OCI registries](https://helm.sh/docs/topics/registries/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
