# Technical Design: Outdoor Weather & Air Quality Metrics

## 1. Use case

Ingest localized outdoor weather and air-quality metrics into the homelab's VictoriaMetrics so Grafana can compare
**outdoor** conditions against **indoor** AirGradient sensor data over the long term. Indoor data starts **2026-04-17**;
outdoor history is backfilled to the same date.

Outdoor series carry the configured coordinates (and UBA station) as labels, so a future location change produces new,
distinguishable time series instead of a silent discontinuity.

## 2. How this fits the existing infrastructure

This repo does **not** run a standalone Prometheus, and retention is **not** the gate. Two facts drove the design:

1. **Two-tier VictoriaMetrics** (`prototypes/victoria-metrics-k8s-stack`):
   - `vmks` — 30d, all metrics.
   - `vmks-long` — 5y, but `vmagent` only remote-writes a **filtered subset** to it
     (`additionalRemoteWrites[].inlineUrlRelabelConfig`, an `action: keep` on `__name__`).
   - Grafana/vmalert/vmui read from `vmselect-vmks-long`, which unions both tiers.

   → The real gate is that keep-filter. It was `airgradient_.*`; it is now **`airgradient_.*|outdoor_.*`**. Without this,
   live outdoor data would only reach the 30d tier and vanish after a month, and a >30d backfill via the scrape path
   would be pointless.

2. **Scraping is ServiceMonitor-based.** `vmagent` discovers `ServiceMonitor`s cluster-wide. The exporter is therefore a
   normal Deployment + Service + ServiceMonitor (same pattern as `airgradient-exporter`), not a push pipeline.

## 3. Data sources (hybrid)

The "100% physical sensor" purist constraint was relaxed where it costs more than it's worth:

| Domain | Source | Why |
| --- | --- | --- |
| Weather (temp, humidity, wind, pressure, precip) | **Open-Meteo** (keyless) | Model/reanalysis sampled at the *exact* house coordinates — more representative of "here" than an airport sensor ~10 km away. Free historical archive (ERA5) + forecast endpoint for recent days. |
| Air quality (PM2.5, PM10, NO₂, O₃) | **UBA Luftdaten** (keyless) | Real sensor readings from the nearest official German monitoring station; PM/NO₂ vary too sharply with location to model. |

Rejected: OpenWeatherMap history (paid tier); **OpenAQ** (now requires an API key); a standalone `json_exporter`
(UBA's indexed-array JSON is awkward for JSONPath, and a single codebase guarantees live/backfill metric-name parity).

Location is a private house coordinate paired with the nearest active **background** UBA station (background type
avoids roadside spikes). Location config is **sops-encrypted**
(`prototypes/outdoor-weather/static/outdoor-weather-location.sops.yaml`) — it is private.

### Endpoints

- Weather live: `https://api.open-meteo.com/v1/forecast` (`current=...`).
- Weather history: `https://archive-api.open-meteo.com/v1/archive` (ERA5, ~5-day lag); the most recent days fall back to
  the forecast endpoint.
- Air quality: `https://luftdaten.umweltbundesamt.de/api/air-data/v2/measures/json`
  (`station`, `component`, `scope`, `date_from/to`, `time_from/to`). Component IDs: PM10=1, O₃=3, NO₂=5, PM2.5=9.
  UBA timestamps are fixed CET (UTC+1) and encode end-of-day as hour `24:00:00`.

## 4. Component: `outdoor-weather`

Stdlib-only Python in `prototypes/outdoor-weather/ytt/exporter/`, split so each part runs standalone and is loaded into
ConfigMaps via `data.read("exporter/<file>.py")`:

- **`common.py`** — config (from env), metric model, source constants, and the Open-Meteo / UBA fetchers.
- **`serve.py`** — the live exporter (imports `common`).
- **`backfill.py`** — the manual historical backfiller + delete helper (imports `common`).

### Live exporter (`serve.py`)

A Deployment on stock `python:3.13-slim` with `common.py`+`serve.py` mounted from a ConfigMap. A background thread
refreshes Open-Meteo current conditions + the latest UBA readings every `OUTDOOR_REFRESH_SECONDS` (default 600);
`/metrics` serves the cached snapshot. Scraped by `vmagent` → 30d tier, and (via the expanded keep-filter) → 5y tier.

### Backfiller (`backfill.py`) — run manually

Intentionally **not** a k8s Job. It POSTs Prometheus exposition **with millisecond timestamps** to VictoriaMetrics'
import API, aimed at `vminsert-vmks-long` (`/insert/0/prometheus/api/v1/import/prometheus`) so samples land straight in
the 5y tier, bypassing the keep-filter. Run it locally against port-forwarded cluster services. Subcommands:

- `weather --source {archive,forecast,auto}` — Open-Meteo. `auto` uses the ERA5 archive for `[start, today-6]` and the
  forecast endpoint for the recent tail.
- `air` — UBA air quality.
- `delete-forecast` / `delete --match <selector>` — delete series (see §6).

### Metric model

| Metric | Unit | Source | Indoor counterpart |
| --- | --- | --- | --- |
| `outdoor_temp_celsius` | °C | Open-Meteo | `airgradient_atmp` |
| `outdoor_humidity_percent` | % | Open-Meteo | `airgradient_rhum` |
| `outdoor_wind_speed_ms` | m/s | Open-Meteo | — |
| `outdoor_pressure_hpa` | hPa | Open-Meteo | — |
| `outdoor_precip_mm` | mm | Open-Meteo | — |
| `outdoor_pm02_ugm3` | µg/m³ | UBA | `airgradient_pm02` |
| `outdoor_pm10_ugm3` | µg/m³ | UBA | `airgradient_pm10` |
| `outdoor_no2_ugm3` | µg/m³ | UBA | — |
| `outdoor_o3_ugm3` | µg/m³ | UBA | — |

Labels on every series: `latitude`, `longitude`, `location`, `source`, and `station` (UBA only). The `source` label
encodes provenance so the low-quality recent backfill can be replaced later:

| `source` | Meaning | Lifecycle |
| --- | --- | --- |
| `open-meteo` | Live exporter (current conditions) | Permanent |
| `open-meteo-archive` | ERA5 historical backfill | Authoritative |
| `open-meteo-forecast` | Backfill of days ERA5 hasn't reached | Disposable trailing window |
| `uba` | Air-quality sensor station | Permanent |

## 5. Dashboard

A separate **private** "Indoor vs Outdoor" Grafana dashboard
(`prototypes/outdoor-weather/dashboard/dashboard.go`, grafana-foundation-sdk, generated to `ytt/dashboard.json` and
shipped as a `grafana_dashboard` ConfigMap). It overlays indoor vs outdoor temperature, humidity, PM2.5 and PM10, plus
outdoor-only NO₂/O₃, wind, pressure and precipitation. The public `airgradient-exporter` dashboard is untouched; the Go
source is written in the same style so it can fold into that project later.

Outdoor queries aggregate `avg without(source, station)(...)` so the provenance sources (archive/forecast/live) merge
into one continuous line per metric — at any timestamp only one source has data — while provenance stays queryable.

## 6. Running the backfill

VictoriaMetrics can only delete **whole series** (no time-range delete) and does **not** reliably overwrite
same-timestamp samples (this cluster sets no `-dedup.minScrapeInterval`). So forecast data is treated as a disposable
trailing window: to improve precision once ERA5 catches up, delete the whole forecast series and re-import.

```bash
# Port-forward the VM cluster services:
kubectl -n vmks port-forward svc/vminsert-vmks-long 8480
kubectl -n vmks port-forward svc/vmselect-vmks-long 8481

# Location config from the sops-encrypted file (lat/lon/location/UBA station):
eval "$(sops -d --output-type dotenv prototypes/outdoor-weather/static/outdoor-weather-location.sops.yaml | sed 's/^/export /')"
export OUTDOOR_IMPORT_URL=http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus
export OUTDOOR_DELETE_URL=http://localhost:8481/delete/0/prometheus/api/v1/admin/tsdb/delete_series

cd prototypes/outdoor-weather/ytt/exporter

# Initial seed (archive where available, forecast for the recent tail):
python3 backfill.py weather --source auto --start 2026-04-17
python3 backfill.py air --start 2026-04-17

# Later, replace the now-stale forecast tail with ERA5 archive:
python3 backfill.py delete-forecast
python3 backfill.py weather --source auto --start 2026-04-17
```

Add `--dry-run` to any command to print/preview instead of writing. Re-importing the archive over its own range is
harmless (identical values); the forecast series is always just the trailing window, so its whole-series delete is safe.
