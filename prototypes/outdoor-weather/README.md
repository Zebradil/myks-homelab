# outdoor-weather

Outdoor weather (Open-Meteo) + air quality (UBA) metrics for indoor-vs-outdoor comparison. Design: [`docs/outdoors-weather-design.md`](../../docs/outdoors-weather-design.md).

- **Live**: `serve.py` Deployment, scraped by vmagent → 30d + 5y tiers (keep-filter includes `outdoor_.*`).
- **Backfill**: `backfill.py`, run manually (below).
- Location config is sops-encrypted in `static/outdoor-weather-location.sops.yaml`.

## Backfill / maintenance

Port-forward and set env once per shell:

```bash
kubectl -n vmks port-forward svc/vminsert-vmks-long 8480 &
kubectl -n vmks port-forward svc/vmselect-vmks-long 8481 &

# Location config from the sops-encrypted file (lat/lon/location/UBA station):
eval "$(sops -d --output-type dotenv prototypes/outdoor-weather/static/outdoor-weather-location.sops.yaml | sed 's/^/export /')"
export OUTDOOR_IMPORT_URL=http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus
export OUTDOOR_DELETE_URL=http://localhost:8481/delete/0/prometheus/api/v1/admin/tsdb/delete_series

cd prototypes/outdoor-weather/ytt/exporter
```

Initial seed (indoor data starts 2026-04-17):

```bash
python3 backfill.py weather --source auto --start 2026-04-17
python3 backfill.py air --start 2026-04-17
```

Replace stale forecast tail with ERA5 archive (run anytime after ~6 days):

```bash
python3 backfill.py delete-forecast
python3 backfill.py weather --source auto --start 2026-04-17
```

Notes:
- `--dry-run` on any command prints instead of writing/deleting.
- `auto`: archive for `[start, today-6]`, forecast for the recent tail.
- Re-importing archive over its own range is harmless (identical values).
- VM deletes whole series only (no time range); forecast is a disposable trailing window.

## Regenerate dashboard

```bash
cd prototypes/outdoor-weather/dashboard && go run . > ../ytt/dashboard.json
```

## Change location

```bash
sops prototypes/outdoor-weather/static/outdoor-weather-location.sops.yaml
```

Nearest UBA station (background type preferred):

```bash
curl -sL 'https://luftdaten.umweltbundesamt.de/api/air-data/v2/stations/json'
# row indices: [0]=id [1]=code [2]=name [6]=active_to(null=active) [7]=lon [8]=lat [16]=type
```
