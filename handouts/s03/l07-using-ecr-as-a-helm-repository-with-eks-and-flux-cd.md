---
title: "Using ECR as a Helm repository with EKS and Flux CD"
kicker: "FLUX CD · SECTION 3 · LECTURE 7"
description: "This lecture demonstrates how to deploy Flux CD on Amazon EKS and use AWS Elastic Container Registry (ECR) as a private Helm repository. We use IAM Roles for Service Accounts"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Using ECR as a Helm repository with EKS and Flux CD

*Section 3, Lecture 7 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Provision an EKS cluster with an OIDC provider enabled for IAM Roles for Service Accounts
- Create an IAM role and trust policy that lets Flux CD's source-controller assume it via OIDC
- Configure a HelmRepository with `type: oci` and `provider: aws` to authenticate to ECR without storing credentials in Git
- Push a packaged Helm chart to a private ECR repository and deploy it with a HelmRelease
- Tear down the EKS cluster, ECR repository, and IAM role to stop billing after the lab

## Overview

This lecture demonstrates how to deploy Flux CD on Amazon EKS and use AWS Elastic Container Registry (ECR) as a private Helm repository. We use IAM Roles for Service Accounts (IRSA) to allow Flux CD's source controller to authenticate to ECR securely without storing credentials in Git.

### Requirements

- AWS account with administrative or appropriate permissions
- AWS CLI installed and configured
- eksctl command line tool
- kubectl installed
- Helm 3.x installed
- A Git repository (GitLab recommended; other platforms work similarly)
- Docker installed (for logging into ECR)

**Note:** This lecture uses real AWS resources (EKS cluster, ECR repositories, IAM roles). Be aware of associated costs and clean up resources when finished.

---

## Key Commands Reference

### Install Tools
```bash
# macOS (Homebrew)
brew install awscli eksctl
```
```bash
# Linux
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install
curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" \
  | tar xz -C /tmp && sudo install -m 0755 /tmp/eksctl /usr/local/bin/eksctl
```
Installs the command line tools needed to interact with AWS services and provision EKS clusters. The Homebrew formula is `awscli`, not `aws`.

### Configure AWS Credentials
```bash
aws configure
```
Sets up your AWS access key, secret key, and default region for CLI operations.

### Create EKS Cluster
```bash
eksctl create cluster \
--name my-cluster \
--version auto \
--region us-east-1 \
--nodegroup-name my-nodes \
--node-type t3.large \
--nodes 1 \
--nodes-min 1 \
--nodes-max 2 \
--managed \
--with-oidc
```
Provisions an EKS cluster with one node and an OIDC provider for IAM role integration. The `--with-oidc` flag is essential for IRSA.

### Create IAM Role
```bash
aws iam create-role --role-name FluxCDECR --assume-role-policy-document file://trust.json
```
Creates an IAM role that will be assumed by the Flux CD service account via OIDC.

### Attach ECR Policy
```bash
aws iam attach-role-policy --role-name FluxCDECR --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```
Grants the role permission to read from ECR repositories.

### Bootstrap Flux CD
```bash
flux bootstrap gitlab \
--owner=<your-gitlab-username> \
--repository=<your-repository-name> \
--branch=main \
--path=clusters/eks \
--token-auth \
--personal
```
Installs Flux CD on the EKS cluster and configures it to manage manifests from a Git repository. Replace `<your-gitlab-username>` and `<your-repository-name>` with your own GitLab username and repository, and export your GitLab personal access token as `GITLAB_TOKEN` first — `--token-auth` reads it from the environment.

### Package Helm Chart
```bash
helm package ./apache
```
Creates a `.tgz` file from your Helm chart, ready to be pushed to ECR.

### Log In to ECR
```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin accountID.dkr.ecr.us-east-1.amazonaws.com
```
Authenticates Docker (and Helm) to push to your private ECR registry. Replace `accountID` with your AWS account ID.

### Push Chart to ECR
```bash
helm push ./apache-0.1.0.tgz oci://accountID.dkr.ecr.us-east-1.amazonaws.com
```
Uploads the packaged Helm chart to ECR. The package name must match the repository name in ECR.

### Verify Deployment
```bash
kubectl get helmrepository
kubectl get helmrelease
kubectl get pods
```
Checks that the HelmRepository source is ready, the HelmRelease is deployed, and pods are running.

---

## IRSA Trust Policy

Save this as `trust.json` and replace `accountID` and `clusterID` with your actual values:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::accountID:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/clusterID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.us-east-1.amazonaws.com/id/clusterID:sub": "system:serviceaccount:flux-system:source-controller",
          "oidc.eks.us-east-1.amazonaws.com/id/clusterID:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

This policy allows the Flux CD source controller service account (running in the flux-system namespace) to assume the FluxCDECR role via OIDC.

---

## Kustomization Patch

Add this patch to `clusters/eks/flux-system/kustomization.yaml` to annotate the source-controller service account with the IAM role ARN:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
patches:
  - patch: |
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: source-controller
        annotations:
          eks.amazonaws.com/role-arn: "arn:aws:iam::accountID:role/FluxCDECR"
    target:
      kind: ServiceAccount
      name: source-controller
```

Replace `accountID` with your AWS account ID. This annotation tells the EKS OIDC provider to automatically inject AWS credentials into the source controller pods.

---

## HelmRepository Manifest

Save this as `clusters/eks/ecr.yaml`:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ecr
  namespace: default
spec:
  type: oci
  interval: 5m0s
  url: oci://accountID.dkr.ecr.us-east-1.amazonaws.com
  provider: aws
```

Replace `accountID` with your AWS account ID. The `provider: aws` field tells Flux to use the service account's IAM role credentials to authenticate to ECR.

---

## HelmRelease Manifest

Save this as `clusters/eks/apache-helm-release.yaml`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: apache
  namespace: default
spec:
  interval: 5m
  chart:
    spec:
      chart: apache
      version: '0.1.0'
      sourceRef:
        kind: HelmRepository
        name: ecr
        namespace: default
      interval: 1m
```

This manifest instructs Flux to fetch the Apache chart from the ECR Helm repository and deploy it to the cluster.

---

## Key Concepts

### IRSA (IAM Roles for Service Accounts)

IRSA is the mechanism that links Kubernetes service accounts to AWS IAM roles. When a pod with an annotated service account tries to access AWS APIs, the EKS OIDC provider exchanges the pod's identity token for temporary AWS credentials. This allows pods to access AWS resources without storing long-lived credentials in Kubernetes secrets.

### HelmRepository with OCI and AWS Provider

When you set `type: oci` and `provider: aws` on a HelmRepository, Flux uses the IRSA mechanism to authenticate to ECR instead of using a generic secret. This is more secure than storing ECR credentials in a Kubernetes secret in Git.

### Cluster Reconciliation

After applying new manifests, you can trigger Flux to immediately reconcile with:

```bash
flux reconcile kustomization flux-system --with-source
```

This forces Flux to check the Git repository and apply any changes immediately, rather than waiting for the default 10-minute interval.

---

## Troubleshooting

**HelmRepository shows "Error" status**: Check that the OIDC provider is created on your cluster and the service account is correctly annotated. Verify the ECR URL is correct and the repository exists.

**HelmRelease fails to pull chart**: Ensure the chart version matches what is in ECR, and that the role has the AmazonEC2ContainerRegistryReadOnly policy attached.

**kubectl commands fail to connect**: Make sure your kubeconfig is set up correctly. Run `aws eks update-kubeconfig --name my-cluster --region us-east-1` to refresh your kubeconfig.

**ECR login fails**: Verify your AWS credentials are correct and you have ECR permissions. The personal access token (if using) should not expire during the demo.

---

## Clean Up — do this as soon as you are finished

An EKS cluster keeps billing until you delete it: roughly $0.10/hour for the control
plane plus the cost of the node. Nothing in this lecture deletes it for you.

```bash
# 1. The cluster, its nodegroup and its VPC (10-20 minutes)
eksctl delete cluster --name my-cluster --region us-east-1 --wait

# 2. The ECR repository, and the chart in it
aws ecr delete-repository --repository-name apache --region us-east-1 --force

# 3. The IAM role (detach the managed policy first, or the delete is refused)
aws iam detach-role-policy --role-name FluxCDECR \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam delete-role --role-name FluxCDECR
```

Then check that nothing survived, rather than assuming:

```bash
eksctl get cluster --region us-east-1
aws ecr describe-repositories --region us-east-1 --query 'repositories[].repositoryName'
aws iam get-role --role-name FluxCDECR   # should report NoSuchEntity
```

---

## Next Steps

- **Pod Identity Alternative**: For new EKS clusters, consider using EKS Pod Identity instead of IRSA. It provides the same functionality without requiring an OIDC provider and is simpler to configure.
- **Private Git Repository**: Use a private Git repository for your Flux configuration to reduce the risk of accidental credential exposure.
- **Helm Values**: Explore using HelmRelease `valuesFrom` to manage Helm values from ConfigMaps or Secrets.
- **Multi-cluster**: Extend this setup to multiple EKS clusters, each with their own Flux bootstrap and service accounts.

---

## Further Reading

- **Flux CD — Migrate to the Helm Controller**: https://fluxcd.io/flux/migration/helm-operator-migration/
- **AWS EKS and Helm**: https://docs.aws.amazon.com/eks/latest/userguide/helm.html
- **IRSA Setup**: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
- **ECR as Helm Repository**: https://docs.aws.amazon.com/AmazonECR/latest/userguide/Amazon_ECR_OCI_helm_repositories.html
- **Flux HelmRepository API**: https://fluxcd.io/flux/components/source/helmrepositories/
- **Flux HelmRelease API**: https://fluxcd.io/flux/components/helm/helmreleases/

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
