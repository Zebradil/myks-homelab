# Myks homelab

This repository stores myks configuration and is source of truth for my homelab based on [k3s](https://k3s.io/).

## Setup

### ArgoCD

ArgoCD is used to deploy and manage applications on the cluster.
It is needed to be manually installed on a fresh cluster.

```zsh
#!/bin/zsh

cd rendered/envs/alpha/argocd

# First, create the CRDs, then the rest.
CRDs=customresourcedefinition-*
kubectl create -f $~CRDs
kubectl create -f ^$~CRDs
```

Give it a few minutes to start up.

ArgoCD Vault Plugin is configured as a Content Management Plugin.
It uses sops to decrypt secrets, if there are any.

To finish its setup, the private key needs to be set in the cluster.

```zsh
# Patch the secret to set age private key.
# ArgoCD will use it to decrypt sops secrets.
kubectl patch secret sops-age-key \
  -n argocd \
  -p '{"stringData": {"key": "'$(systemd-ask-password -n)'"}}'
```
