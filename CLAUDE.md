# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a GitOps homelab repository managing a k3s Kubernetes cluster using [myks](https://github.com/mykso/myks) — a
configuration management tool built on top of ytt (Carvel), Helm, and Vendir. ArgoCD handles continuous delivery from
the rendered manifests.

## Tool Setup

Tools are managed via `mise` (`.mise.toml`). Install them with `mise install`. The primary tools are:

- `myks` — renders Kubernetes manifests
- `task` — task runner (Taskfile.yaml)
- `sops` / `age` — secret encryption/decryption
- `kubeconform` — Kubernetes manifest validation
- `helm`, `yq`, `argocd`

A Nix flake (`flake.nix`) and direnv (`.envrc`) are also available for environment setup.

## Key Commands

```bash
# Render all changed applications
myks render

# Render all applications in all environments
myks render ALL

# Render specific environments/apps
myks render alpha argocd

# Clean up cache after rendering
myks cleanup --cache

# Show filtered git diff (ignores noisy version-only changes)
task git:diff -- origin/main...HEAD

# Show filtered git diff for a PR
task git:diff:pr -- <PR_NUMBER> rendered
```

## Architecture

### myks Configuration Model

myks uses a **prototype + environment overlay** pattern:

- **`prototypes/<app>/`** — Reusable application blueprints. Each prototype can contain `helm/`, `ytt/`, `vendir/`, and
  `app-data.ytt.yaml`. These define the base configuration for an application.
- **`envs/_apps/<app>/`** — Environment-specific overrides per application. Each app directory contains ytt overlays,
  value files, and image policy configs that are merged on top of the prototype.
- **`envs/_env/`** — Global overlays applied to all apps in the environment (common annotations, ArgoCD image updater
  policies, etc.).
- **`rendered/`** — Output directory where myks writes final Kubernetes manifests. These are committed and picked up by
  ArgoCD.

### Shared Libraries (`lib/`)

- `lib/overlay-matchers.star` — Starlark functions for matching Kubernetes resources in ytt overlays
- `lib/secrets.star` — Starlark helpers for sops-encrypted secrets
- `lib/util.star` — General utilities
- `lib/traefik.lib.yaml` / `lib/grafana.lib.yaml` — ytt library configs for Traefik ingress and Grafana

### Environment Data

Environment variables/values flow through:

- `envs/env-data.values.yaml` — Shared values (base domain, host addresses, node names, etc.)
- `envs/env-data.schema.yaml` — ytt schema defining expected structure
- `envs/env-data.alpha.yaml` — Alpha environment overrides

### Secret Management

Secrets are encrypted with sops using age keys. The `.sops.yaml` defines which keys can decrypt which files. When
authoring secrets, use `sops` to encrypt files before committing.

### CI/CD

**`.github/workflows/render-myks.yaml`** — On every PR and push to main:

1. Detects changed apps using git diff (Nx Smart Mode for base/head commit detection)
2. Runs `myks render` only for affected apps
3. Auto-commits rendered output back to the branch (signed commit)
4. Sets a commit status for the PR check

**`.github/workflows/auto-approve.yaml`** — Auto-approves PRs that only contain insignificant changes (e.g., version
bumps with no meaningful manifest diff).

### Plugins (`plugins/`)

Custom myks plugins loaded automatically via `.myks.yaml`. `argo-refresh` triggers ArgoCD app refresh after rendering.

## Adding a New Application

1. Create a prototype in `prototypes/<app>/` with at minimum an `app-data.ytt.yaml`
2. Create an app override in `envs/_apps/<app>/` with environment-specific values
3. Run `myks render ALL <app>` to test rendering
4. Commit both the source and rendered output

## Linting

```bash
yamllint .
```

YAML lint rules are configured in `.yamllint.yaml`.
