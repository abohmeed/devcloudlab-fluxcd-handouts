---
title: "Sending Flux CD notifications to Slack"
kicker: "FLUX CD · SECTION 7 · LECTURE 2"
description: "This lecture demonstrates how to configure Flux CD's notification controller to send real-time alerts to Slack whenever your cluster state changes. By integrating Flux CD"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Sending Flux CD notifications to Slack

*Section 7, Lecture 2 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Create a Slack app with a bot token and an incoming webhook for Flux CD notifications
- Configure a Provider resource that tells Flux CD how to reach your Slack channel
- Configure an Alert resource that triggers on Kustomization, GitRepository, and HelmRelease events
- Filter notifications by event severity and by resource name using inclusion and exclusion lists

## Overview

This lecture demonstrates how to configure Flux CD's notification controller to send real-time alerts to Slack whenever your cluster state changes. By integrating Flux CD with Slack, you can monitor deployments, Git repository syncs, and Helm releases without constantly checking your cluster manually.

The notification controller works through two key resources:

- **Provider:** Defines *how* notifications are sent (Slack in this case), including the webhook URL and authentication.
- **Alert:** Defines *what* events trigger notifications (Kustomization, GitRepository, HelmRelease) and at what severity level.

Flux CD supports many notification platforms out of the box (Slack, Microsoft Teams, Telegram) and generic webhooks for custom integrations.

---

## Prerequisites

- A working Kubernetes cluster with Flux CD installed (v2.0 or later)
- A Slack workspace where you have permission to create apps and webhooks
- `kubectl` configured to access your cluster
- `flux` CLI installed locally
- A Git repository connected to your Flux cluster

---

## Step-by-Step Instructions

### 1. Create a Slack App and Webhook

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Click **Create an App** → **Blank app** (earlier versions of this dialog called it **From scratch**)
3. Name your app (e.g., `fluxcd-notifications`)
4. Select your Slack workspace
5. Navigate to **OAuth & Permissions** in the left sidebar
6. Under **Bot Token Scopes**, click **Add an OAuth Scope** and select `chat:write`
7. Scroll to the top and copy your **Bot User OAuth Token** (starts with `xoxb-`)
8. Go to **Incoming Webhooks** in the left sidebar
9. Toggle **Activate Incoming Webhooks** to **On**
10. Click **Add New Webhook to Workspace**
11. Select the channel where you want notifications (or create a new one, e.g., `#flux-cd-notifications`)
12. Copy the **Webhook URL** that is generated

You now have two critical values:
- **Bot User OAuth Token** (e.g., `xoxb-<your-bot-token>`)
- **Webhook URL** (e.g., `https://hooks.slack.com/services/<T-ID>/<B-ID>/<secret>`)

### 2. Create a Kubernetes Secret

Store the OAuth token as a Kubernetes secret in the `flux-system` namespace:

```bash
kubectl create secret generic slack-secret \
  --from-literal=token=xoxb-YOUR_OAUTH_TOKEN_HERE \
  -n flux-system
```

Replace `xoxb-YOUR_OAUTH_TOKEN_HERE` with your actual Bot User OAuth Token.

Verify the secret was created:

```bash
kubectl get secret slack-secret -n flux-system
```

### 3. Create the Slack Provider

Create a `slack/` directory in your Git repository and define the notification provider:

```bash
mkdir -p slack
cd slack
```

Create a file named `slack-provider.yaml`:

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: flux-cd-notifications
  address: https://hooks.slack.com/services/<T-ID>/<B-ID>/<secret>
  secretRef:
    name: slack-secret
```

**What this does:**
- `type: slack` — Tells Flux to use Slack as the notification platform
- `channel: flux-cd-notifications` — The Slack channel to send messages to
- `address` — The incoming webhook URL from Step 1
- `secretRef` — References the Kubernetes secret containing the OAuth token

Alternatively, generate this with the `flux` CLI:

```bash
flux create alert-provider slack \
  --type slack \
  --channel flux-cd-notifications \
  --address 'https://hooks.slack.com/services/<T-ID>/<B-ID>/<secret>' \
  --secret-ref slack-secret \
  --export > slack-provider.yaml
```

### 4. Create the Alert Resource

Define which Flux CD events trigger notifications:

```bash
cat > reconciliation-alert.yaml << 'EOF'
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: flux-system
  namespace: flux-system
spec:
  eventSeverity: info
  summary: "Flux CD notification"
  eventMetadata:
    env: "staging"
    cluster: "flux-cd-notification"
  eventSources:
  - kind: Kustomization
    name: '*'
  - kind: GitRepository
    name: '*'
  - kind: HelmRelease
    name: '*'
  providerRef:
    name: slack
EOF
```

**What this does:**
- `eventSeverity: info` — Send notifications for all events (info, warning, error). Use `error` for only failures.
- `summary` — Optional short description included in Slack messages (max 255 characters). Note that `.spec.summary` is **deprecated** at `v1beta3`: it still works, but the notification controller logs `specifying an alert summary with '.spec.summary' is deprecated, use '.spec.eventMetadata.summary' instead` on every event it sends. In new manifests, prefer a `summary` key inside `eventMetadata`
- `eventMetadata` — Key-value pairs sent with each notification (useful for filtering or routing). They are rendered as fields on the Slack message
- `eventSources` — Which resources to monitor. The `*` (wildcard) means all instances of that kind
- `providerRef` — Links to the Slack provider created above

Commit both files to your repository:

```bash
cd ..
git add slack/
git commit -m "Add Slack notification configuration"
git push
```

### 5. Reconcile Flux CD

Apply the new resources to your cluster:

```bash
flux reconcile kustomization flux-system --with-source
```

`flux reconcile` prints `✔ fetched revision main@sha1:…` and then
`✔ applied revision main@sha1:…`. It does not print a health summary.

One thing to check if nothing arrives: Flux only builds the path it was
bootstrapped with. If your cluster was bootstrapped with, say, `--path=./clusters/staging`,
then manifests committed at the repository root are never applied — and the
reconcile above still reports success, because the path it *does* watch is
healthy. Confirm with:

```bash
kubectl get kustomization flux-system -n flux-system -o jsonpath='{.spec.path}'
```

Verify the alert was created:

```bash
flux get alerts -n flux-system
```

You should see output similar to:

```
NAME          SUSPENDED   READY   MESSAGE
flux-system   False       True    Alert is Ready
```

### 6. Test the Setup

Create a test Kubernetes resource to trigger a notification:

```bash
mkdir -p nginx
cd nginx
```

Create `deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: default
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: web
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
```

Commit and push:

```bash
cd ..
git add nginx/
git commit -m "Add nginx deployment for testing"
git push
```

Reconcile:

```bash
flux reconcile kustomization flux-system --with-source
```

Check your Slack channel. You should see messages like:

- GitRepository sync event (detecting the new files pushed)
- Kustomization reconciliation event (applying the nginx deployment)
- Deployment creation event

Each message includes:
- The event source (e.g., GitRepository, Kustomization)
- The timestamp
- The event severity
- Any custom metadata you defined

The metadata arrives as fields under the message body. The title is the source
object in lower case with a dot before its namespace, and the body is the event
message itself, so the Kustomization event that applies the deployment above
looks like this in the channel:

```
kustomization/flux-system.flux-system

Deployment/default/nginx created

summary   Flux CD notification
revision  main@sha1:8e0895708b160a13da5c112e5f74c239a5f61134
cluster   flux-cd-notification
env       staging
```

The four fields come from a map, so their order changes from one message to the
next. The revision is the full commit sha, not the short one Git printed.

### 7. Fine-Tune Notifications (Optional)

You can filter notifications using inclusion and exclusion lists based on regular expressions:

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: flux-system
  namespace: flux-system
spec:
  eventSeverity: info
  eventSources:
  - kind: Kustomization
    name: '*'
  - kind: GitRepository
    name: '*'
  providerRef:
    name: slack
  # Only send notifications for these resources (inclusion)
  inclusionList:
  - "flux-system"
  - "production-.*"
  # Never send notifications matching these patterns (exclusion takes precedence)
  exclusionList:
  - ".*-dev"
  - "test-.*"
```

---

## Common Commands

| Command | Purpose |
|---|---|
| `flux get alerts -n flux-system` | List all alerts in the flux-system namespace |
| `flux get alert-providers -n flux-system` | List all notification providers |
| `kubectl get secret slack-secret -n flux-system -o yaml` | View the Slack secret (values are base64-encoded) |
| `flux reconcile alert flux-system -n flux-system` | Manually trigger an alert reconciliation |
| `kubectl logs -n flux-system deployment/notification-controller -f` | View notification controller logs |

---

## Complete Manifests

### slack-provider.yaml

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: flux-cd-notifications
  address: https://hooks.slack.com/services/<T-ID>/<B-ID>/<secret>
  secretRef:
    name: slack-secret
```

### reconciliation-alert.yaml

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: flux-system
  namespace: flux-system
spec:
  eventSeverity: info
  summary: "Flux CD notification"
  eventMetadata:
    env: "staging"
    cluster: "flux-cd-notification"
  eventSources:
  - kind: Kustomization
    name: '*'
  - kind: GitRepository
    name: '*'
  - kind: HelmRelease
    name: '*'
  providerRef:
    name: slack
```

---

## API Versions — Important

This lecture uses `notification.toolkit.fluxcd.io/v1beta3` for Alert and Provider resources. Note that in the same API group, Receiver is stable at `v1`. Do not assume all resources in an API group use the same version. If you get an error like "no matches for kind Alert", run `kubectl api-resources --api-group=notification.toolkit.fluxcd.io` on your cluster to see which version each resource actually supports.

---

## Troubleshooting

**No messages in Slack:**
1. Check the alert status: `flux get alerts -n flux-system`
2. Review notification controller logs: `kubectl logs -n flux-system deployment/notification-controller -f`
3. Verify the webhook URL is accessible and correct
4. Ensure the secret contains the correct token: `kubectl get secret slack-secret -n flux-system -o jsonpath='{.data.token}' | base64 -d`
5. Check that the Slack app is still installed in your workspace and the webhook is active

**Alert not reconciling:**
1. Check for YAML syntax errors: `kubectl apply -f slack-provider.yaml --dry-run=client`
2. Verify the provider name matches the `providerRef` in the alert
3. Review Flux events: `flux logs --all-namespaces --follow`

**Too many notifications:**
- Adjust `eventSeverity` from `info` to `error` to only alert on failures
- Use `inclusionList` and `exclusionList` to filter which resources send notifications

---

## Further Reading

- [Flux CD Notification Controller Documentation](https://fluxcd.io/flux/components/notification/)
- [Slack Incoming Webhooks API](https://api.slack.com/messaging/webhooks)
- [Flux CD Event Sources](https://fluxcd.io/flux/components/notification/alerts/)
- [Notification Providers](https://fluxcd.io/flux/components/notification/provider/)
- [Flux CD — Setting Up Alerts (Notifications)](https://fluxcd.io/flux/monitoring/alerts/)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
