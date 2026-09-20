<p align="center">
  <a href="https://devcloudlab.com"><img src="assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="130"></a>
</p>

<h1 align="center">Flux CD — Course Handouts</h1>

<p align="center">
  The written companions to the <strong>Flux CD</strong> course by
  <a href="https://devcloudlab.com"><strong>DevCloudLab</strong></a>.<br>
  One handout per lecture: the concepts, the commands, the manifests — all copyable.
</p>

<p align="center">
  <a href="https://devcloudlab.com"><strong>→ More hands-on cloud-native courses at DevCloudLab.com</strong></a>
</p>

---

## How to use these

Each lecture in the course links to its handout here. Watch the lecture, then
keep the handout: every command and manifest is in a code block you can copy
straight out of the page with the button in its top-right corner.

Where a lecture was recorded before a tool changed, the handout gives the
**current working command** and flags what the video shows, in a note like this:

> **Since this video was recorded:** the older form no longer works on current
> versions. The command above is the current equivalent.

## Handouts

## Section 1 — Introduction

- **2.** [Understanding GitOps](handouts/s01/l02-understanding-gitops.md)
- **3.** [Introduction to Flux CD and its role in Kubernetes deployments](handouts/s01/l03-introduction-to-flux-cd-and-its-role-in-kubernetes-d.md)
- **4.** [Benefits of automating deployments with Flux CD](handouts/s01/l04-benefits-of-automating-deployments-with-flux-cd.md)
- **5.** [GitOps and DevOps](handouts/s01/l05-gitops-and-devops.md)

## Section 2 — Getting started with Flux CD

- **1.** [Installing and configuring Git](handouts/s02/l01-installing-and-configuring-git.md)
- **2.** [Kubernetes cluster setup](handouts/s02/l02-kubernetes-cluster-setup.md)
- **3.** [Installing and bootstrapping Flux CD](handouts/s02/l03-installing-and-bootstrapping-flux-cd.md)
- **4.** [Syncing Kubernetes resources with Flux CD](handouts/s02/l04-syncing-kubernetes-resources-with-flux-cd.md)
- **5.** [Flux CD workflows and automation processes](handouts/s02/l05-flux-cd-workflows-and-automation-processes.md)
- **6.** [Implementing declarative infrastructure with Flux CD](handouts/s02/l06-implementing-declarative-infrastructure-with-flux-cd.md)
- **7.** [Migrating off the removed Flux beta APIs](handouts/s02/l07-migrating-off-the-removed-flux-beta-apis.md)

## Section 3 — Flux CD and Helm

- **1.** [Understanding Helm and its interaction with Flux CD](handouts/s03/l01-understanding-helm-and-its-interaction-with-flux-cd.md)
- **2.** [Deploying applications using Flux CD with Git as the Helm chart source](handouts/s03/l02-deploying-applications-using-flux-cd-with-git-as-the.md)
- **3.** [Modifying the Helm chart and overriding the default values](handouts/s03/l03-modifying-the-helm-chart-and-overriding-the-default.md)
- **4.** [(Optional) Creating a private Helm repository](handouts/s03/l04-optional-creating-a-private-helm-repository.md)
- **5.** [Using HTTP Helm repositories with Flux CD](handouts/s03/l05-using-http-helm-repositories-with-flux-cd.md)
- **6.** [Using OCI Helm repositories with Flux CD](handouts/s03/l06-using-oci-helm-repositories-with-flux-cd.md)
- **7.** [Using ECR as a Helm repository with EKS and Flux CD](handouts/s03/l07-using-ecr-as-a-helm-repository-with-eks-and-flux-cd.md)
- **8.** [Automating Helm Release upgrades](handouts/s03/l08-automating-helm-release-upgrades.md)
- **9.** [Installing a web UI for Flux CD — Flux Operator replaces Weave GitOps](handouts/s03/l09-installing-a-web-ui-for-flux-cd-flux-operator-replac.md)

## Section 4 — Flux CD and Kustomize

- **1.** [Flux CD and Kustomize](handouts/s04/l01-flux-cd-and-kustomize.md)
- **2.** [Different Git directory structuring methods](handouts/s04/l02-different-git-directory-structuring-methods.md)
- **3.** [Restructuring our repository to follow best practices](handouts/s04/l03-restructuring-our-repository-to-follow-best-practice.md)
- **4.** [Using Flux CD with the Monorepo approach](handouts/s04/l04-using-flux-cd-with-the-monorepo-approach.md)
- **5.** [Restructuring the repository to follow the multi-tenancy approach](handouts/s04/l05-restructuring-the-repository-to-follow-the-multi-ten.md)
- **6.** [Onboarding tenants and enforcing restrictions — the dev team](handouts/s04/l06-onboarding-tenants-and-enforcing-restrictions-the-de.md)
- **7.** [Onboarding tenants and enforcing restrictions — the admin team](handouts/s04/l07-onboarding-tenants-and-enforcing-restrictions-the-ad.md)

## Section 5 — Flux CD security

- **1.** [Section introduction — Flux CD security](handouts/s05/l01-section-introduction-flux-cd-security.md)
- **2.** [Secrets encryption with Bitnami's Sealed Secrets](handouts/s05/l02-secrets-encryption-with-bitnami-s-sealed-secrets.md)
- **3.** [Flux CD's Kustomization integration with Mozilla SOPS](handouts/s05/l03-flux-cd-s-kustomization-integration-with-mozilla-sop.md)
- **4.** [Secrets encryption with GPG](handouts/s05/l04-secrets-encryption-with-gpg.md)
- **5.** [Secrets encryption with Age](handouts/s05/l05-secrets-encryption-with-age.md)
- **6.** [Secrets encryption with HashiCorp Vault (and OpenBao)](handouts/s05/l06-secrets-encryption-with-hashicorp-vault-and-openbao.md)
- **7.** [Validating the integrity of Helm charts using Cosign](handouts/s05/l07-validating-the-integrity-of-helm-charts-using-cosign.md)

## Section 6 — Image automation

- **1.** [What is image automation](handouts/s06/l01-what-is-image-automation.md)
- **2.** [Image automation with public registries](handouts/s06/l02-image-automation-with-public-registries.md)
- **3.** [Image automation with private registries](handouts/s06/l03-image-automation-with-private-registries.md)

## Section 7 — Flux CD notification automation

- **1.** [Section introduction — Flux CD notification automation](handouts/s07/l01-section-introduction-flux-cd-notification-automation.md)
- **2.** [Sending Flux CD notifications to Slack](handouts/s07/l02-sending-flux-cd-notifications-to-slack.md)
- **3.** [Flux CD automatic reconciliation using webhooks](handouts/s07/l03-flux-cd-automatic-reconciliation-using-webhooks.md)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="110"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
