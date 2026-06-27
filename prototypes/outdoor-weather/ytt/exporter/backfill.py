#!/usr/bin/env python3
"""Historical backfiller for outdoor-weather metrics (run manually).

Posts Prometheus exposition WITH millisecond timestamps to VictoriaMetrics'
import API. Aim it at vminsert-vmks-long so samples land directly in the 5y tier
(this bypasses the vmagent remoteWrite keep-filter).

Typical local use (port-forward the cluster services first):

    kubectl -n vmks port-forward svc/vminsert-vmks-long 8480
    kubectl -n vmks port-forward svc/vmselect-vmks-long 8481

    export OUTDOOR_LATITUDE=.. OUTDOOR_LONGITUDE=.. OUTDOOR_UBA_STATION=..
    export OUTDOOR_IMPORT_URL=http://localhost:8480/insert/0/prometheus/api/v1/import/prometheus
    export OUTDOOR_DELETE_URL=http://localhost:8481/delete/0/prometheus/api/v1/admin/tsdb/delete_series

    # Seed history (archive where available, forecast for the recent tail):
    python3 backfill.py weather --source auto --start 2026-04-17
    python3 backfill.py air --start 2026-04-17

Replacing the low-quality recent tail once ERA5 has caught up. VictoriaMetrics
can only delete whole series (no time range), so forecast data is treated as a
disposable trailing window: delete it wholesale, then re-import archive + a
fresh trailing forecast:

    python3 backfill.py delete-forecast
    python3 backfill.py weather --source auto --start 2026-04-17
"""

import argparse
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta

import common

IMPORT_URL = os.environ.get("OUTDOOR_IMPORT_URL", "")
DELETE_URL = os.environ.get("OUTDOOR_DELETE_URL", "")


def _parse_date(s):
    return datetime.strptime(s, "%Y-%m-%d").date()


def _post_import(samples, import_url, dry_run):
    if not samples:
        common.log("no samples produced; nothing to import")
        return
    body = "\n".join(common.render_line(s, with_ts=True) for s in samples) + "\n"
    if dry_run:
        sys.stdout.write(body)
        common.log(f"dry-run: {len(samples)} samples not sent")
        return
    if not import_url:
        sys.exit("--import-url (or OUTDOOR_IMPORT_URL) required unless --dry-run")
    req = urllib.request.Request(
        import_url,
        data=body.encode("utf-8"),
        headers={"Content-Type": "text/plain"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=common.HTTP_TIMEOUT * 4) as resp:
        common.log(f"imported {len(samples)} samples, status {resp.status}")


def cmd_weather(args):
    start = _parse_date(args.start)
    end = _parse_date(args.end) if args.end else common.today_utc()
    cutoff = common.today_utc() - timedelta(days=common.ARCHIVE_LAG_DAYS)

    samples = []
    if args.source in ("archive", "auto"):
        a_end = min(end, cutoff) if args.source == "auto" else end
        if start <= a_end:
            samples += common.fetch_weather_hourly(
                common.OPEN_METEO_ARCHIVE, start, a_end, common.SOURCE_ARCHIVE
            )
    if args.source in ("forecast", "auto"):
        f_start = max(start, cutoff + timedelta(days=1)) if args.source == "auto" else start
        if f_start <= end:
            samples += common.fetch_weather_hourly(
                common.OPEN_METEO_FORECAST, f_start, end, common.SOURCE_FORECAST
            )
    _post_import(samples, args.import_url, args.dry_run)


def cmd_air(args):
    start = _parse_date(args.start)
    end = _parse_date(args.end) if args.end else common.today_utc()
    _post_import(common.fetch_uba_range(start, end), args.import_url, args.dry_run)


def _delete(match, delete_url, dry_run):
    if dry_run:
        common.log(f"dry-run: would delete series matching {match}")
        return
    if not delete_url:
        sys.exit("--delete-url (or OUTDOOR_DELETE_URL) required unless --dry-run")
    data = urllib.parse.urlencode([("match[]", match)]).encode("utf-8")
    req = urllib.request.Request(
        delete_url,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=common.HTTP_TIMEOUT) as resp:
        common.log(f"delete '{match}' status {resp.status}")


def cmd_delete(args):
    _delete(args.match, args.delete_url, args.dry_run)


def cmd_delete_forecast(args):
    # Whole-series delete of every outdoor_* metric tagged as forecast backfill.
    _delete('{__name__=~"outdoor_.*",source="%s"}' % common.SOURCE_FORECAST,
            args.delete_url, args.dry_run)


def main():
    p = argparse.ArgumentParser(description="outdoor-weather backfiller")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_import_args(sp):
        sp.add_argument("--start", required=True, help="start date YYYY-MM-DD (inclusive)")
        sp.add_argument("--end", default="", help="end date YYYY-MM-DD (default today)")
        sp.add_argument("--import-url", default=IMPORT_URL, help="VM import/prometheus URL")
        sp.add_argument("--dry-run", action="store_true", help="print to stdout instead of POSTing")

    w = sub.add_parser("weather", help="backfill Open-Meteo weather")
    w.add_argument("--source", choices=["archive", "forecast", "auto"], default="auto")
    add_import_args(w)
    w.set_defaults(func=cmd_weather)

    a = sub.add_parser("air", help="backfill UBA air quality")
    add_import_args(a)
    a.set_defaults(func=cmd_air)

    d = sub.add_parser("delete", help="delete series by selector (whole series)")
    d.add_argument("--match", required=True, help='series selector, e.g. {source="open-meteo-forecast"}')
    d.add_argument("--delete-url", default=DELETE_URL, help="VM delete_series URL")
    d.add_argument("--dry-run", action="store_true")
    d.set_defaults(func=cmd_delete)

    df = sub.add_parser("delete-forecast", help="delete all forecast-sourced outdoor series")
    df.add_argument("--delete-url", default=DELETE_URL, help="VM delete_series URL")
    df.add_argument("--dry-run", action="store_true")
    df.set_defaults(func=cmd_delete_forecast)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
