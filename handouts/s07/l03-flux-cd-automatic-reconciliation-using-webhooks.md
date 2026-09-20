---
title: "Flux CD automatic reconciliation using webhooks"
kicker: "FLUX CD · SECTION 7 · LECTURE 3"
description: "Expose Flux's notification receiver as a webhook endpoint and trigger instant reconciliation from GitLab or GitHub pushes, instead of waiting on the poll interval."
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Flux CD automatic reconciliation using webhooks

*Section 7, Lecture 3 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Why polling has a lag, and how a **Receiver** removes it by reacting to Git events instead of waiting for the interval
- How to create a Receiver and secure it with an HMAC token stored in a Secret
- How to expose the receiver's endpoint outside the cluster and read the generated webhook path from its status
- How to register that webhook with GitLab or GitHub
- Why many teams keep polling as a safety net even after webhooks are wired up

---

## Polling vs. pushing

Up to this point, every change you wanted Flux to pick up immediately needed a manual `flux reconcile`. Flux's `GitRepository` source still polls on its own interval in the background, so a change always lands eventually — but "eventually" can be minutes away.

The notification controller closes that gap with a **Receiver**: a Kubernetes object that stands up a small HTTP service inside the cluster. You hand its URL to your Git provider as a **webhook**. When something happens on the repository — a push, a tag, a comment — the provider fires an HTTP request at that URL with a payload describing the event. The receiver reacts by triggering reconciliation on the specific resources you told it to watch, instead of Flux sitting around until the next poll.

Because that URL accepts arbitrary requests, anyone who obtains it could trigger reconciliation on demand. Flux defends against this with a shared secret: the Git provider sends a token in the request header, the receiver compares it to a token you stored in a Secret, and it silently discards anything that doesn't match.

---

## The Receiver resource

Create a directory for the webhook manifests alongside your other Flux sources, then define the receiver:

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1
kind: Receiver
metadata:
  name: gitlab-receiver
  namespace: flux-system
spec:
  type: gitlab
  events:
    - "Push Hook"
    - "Tag Push Hook"
  secretRef:
    name: receiver-token
  resources:
    - apiVersion: source.toolkit.fluxcd.io/v1
      kind: GitRepository
      name: flux-system
```

> **Since this video was recorded:** the notification API group has moved on.
> `Receiver` reached general availability at `notification.toolkit.fluxcd.io/v1`
> (it was `v1beta2` at the time of recording). The manifest above is the
> current, stable form.

A few fields worth pausing on:

- **`spec.type`** — the platform sending events. Flux natively understands `gitlab`, `github`, `gitea`, and `bitbucket-server`, meaning it can parse each platform's payload well enough to filter by event type. For platforms it doesn't understand natively (a container registry, for example), use `type: generic` or `generic-hmac` and filter events on the sender's side instead — the receiver will react to every message it gets.
- **`spec.events`** — which event types to act on. The exact names (`Push Hook`, `Tag Push Hook`, and so on) come from the platform's own webhook documentation, not from Flux.
- **`spec.secretRef`** — the Secret holding the HMAC token (below).
- **`spec.resources`** — the Flux objects to reconcile when a matching event arrives. This is a list, so one receiver can drive several `GitRepository`, `Kustomization`, `HelmRelease`, `Bucket`, `OCIRepository`, `ImageRepository`, or `ImageUpdateAutomation` objects.

## The HMAC token Secret

Generate a random token any way you like — a chained shell command works fine for a lab:

```bash
head -c 12 /dev/urandom | shasum | cut -d ' ' -f1
```

Copy the value, then store it in a Secret named to match `secretRef.name` above:

```bash
kubectl -n flux-system create secret generic receiver-token \
  --from-literal=token=<GENERATED_TOKEN>
```

`<GENERATED_TOKEN>` is a placeholder — substitute the string the command above printed. If you've covered sealed secrets, GPG, Age, or Vault elsewhere in this course, this is exactly the kind of value you'd want encrypted before it reaches Git; for a lab, creating it imperatively and keeping it out of source control is enough.

Commit and push the receiver manifest, then reconcile so Flux picks it up:

```bash
git add webhooks/
git commit -m "Add GitLab receiver"
git push
flux reconcile kustomization flux-system --with-source
```

---

## Exposing the receiver endpoint

Creating the Receiver makes the notification controller stand up a `ClusterIP` Service named `webhook-receiver` in `flux-system`, listening on port 80 and forwarding to the controller pod on port 9292. `ClusterIP` means it's only reachable from inside the cluster — you need to get an external URL pointed at it before any Git provider can call it.

| Where you run | How to expose it |
|---|---|
| A cloud-managed cluster | Change the Service to `type: LoadBalancer`, or route an Ingress through the cloud provider's own load balancer |
| A cluster with an Ingress controller already installed | Create an `Ingress` object routing to `webhook-receiver:80` |
| A local cluster with no public IP (KinD, a home lab) | Add a tunnel — for example ngrok — in front of the Ingress |

An Ingress is the more portable option, since it works the same way whether or not you're behind a tunnel:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webhook-receiver
  namespace: flux-system
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: webhook-receiver
            port:
              number: 80
```

Point the Ingress at port **80** — where the Service listens — not port 9292, which is an internal detail of how the Service reaches the controller pod. Commit, push, and reconcile as before.

If you're running on a cluster with no public IP, a tunnel gives you a temporary public hostname that forwards to your Ingress:

```bash
ngrok http 80
```

`ngrok` prints a forwarding URL that looks like `https://<RANDOM_SUBDOMAIN>.ngrok-free.app`. Treat that as a placeholder — it's generated fresh (and on the free tier, it changes every time you restart the tunnel), so copy the URL your own session prints rather than reusing one from a previous run or from this handout.

---

## Reading the generated webhook path

The receiver doesn't use a URL you choose — Flux generates one deterministically from the receiver's name and token, and publishes it on the object's status:

```bash
kubectl -n flux-system get receiver gitlab-receiver -o jsonpath='{.status.webhookPath}'
```

`kubectl describe` shows the same value with more context:

```bash
kubectl -n flux-system describe receiver gitlab-receiver
```

The path this prints — something like `/hook/<GENERATED_HASH>` — is not a full URL by itself. Append it to whatever public hostname now points at the receiver Service (your Ingress host, load balancer hostname, or ngrok forwarding URL) to get the address you'll register with your Git provider, for example:

```
https://<YOUR_PUBLIC_HOSTNAME>/hook/<GENERATED_HASH>
```

Both placeholders come from commands you already ran: the hostname from your Ingress/load balancer/tunnel, and the hash from `.status.webhookPath`.

---

## Registering the webhook

### GitLab

1. Open your repository on GitLab and go to **Settings → Webhooks**
2. Under **URL**, paste the full address you assembled above
3. Under **Secret token**, paste the token you generated for the Secret
4. Under **Trigger**, check the event types matching what you listed in `spec.events` — **Push events** and **Tag push events** for the manifest above
5. Optionally enable **SSL verification** — safe to leave on if your endpoint serves HTTPS (a tunnel like ngrok does by default)
6. Save, then use GitLab's **Test** button to send a sample push event and confirm you get a `200 OK` back before relying on a real commit

### GitHub

GitHub's webhook UI asks for the same three pieces of information under **Settings → Webhooks → Add webhook**:

- **Payload URL** — the same full address
- **Content type** — `application/json`
- **Secret** — the same token

Under **Which events would you like to trigger this webhook?**, select the individual events you want (**Pushes**, for example) rather than "Send me everything." Set `spec.type: github` on the Receiver so Flux can parse GitHub's payload and filter accordingly.

---

## Testing it end to end

Change something Flux is watching — a replica count on a Deployment works well for a visible result — then commit and push:

```bash
git add .
git commit -m "Trigger webhook reconciliation"
git push
```

Instead of running `flux reconcile`, just check the cluster directly:

```bash
kubectl get pods -n default
```

If the webhook is wired correctly, the change shows up without you triggering anything by hand — the push itself was the trigger.

> **Note:** a receiver reacting immediately is not automatically what you want
> in every environment. Many teams deliberately keep the polling interval as
> the only trigger in production, so there's a grace period between a merge
> landing on the main branch and it reaching the cluster — room to catch a
> bad merge before it's live.

---

## Further reading

- [Flux Receiver reference](https://fluxcd.io/flux/components/notification/receiver/)
- [Flux notification controller overview](https://fluxcd.io/flux/components/notification/)
- [Kubernetes Ingress concepts](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [GitLab webhook events](https://docs.gitlab.com/user/project/integrations/webhook_events/)
- [GitHub webhooks documentation](https://docs.github.com/en/webhooks)
- [ngrok documentation](https://ngrok.com/docs)

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
