# Deploy kb-mcp to k3s (high-level brief)

> Brief for the k3s/myks agent. The detailed myks/ytt/helm authoring is yours;
> this is the spec to execute against. Source app repo:
> `github.com/zebradil/know-mcp`. Reference files there:
> `deploy/docker/compose.yml`, `deploy/caddy/Caddyfile`, `docs/operations.md`,
> `docs/auth.md`, `crates/server/src/config.rs`.

## Goal

Deploy **kb-mcp** (a Rust MCP server) + **Logto** (OAuth 2.1 IdP) + **Postgres**
to k3s, publicly reachable over **IPv6** at `https://kb-mcp.zebradil.dev`, so that
**claude.ai** can add it as a Custom Connector: discover OAuth metadata,
Dynamic-Client-Register against Logto, run the PKCE flow, and call MCP tools
end-to-end. Writes auto-push as git commits to the upstream KB repo.

Image is published by the app repo's CI to `oci.zebradil.dev/zebradil/know-mcp`
(Harbor). amd64 only. Pull directly — **no kbld rewrite** (kbld targets
ghcr/quay/registry.k8s.io; this image already lives in Harbor).

## Architecture

```
claude.ai ──IPv6/443──> Traefik ──> kb-mcp (:8080)  /mcp + /.well-known/oauth-protected-resource
                            └──────> Logto  (:3001)  /oidc (OAuth AS, DCR)
kb-mcp ──validates JWT via JWKS──> Logto /oidc/jwks
kb-mcp ──git push──> upstream KB remote (SSH deploy key)
Logto  ──> Postgres
```

Two hostnames, both under the existing wildcard `*.zebradil.dev` cert
(cert-manager / Cloudflare DNS-01) and the IPv6-bound public entrypoint:

- `kb-mcp.zebradil.dev` — MCP transport (audience).
- `kb-mcp-auth.zebradil.dev` — Logto authorization server (issuer = `…/oidc`).

## myks layout (follow paperless + harbor prototypes)

- `prototypes/kb-mcp/`
  - `app-data.ytt.yaml` — image tag, hostnames, oauth values, schema.
  - `vendir/values.ytt.yaml` — Bitnami `postgresql` chart source (paperless pattern).
  - `helm/postgresql.yaml` — Postgres overrides.
  - `ytt/all.ytt.yaml` — kb-mcp + Logto Deployments, Services, PVCs.
  - `ytt/ingress.ytt.yaml` — routes (see constraints below).
- `envs/_apps/kb-mcp/`
  - `app-data.ytt.yaml` — env overrides + sops references.
  - `static/0.sops.yaml` — Logto DB password, git deploy key (private), known_hosts.
- Register in `envs/env-data.alpha.yaml` `applications:` as `proto: kb-mcp`.
- Namespace: `kb-mcp`.

## Routing — CRITICAL

- `/mcp`, `/mcp/*`, `/.well-known/oauth-protected-resource` and the **entire Logto
  host must be UNAUTHENTICATED at the edge — NO Authelia middleware.** claude.ai
  cannot pass an Authelia interstitial. Use the plain `web` route group, not the
  Authelia-protected one (the echo-server connector test proves an unprotected
  web route works). Model the allow/deny shape on `deploy/caddy/Caddyfile`:
  - **kb-mcp host:** expose only `/mcp`, `/mcp/*`,
    `/.well-known/oauth-protected-resource`. Keep `/healthz`, `/readyz`,
    `/metrics` OFF the public edge (cluster-internal only).
  - **Logto host:** expose root + `/oidc*`; **block `/console*` and `/api*`**
    publicly (admin via `kubectl port-forward`).
- Ensure both hostnames resolve over IPv6 (AAAA). Wildcard `*.zebradil.dev` AAAA
  already exists; public entrypoint already binds node IPv6
  (`envs/_apps/traefik/.../entrypoint-wrapper.sh`).

## kb-mcp Deployment

- Image: `oci.zebradil.dev/zebradil/know-mcp:<tag>` (pin a tag).
- `securityContext`: `runAsUser: 65532`, `runAsGroup: 65532`, `fsGroup: 65532`
  (image is debian nonroot uid 65532; PVCs must be writable by it).
- Env (mirror `deploy/docker/compose.yml`):
  - `KBMCP_LISTEN=0.0.0.0:8080`
  - `KBMCP_METRICS_LISTEN=0.0.0.0:9090` — only if Prometheus scrapes cross-pod;
    otherwise leave the localhost default and scrape via a sidecar.
  - `KBMCP_KB_PATH=/data/know`
  - `KBMCP_AUTH_DB_PATH=/data/state/auth.sqlite`
  - `KBMCP_INDEX_DB_PATH=/data/state/index.sqlite`
  - `KBMCP_LOG_FORMAT=json`
  - `KBMCP_GIT__AUTO_PUSH=true`, `KBMCP_GIT__REMOTE=origin`, `KBMCP_GIT__BRANCH=main`
  - `GIT_SSH_COMMAND=ssh -i /data/state/git-key -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/data/state/known_hosts`
  - `KBMCP_OAUTH__ENABLED=true`
  - `KBMCP_OAUTH__ISSUER=https://kb-mcp-auth.zebradil.dev/oidc`
  - `KBMCP_OAUTH__AUDIENCE=https://kb-mcp.zebradil.dev/mcp`
  - `KBMCP_OAUTH__JWKS_URI=https://kb-mcp-auth.zebradil.dev/oidc/jwks` ← **set
    explicitly**; the auto-derived `<issuer>/.well-known/jwks.json` 404s on Logto.
- Probes: liveness + readiness HTTP GET `/healthz` and `/readyz` on 8080.
- **initContainer** (same kb-mcp image — ships `git`, `openssh-client`, the
  `kb-mcp` binary): if the KB PVC is empty, `git clone <KB remote>` into
  `/data/know`, then run `/usr/local/bin/kb-mcp init` against it. The server
  **crash-loops** against an uninitialized KB (needs git repo + `journal/
  projects/ inbox/ templates/` dirs + `.gitignore` for `.kbmcp.lock.*` /
  `.kbmcp.tmp.*`). Mount the SSH deploy key + known_hosts for the clone.

## Logto + Postgres

- Logto image `svhd/logto:1.36.0` (pin; never `:latest`).
- Entrypoint seed trick (from compose.yml — a fresh DB crash-loops without it):
  `sh -c "npm run cli db seed -- --swe && npm run start"`.
- Env: `ENDPOINT=https://kb-mcp-auth.zebradil.dev`, `PORT=3001`,
  `DB_URL=postgres://logto:<sops pw>@<pg svc>:5432/logto`.
- Postgres: Bitnami `postgresql` chart (paperless pattern) or a small Deployment;
  PVC on `local-path` or `synology-iscsi-storage`. Password from sops.

## Storage (PVCs, RWO)

- `know` — KB git checkout.
- `state` — `auth.sqlite` + `index.sqlite` + `git-key`.
- `logto-pg` — Postgres data.

Notes: `index.sqlite` is **disposable** (reindexes from the git tree on boot);
`auth.sqlite` (bearer-token DB) + `git-key` are **precious** — back them up.

## Secrets (sops/age, existing ArgoCD Vault Plugin pattern)

- Logto DB password.
- Git SSH deploy key (private half) — add the **public** half to the upstream KB
  repo as a **write** deploy key.
- `known_hosts` — pre-seed via `ssh-keyscan -t ed25519,rsa -H <KB git host>` and
  verify the fingerprint before trusting (`StrictHostKeyChecking=yes` fails closed).

## Manual post-deploy (mirror app repo `docs/operations.md` §8)

1. `kubectl port-forward` Logto, open `/console`, run the first-run wizard.
2. Create an **API resource** with identifier `https://kb-mcp.zebradil.dev/mcp`
   (**byte-exact** = audience); add scopes `kb:read`, `kb:write`, `kb:admin`.
3. Enable **Dynamic Client Registration** with an admin-gated registration token.
4. claude.ai → **Custom Connector** → `https://kb-mcp.zebradil.dev/mcp`; complete
   the browser OAuth flow; the tool list should populate.

## Acceptance

- `curl https://kb-mcp.zebradil.dev/healthz` → `ok` (from inside cluster; the path
  is not on the public edge).
- `curl https://kb-mcp.zebradil.dev/.well-known/oauth-protected-resource | jq .` →
  `resource = https://kb-mcp.zebradil.dev/mcp`,
  `authorization_servers = ["https://kb-mcp-auth.zebradil.dev/oidc"]`.
- An `inbox.capture` issued from claude.ai lands as a commit on the upstream KB
  remote within seconds.

## Gotchas (from app repo test-plan Layer 3)

- **Opaque vs JWT**: Logto needs `resource=<audience>` on token mint to emit a
  JWT (claude.ai supplies it via the resource param). Audience must match exactly.
- **`iss`/`aud` exact match**: no trailing slash after `/oidc`.
- **JWKS path**: must be Logto's `/oidc/jwks`, not the default
  `<issuer>/.well-known/jwks.json` → else `unknown_token` + `fetching JWKS`.
- **Scopes**: granted to the client AND requested, else `-32001 forbidden`.
