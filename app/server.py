"""Small dependency-free service used to demonstrate multi-cloud failover."""

from __future__ import annotations

import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from time import monotonic
from urllib.parse import urlsplit


STARTED_AT = monotonic()
REQUEST_COUNT = 0
REQUEST_LOCK = threading.Lock()


def application_metadata() -> dict[str, str]:
    return {
        "service": "multicloud-demo",
        "status": "healthy",
        "cloud": os.getenv("CLOUD_PROVIDER", "local"),
        "region": os.getenv("CLOUD_REGION", "local"),
        "version": os.getenv("APP_VERSION", "dev"),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "multicloud-demo"

    def _write_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        global REQUEST_COUNT
        with REQUEST_LOCK:
            REQUEST_COUNT += 1

        path = urlsplit(self.path).path
        if path in {"/health", "/ready"}:
            self._write_json(200, application_metadata())
            return
        if path == "/metrics":
            uptime = max(0.0, monotonic() - STARTED_AT)
            with REQUEST_LOCK:
                request_count = REQUEST_COUNT
            body = (
                "# HELP multicloud_demo_requests_total HTTP requests received.\n"
                "# TYPE multicloud_demo_requests_total counter\n"
                f"multicloud_demo_requests_total {request_count}\n"
                "# HELP multicloud_demo_uptime_seconds Process uptime.\n"
                "# TYPE multicloud_demo_uptime_seconds gauge\n"
                f"multicloud_demo_uptime_seconds {uptime:.3f}\n"
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/":
            self._write_json(200, application_metadata())
            return
        self._write_json(404, {"status": "not_found", "path": path})

    def log_message(self, fmt: str, *args: object) -> None:
        print(f'{self.address_string()} - {fmt % args}', flush=True)


def main() -> None:
    port = int(os.getenv("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"multicloud-demo listening on 0.0.0.0:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()

