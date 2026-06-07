# Deploy kb-mcp to k3s (high-level brief)

> Brief for the k3s/myks agent. The detailed myks/ytt/helm authoring is yours; this is the spec to execute against.
> Source app repo: `github.com/zebradil/know-mcp`. Reference files there: `deploy/docker/compose.yml`,
> `deploy/caddy/Caddyfile`, `docs/operations.md`, `docs/auth.md`, `crates/server/src/config.rs`.

## Goal

Deploy **kb-mcp** (a Rust MCP server) to k3s, publicly reachable over **IPv6** at `https://kb-mcp.zebradil.dev`, so that
**claude.ai** can add it as a Custom Connector: discover OAuth metadata, run the PKCE flow against the **existing
Authelia** instance, and call MCP tools end-to-end. Writes auto-push as git commits to the upstream KB repo.

**No new IdP, no new database.** The earlier draft of this plan bundled Logto (OAuth AS) + Postgres. That is dropped:
the cluster already runs **Authelia** at `auth.zebradil.dev` as an OIDC 1.0 provider, and it covers every requirement
claude.ai actually has. See "Why Authelia instead of Logto" below.

Image is published by the app repo's CI to `oci.zebradil.dev/zebradil/know-mcp` (Harbor). amd64 only. Pull directly —
**no kbld rewrite** (kbld targets ghcr/quay/registry.k8s.io; this image already lives in Harbor).

## Why Authelia instead of Logto

claude.ai custom connectors do **not** require Dynamic Client Registration. Since ~July 2025 the connector "Advanced
settings" accepts a manually pre-registered `client_id` (+ optional secret). So a static OIDC client is enough — which
is exactly Authelia's model.

Everything else claude.ai needs, Authelia 4.39 supports:

| claude.ai requirement                  | Authelia 4.39                                                          |
| -------------------------------------- | ---------------------------------------------------------------------- |
| OAuth 2.1 + PKCE S256                  | ✅ `require_pkce`, `pkce_challenge_method: S256`                       |
| OIDC discovery metadata                | ✅ `/.well-known/openid-configuration`                                 |
| JWT access token (for JWKS validation) | ✅ `access_token_signed_response_alg: RS256` (default `none` = opaque) |
| Resource indicators → `aud` (RFC 8707) | ✅ client `audience` + `requested_audience_mode`                       |
| JWKS endpoint                          | ✅ `https://auth.zebradil.dev/jwks.json`                               |
| Custom scopes                          | ✅ `identity_providers.oidc.scopes` (4.39+)                            |
| Client registration                    | ❌ no DCR (roadmap only) → use a **static client**                     |

Dropping Logto removes: a Node IdP (core+admin), **Postgres + its PVC**, the `kb-mcp-auth.zebradil.dev` host, Logto's
`SECRET_VAULT_KEK` / DB password / db-seed entrypoint, the `/console` first-run wizard, and Logto version/upgrade
surface. Net: **3 services → 1** (kb-mcp + the Authelia we already run).

## Architecture

```
claude.ai ──IPv6/443──> Traefik ──> kb-mcp (:8080)  /mcp + /.well-known/oauth-protected-resource
                            └──────> Authelia (existing)  /.well-known/openid-configuration, /jwks.json (OAuth AS, PKCE)
kb-mcp ──validates JWT via JWKS──> Authelia /jwks.json
kb-mcp ──git push──> upstream KB remote (SSH deploy key)
```

One new hostname, under the existing wildcard `*.zebradil.dev` cert (cert-manager / Cloudflare DNS-01) and the
IPv6-bound public entrypoint:

- `kb-mcp.zebradil.dev` — MCP transport (audience).

The authorization server is the **already-public** `auth.zebradil.dev` (issuer = `https://auth.zebradil.dev`, no path
suffix).

## myks layout (follow comentario + paperless prototypes)

- `prototypes/kb-mcp/`
  - `app-data.ytt.yaml` — image tag, storage, oauth (issuer/jwks), git branch, schema.
  - `ytt/all.ytt.yaml` — kb-mcp Deployment (initContainer + main), Service, PVCs.
  - `ytt/ingress.ytt.yaml` — unauthenticated, path-restricted route (see constraints).
  - `ytt/secret.ytt.yaml` — git deploy key + known_hosts Secret (sops refs).
- `envs/_apps/kb-mcp/`
  - `app-data.ytt.yaml` — env overrides + sops references + KB remote URL.
  - `static/0.sops.yaml` — git deploy key (private) + known_hosts.
- Register in `envs/env-data.alpha.yaml` `applications:` as `proto: kb-mcp`.
- Namespace: `kb-mcp`.
- **Authelia change** (`prototypes/authelia/helm/authelia.yaml`): add a static OIDC client + the custom `kb:*` scopes
  (see "Authelia client" below).

## Routing — CRITICAL

- `/mcp`, `/mcp/*`, `/.well-known/oauth-protected-resource` on the kb-mcp host must be **UNAUTHENTICATED at the edge —
  NO Authelia forwardAuth middleware.** claude.ai cannot pass an Authelia interstitial. Build a plain IngressRoute on
  the `web`/`websecure` entrypoints; do **not** attach `chain-authelia-auth`. (Authelia-as-IdP and
  Authelia-as-forwardAuth are the _same_ instance — the rule is simply: don't put the middleware on this route.) Model
  the allow shape on `deploy/caddy/Caddyfile`:
  - **kb-mcp host:** expose only `/mcp`, `/mcp/*`, `/.well-known/oauth-protected-resource`. Keep `/healthz`, `/readyz`,
    `/metrics` OFF the public edge (cluster-internal via the Service only).
- The OAuth endpoints are served by the existing public `auth.zebradil.dev` — no new auth host, no extra routing.
- Ensure `kb-mcp.zebradil.dev` resolves over IPv6 (AAAA). Wildcard `*.zebradil.dev` AAAA already exists; public
  entrypoint already binds node IPv6 (`envs/_apps/traefik/.../entrypoint-wrapper.sh`).

## kb-mcp Deployment

- Image: `oci.zebradil.dev/zebradil/know-mcp:<tag>` (pin a tag).
- `securityContext`: `runAsUser: 65532`, `runAsGroup: 65532`, `fsGroup: 65532` (image is debian nonroot uid 65532; PVCs
  must be writable by it).
- Env (mirror `deploy/docker/compose.yml`):
  - `KBMCP_LISTEN=0.0.0.0:8080`
  - `KBMCP_KB_PATH=/data/know`
  - `KBMCP_AUTH_DB_PATH=/data/state/auth.sqlite`
  - `KBMCP_INDEX_DB_PATH=/data/state/index.sqlite`
  - `KBMCP_LOG_FORMAT=json`
  - `KBMCP_GIT__AUTO_PUSH=true`, `KBMCP_GIT__REMOTE=origin`, `KBMCP_GIT__BRANCH=main`
  - `GIT_SSH_COMMAND=ssh -i /data/state/git-key -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/data/state/known_hosts`
  - `KBMCP_OAUTH__ENABLED=true`
  - `KBMCP_OAUTH__ISSUER=https://auth.zebradil.dev` ← **no path suffix**; Authelia's issuer is the root domain.
  - `KBMCP_OAUTH__AUDIENCE=https://kb-mcp.zebradil.dev/mcp`
  - `KBMCP_OAUTH__JWKS_URI=https://auth.zebradil.dev/jwks.json` ← **set explicitly**; Authelia serves JWKS at
    `/jwks.json`, not `<issuer>/.well-known/jwks.json`.
- Probes: liveness + readiness HTTP GET `/healthz` and `/readyz` on 8080.
- **initContainer** (same kb-mcp image — ships `git`, `openssh-client`, the `kb-mcp` binary). On every start it:
  1. installs the deploy key + known_hosts from the mounted Secret into `/data/state/` with `chmod 600` on the key (ssh
     refuses group/other-readable keys; the Secret mount can't satisfy ssh's ownership check directly, so we copy into
     the PVC owned by uid 65532). Re-copy each start picks up rotation.
  2. if the KB PVC is empty: `git clone <KB remote>` into `/data/know`, then run `kb-mcp init` against it. The server
     **crash-loops** against an uninitialized KB (needs git repo + `journal/ projects/ inbox/ templates/` dirs +
     `.gitignore` for `.kbmcp.lock.*` / `.kbmcp.tmp.*`).

## Authelia client (the only Authelia change)

Add to `identity_providers.oidc` in `prototypes/authelia/helm/authelia.yaml`:

- **Custom scopes** (sibling of `clients:`):
  ```yaml
  scopes:
    'kb:read': { claims: [] }
    'kb:write': { claims: [] }
    'kb:admin': { claims: [] }
  ```
- **A static public PKCE client**:
  - `client_id: kb-mcp` (public client → the id is not a secret).
  - `public: true`, `token_endpoint_auth_method: none`, `require_pkce: true`, `pkce_challenge_method: S256`.
  - `redirect_uris`: `https://claude.ai/api/mcp/auth_callback` **and** `https://claude.com/api/mcp/auth_callback`
    (future-proof).
  - `audience: [https://kb-mcp.zebradil.dev/mcp]`, `requested_audience_mode: explicit` (claude.ai passes `resource=` →
    `aud`).
  - `scopes`: `openid offline_access profile email groups kb:read kb:write kb:admin`.
  - `grant_types: [authorization_code, refresh_token]`, `response_types: [code]`.
  - `access_token_signed_response_alg: RS256` ← **critical**; without it Authelia mints an **opaque** access token and
    the MCP server cannot JWKS-validate it.
  - `authorization_policy: two_factor`, `pre_configured_consent_duration: 1y`.

No Authelia secret to manage (public client). The existing `default` RS256 JWK already in the config signs the JWT
access tokens.

## Storage (PVCs, RWO)

- `know` — KB git checkout.
- `state` — `auth.sqlite` + `index.sqlite` + `git-key` + `known_hosts`.

Notes: `index.sqlite` is **disposable** (reindexes from the git tree on boot); `auth.sqlite` (bearer-token DB) +
`git-key` are **precious** — back them up. (Postgres / `logto-pg` PVC from the old plan are gone.)

## Secrets (sops/age, existing ArgoCD Vault Plugin pattern)

`envs/_apps/kb-mcp/static/0.sops.yaml`:

- `git_key` — Git SSH deploy key (private half). Add the **public** half to the upstream KB repo as a **write** deploy
  key.
- `known_hosts` — pre-seeded via `ssh-keyscan -t ed25519,rsa github.com` and fingerprint-verified before trusting
  (`StrictHostKeyChecking=yes` fails closed).

(Logto DB password from the old plan is gone.)

## Manual post-deploy

1. Add the generated **public** deploy key (printed at provisioning time) to the KB repo (Settings → Deploy keys → Allow
   write access). Set the KB remote URL in `envs/_apps/kb-mcp/app-data.ytt.yaml` (`kbRepo`).
2. claude.ai → **Custom Connector** → URL `https://kb-mcp.zebradil.dev/mcp`.
3. In **Advanced settings** set **OAuth Client ID = `kb-mcp`** (leave secret empty — public client). Complete the
   browser OAuth flow against Authelia (login + 2FA + consent). The tool list should populate.

## Acceptance

- `curl https://kb-mcp.zebradil.dev/healthz` from inside the cluster → `ok` (path is not on the public edge).
- `curl https://kb-mcp.zebradil.dev/.well-known/oauth-protected-resource | jq .` →
  `resource = https://kb-mcp.zebradil.dev/mcp`, `authorization_servers = ["https://auth.zebradil.dev"]`.
- An `inbox.capture` issued from claude.ai lands as a commit on the upstream KB remote within seconds.

## Gotchas

- **Opaque vs JWT**: Authelia emits a JWT access token only when the client sets
  `access_token_signed_response_alg: RS256`. Otherwise the token is opaque and the MCP server's JWKS validation fails.
- **`iss`/`aud` exact match**: issuer is `https://auth.zebradil.dev` (no trailing slash, no `/oidc`). Audience must be
  byte-exact `https://kb-mcp.zebradil.dev/mcp`.
- **JWKS path**: Authelia's is `/jwks.json`, not `<issuer>/.well-known/jwks.json`.
- **RFC 8707 round-trip (verify in practice)**: confirm Authelia stamps `aud=https://kb-mcp.zebradil.dev/mcp` into the
  JWT when claude.ai sends `resource=…`. Main unknown — test with the echo-server connector flow before trusting it
  end-to-end.
- **Scopes**: the `kb:*` scopes must be both defined globally (`oidc.scopes`) and listed on the client, else
  `-32001 forbidden`.
- **Redirect URI**: Authelia rejects any non-whitelisted `redirect_uri`. Confirm claude.ai's exact callback at connect
  time (`…/api/mcp/auth_callback`).
- **SSH key perms**: the deploy key must be `chmod 600` and owned by uid 65532 — hence the initContainer copy into the
  PVC instead of using the Secret mount directly.
