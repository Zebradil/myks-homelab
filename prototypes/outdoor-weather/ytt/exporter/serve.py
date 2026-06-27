#!/usr/bin/env python3
"""Live outdoor-weather Prometheus exporter.

A background thread refreshes Open-Meteo current conditions and the latest UBA
air-quality readings every OUTDOOR_REFRESH_SECONDS; ``/metrics`` serves the
cached snapshot (values are stamped at scrape time, source=open-meteo / uba).

Run directly:  OUTDOOR_LATITUDE=.. OUTDOOR_LONGITUDE=.. python3 serve.py
"""

import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import common

PORT = int(os.environ.get("PORT", "9113"))
REFRESH_SECONDS = int(os.environ.get("OUTDOOR_REFRESH_SECONDS", "600"))


class _Cache:
    def __init__(self):
        self.lock = threading.Lock()
        self.lines = ["# outdoor-weather starting up"]

    def set(self, samples):
        body = [common.render_line(s, with_ts=False) for s in samples]
        with self.lock:
            self.lines = body or ["# outdoor-weather no data"]

    def get(self):
        with self.lock:
            return "\n".join(self.lines) + "\n"


def _refresh_loop(cache):
    while True:
        samples = []
        try:
            samples += common.fetch_weather_current()
        except Exception as exc:  # noqa: BLE001
            common.log(f"weather refresh failed: {exc}")
        try:
            samples += common.fetch_uba_current()
        except Exception as exc:  # noqa: BLE001
            common.log(f"UBA refresh failed: {exc}")
        if samples:
            cache.set(samples)
            common.log(f"refreshed: {len(samples)} series")
        time.sleep(REFRESH_SECONDS)


def main():
    cache = _Cache()
    threading.Thread(target=_refresh_loop, args=(cache,), daemon=True).start()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path == "/metrics":
                payload = cache.get().encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; version=0.0.4")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            else:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"outdoor-weather exporter\n")

        def log_message(self, *_args):  # silence per-request logging
            pass

    common.log(f"serving /metrics on :{PORT} (refresh every {REFRESH_SECONDS}s)")
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
