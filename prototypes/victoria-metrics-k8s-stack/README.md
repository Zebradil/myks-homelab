# victoria-metrics-k8s-stack

Kubernetes monitoring for the homelab k3s cluster: metric scraping, two-tier storage, alerting, and Grafana dashboards —
deployed via the
[victoria-metrics-k8s-stack](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-k8s-stack)
Helm chart (v0.67.x) plus ytt overlays.

## Components

| Component                 | Kind             | Source    | Role                                                                                      |
| ------------------------- | ---------------- | --------- | ----------------------------------------------------------------------------------------- |
| **vmagent**               | `VMAgent`        | Helm      | Scrapes all cluster targets; dual-writes to both storage clusters                         |
| **vmcluster `vmks`**      | `VMCluster`      | Helm      | Short-term storage (30d, all metrics); vminsert only, no vmselect                         |
| **vmcluster `vmks-long`** | `VMCluster`      | ytt clone | Long-term storage (5y, filtered metrics); vminsert + vmselect                             |
| **vmalert**               | `VMAlert`        | Helm      | Evaluates alerting/recording rules; reads and writes via vmselect/vminsert                |
| **vmalertmanager**        | `VMAlertManager` | Helm      | Routes and deduplicates alerts; sends Telegram notifications via sops-encrypted bot token |
| **Grafana**               | `Deployment`     | Helm      | Dashboards; datasource points at `vmselect-vmks-long`                                     |
| **node-exporter**         | `DaemonSet`      | Helm      | Node-level metrics                                                                        |
| **kube-state-metrics**    | `Deployment`     | Helm      | Kubernetes object state metrics                                                           |

## Retention tiers

Two VMCluster resources share the same namespace and are managed together:

- **`vmks` (30d):** receives all scraped metrics. Exists for fast short-term queries and as the primary
  alerting/recording rule backend.
- **`vmks-long` (5y):** receives only a filtered subset (currently `airgradient_.*` — air quality sensor data). Provides
  long-term history for metrics worth keeping beyond a month.

## Write path

```
vmagent
  ├── → vminsert-vmks          (all metrics, 30d tier)
  └── → vminsert-vmks-long     (airgradient_.* only, 5y tier)
```

The filtered second write is configured via `vmagent.additionalRemoteWrites` + `inlineUrlRelabelConfig` in
`helm/vmks.yaml`. The Helm chart's `vm.write.endpoint` helper auto-generates the primary remoteWrite URL (vminsert-vmks)
because `vmcluster.spec.vminsert` is enabled; `external.vm.write.url` is intentionally absent — the chart ignores it
whenever a managed vminsert is available.

## Read path

```
Grafana / vmalert / vmui
  └── vmselect-vmks-long (storageNode: vmstorage-vmks-*, vmstorage-vmks-long-*)
          ├── queries vmstorage-vmks-0   (30d data for all metrics)
          └── queries vmstorage-vmks-long-0  (5y data for airgradient_* metrics)
```

`vmselect` is **disabled** on the `vmks` cluster (no reader needed there) and **enabled** on `vmks-long` with
`extraArgs.storageNode` listing both vmstorage StatefulSet pods. This single vmselect transparently unions data from
both tiers at query time:

- Querying `airgradient_co2[1y]` → short-term returns 30d, long-term returns 5y; vmselect merges them.
- Querying `container_cpu_usage_seconds_total[1h]` → only short-term has it (never written to long-term); long-term
  returns empty.

`external.vm.read.url` in `helm/vmks.yaml` points all read consumers (Grafana datasource, vmalert remoteRead/datasource,
ingress) at `http://vmselect-vmks-long.vmks.svc.cluster.local.:8481/select/0/prometheus`. The chart only falls back to
this key when both `vmsingle.enabled: false` and `vmcluster.spec.vmselect.enabled: false` (see `vm.read.endpoint` in
`_helpers.tpl`). Flipping either flag silently overrides the URL.

## ytt overlays (`ytt/`)

| File                      | What it does                                                                                                                                                                                                                                                                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `long-term.ytt.yaml`      | Clones the `VMCluster` document into a `kind: List` (ytt cannot duplicate documents natively). The clone gets `-long` appended to its name, `retentionPeriod: 5y`, and `vmselect` added with cross-cluster `storageNode` via `#@overlay/match missing_ok=True` (the base cluster omits the `vmselect` key entirely because it is disabled). |
| `ingress.ytt.yaml`        | Traefik IngressRoutes for vmalert, vmagent, vmselect and vmui (→ `svc/vmselect-vmks-long`).                                                                                                                                                                                                                                                 |
| `k3s-monitoring.ytt.yaml` | Adds `VMNodeScrape` resources for kube-controller-manager and kube-scheduler (k3s exposes these on non-standard HTTPS ports). Removes the corresponding `VMServiceScrape` resources generated by the chart (which target non-existent services on k3s).                                                                                     |
| `secrets.ytt.yaml`        | Emits the `Secret` with the Alertmanager bot token and Healthchecks.io ping URL, decrypted from `static/0.sops.yaml` at render time.                                                                                                                                                                                                        |

## Access URLs

| Service              | LAN URL                                            | Notes                                                 |
| -------------------- | -------------------------------------------------- | ----------------------------------------------------- |
| Grafana              | `https://grafana.lan.zebradil.dev`                 | Protected via Authelia                                |
| Alertmanager         | `https://alertmanager.lan.zebradil.dev`            | Protected via Authelia                                |
| vmalert              | `https://vmalert.lan.zebradil.dev`                 | Protected via Authelia                                |
| vmagent              | `https://vmagent.lan.zebradil.dev`                 | Protected via Authelia                                |
| vmselect (canonical) | `https://vmselect.lan.zebradil.dev/select/0/vmui/` | Also works on `.gray.` and `.junior.` node subdomains |
| vmui (alias)         | `https://vmui.lan.zebradil.dev`                    | 308 → vmselect canonical URL                          |

## Gotchas

**`external.vm.write.url` is not set — and that's correct.** The chart's helper uses the in-cluster vminsert whenever
`vmcluster.spec.vminsert` is enabled, ignoring `external.vm.write.url`. Adding it back has no effect and creates
confusion.

**`external.vm.read.url` only fires as a fallback.** It is used because `vmcluster.spec.vmselect.enabled: false` _and_
`vmsingle.enabled: false`. If you re-enable vmselect on `vmks` (e.g. for debugging), the chart will silently switch all
read consumers to `vmselect-vmks` and ignore the external URL, breaking long-term reads.

**`extraArgs.storageNode` on `vmks-long` may be redundant for its own storage.** The operator auto-populates
`-storageNode` from the cluster's own vmstorage pods. Adding the long-term storage node explicitly in `extraArgs` may
result in it appearing twice. After the first deploy, verify with `kubectl -n vmks describe vmcluster vmks-long` and, if
needed, remove `vmstorage-vmks-long-*` from the `extraArgs.storageNode` value (keeping only the cross-cluster
`vmstorage-vmks-*` entry).

**The `kind: List` wrapper in `long-term.ytt.yaml` is intentional.** ytt processes documents independently and cannot
duplicate a document into two. The workaround is to replace the single `VMCluster` document with a `v1/List` containing
both the original and the patched clone. Any downstream ytt overlay that needs to target either cluster must match by
`kind: VMCluster` subset (not by document position), because both clusters are now children of the same List.

**`vmsingle` is fully disabled.** Any file, ingress route, or rule referencing `vmsingle-vmks` is stale.
