"""Small dependency-free service used to demonstrate multi-cloud failover."""

from __future__ import annotations

import json
import os
import threading
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from time import monotonic
from urllib.parse import urlsplit

import certifi
from pymongo import MongoClient
from pymongo.server_api import ServerApi


STARTED_AT = monotonic()
REQUEST_COUNT = 0
REQUEST_LOCK = threading.Lock()
MONGODB_CLIENT: MongoClient | None = None
MONGODB_LOCK = threading.Lock()


def mongodb_uri() -> str:
    return os.getenv("MONGODB_URI", "").strip()


def mongodb_database_name() -> str:
    return os.getenv("MONGODB_DATABASE", "multicloud_demo")


def mongodb_collection_name() -> str:
    return os.getenv("MONGODB_COLLECTION", "items")


def mongodb_client() -> MongoClient:
    global MONGODB_CLIENT
    uri = mongodb_uri()
    if not uri:
        raise RuntimeError("MongoDB is not configured")

    with MONGODB_LOCK:
        if MONGODB_CLIENT is None:
            tls_options = {"tlsCAFile": certifi.where()} if uri.startswith("mongodb+srv://") else {}
            MONGODB_CLIENT = MongoClient(
                uri,
                server_api=ServerApi("1"),
                serverSelectionTimeoutMS=3000,
                connectTimeoutMS=3000,
                maxPoolSize=10,
                **tls_options,
            )
    return MONGODB_CLIENT


def mongodb_collection():
    return mongodb_client()[mongodb_database_name()][mongodb_collection_name()]


def database_health() -> tuple[int, dict[str, object]]:
    if not mongodb_uri():
        return 503, {"database": "mongodb", "status": "disabled"}

    try:
        mongodb_client().admin.command({"ping": 1})
    except Exception as exc:  # PyMongo exposes several connection exception types.
        return 503, {
            "database": "mongodb",
            "status": "unavailable",
            "error": type(exc).__name__,
        }

    return 200, {
        "database": "mongodb",
        "database_name": mongodb_database_name(),
        "status": "healthy",
    }


def application_metadata() -> dict[str, str]:
    return {
        "service": "multicloud-demo",
        "status": "healthy",
        "cloud": os.getenv("CLOUD_PROVIDER", "local"),
        "region": os.getenv("CLOUD_REGION", "local"),
        "version": os.getenv("APP_VERSION", "dev"),
        "mongodb": "configured" if mongodb_uri() else "disabled",
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
        if path == "/db/health":
            status, payload = database_health()
            self._write_json(status, payload)
            return
        if path == "/db/items":
            if not mongodb_uri():
                self._write_json(503, {"database": "mongodb", "status": "disabled"})
                return
            try:
                items = []
                cursor = mongodb_collection().find({}, {"message": 1, "cloud": 1, "region": 1, "created_at": 1})
                for document in cursor.sort("_id", -1).limit(20):
                    items.append({
                        "id": str(document["_id"]),
                        "message": document.get("message", ""),
                        "cloud": document.get("cloud", ""),
                        "region": document.get("region", ""),
                        "created_at": document.get("created_at", ""),
                    })
                self._write_json(200, {"count": len(items), "items": items})
            except Exception as exc:
                self._write_json(503, {"database": "mongodb", "status": "unavailable", "error": type(exc).__name__})
            return
        if path == "/":
            self._write_json(200, application_metadata())
            return
        self._write_json(404, {"status": "not_found", "path": path})

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        path = urlsplit(self.path).path
        if path != "/db/items":
            self._write_json(404, {"status": "not_found", "path": path})
            return
        if not mongodb_uri():
            self._write_json(503, {"database": "mongodb", "status": "disabled"})
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 65536:
                raise ValueError("request body must contain 1-65536 bytes")
            payload = json.loads(self.rfile.read(content_length))
            message = payload.get("message", "") if isinstance(payload, dict) else ""
            if not isinstance(message, str) or not message.strip():
                raise ValueError("message must be a non-empty string")

            document = {
                "message": message.strip()[:1000],
                "cloud": os.getenv("CLOUD_PROVIDER", "local"),
                "region": os.getenv("CLOUD_REGION", "local"),
                "created_at": datetime.now(UTC).isoformat(),
            }
            result = mongodb_collection().insert_one(document.copy())
            self._write_json(201, {"id": str(result.inserted_id), **document})
        except (json.JSONDecodeError, ValueError) as exc:
            self._write_json(400, {"status": "invalid_request", "error": str(exc)})
        except Exception as exc:
            self._write_json(503, {"database": "mongodb", "status": "unavailable", "error": type(exc).__name__})

    def log_message(self, fmt: str, *args: object) -> None:
        print(f'{self.address_string()} - {fmt % args}', flush=True)


def main() -> None:
    port = int(os.getenv("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"multicloud-demo listening on 0.0.0.0:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
