#!/usr/bin/env python3
"""Router-safe Prometheus exporter for llama.cpp.

In router mode, querying llama-server /metrics?model=<name> for every configured model
can force model switches when --models-max is low. This exporter discovers only the
currently loaded models, fetches metrics for those models, injects a stable `model`
label when needed, and exposes a single Prometheus scrape endpoint.
"""

from __future__ import annotations

import json
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Iterable

LLAMA_SERVER_URL = os.environ.get("LLAMA_SERVER_URL", "http://llama-cpp:8000").rstrip("/")
EXPORTER_PORT = int(os.environ.get("EXPORTER_PORT", "9101"))
CACHE_TTL_SECONDS = float(os.environ.get("CACHE_TTL_SECONDS", "5"))
UPSTREAM_TIMEOUT_SECONDS = float(os.environ.get("UPSTREAM_TIMEOUT_SECONDS", "4"))

MODEL_KEYS = (
    "model",
    "model_name",
    "model_alias",
    "model_id",
    "alias",
)
METRIC_LINE_RE = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*\})?(\s+.+)$")
HELP_TYPE_RE = re.compile(r"^#\s+(HELP|TYPE)\s+([a-zA-Z_:][a-zA-Z0-9_:]*)\b")


class MetricsCache:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._timestamp = 0.0
        self._payload = ""

    def get(self) -> tuple[float, str]:
        with self._lock:
            return self._timestamp, self._payload

    def set(self, payload: str) -> None:
        with self._lock:
            self._timestamp = time.time()
            self._payload = payload


CACHE = MetricsCache()


def http_get_json(path: str) -> object:
    request = urllib.request.Request(f"{LLAMA_SERVER_URL}{path}")
    with urllib.request.urlopen(request, timeout=UPSTREAM_TIMEOUT_SECONDS) as response:
        return json.load(response)


def http_get_text(path: str, query: dict[str, str] | None = None) -> str:
    url = f"{LLAMA_SERVER_URL}{path}"
    if query:
        url += "?" + urllib.parse.urlencode(query)
    request = urllib.request.Request(url)
    with urllib.request.urlopen(request, timeout=UPSTREAM_TIMEOUT_SECONDS) as response:
        return response.read().decode("utf-8", "replace")


def iter_slot_dicts(payload: object) -> Iterable[dict]:
    if isinstance(payload, list):
        for item in payload:
            if isinstance(item, dict):
                yield item
        return

    if not isinstance(payload, dict):
        return

    for key in ("slots", "data", "items", "models"):
        value = payload.get(key)
        if isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    yield item
            return

    yield payload


def extract_loaded_models(payload: object) -> list[str]:
    models: list[str] = []
    seen: set[str] = set()

    for item in iter_slot_dicts(payload):
        state = str(item.get("state", "")).lower()
        is_loaded = item.get("loaded")
        if state in {"empty", "idle_unloaded", "unloaded"} or is_loaded is False:
            continue

        for key in MODEL_KEYS:
            value = item.get(key)
            if not isinstance(value, str):
                continue
            model = value.strip()
            if not model or model.lower() in {"none", "null", "-"}:
                continue
            if model not in seen:
                seen.add(model)
                models.append(model)
            break

    return models


def escape_label_value(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def inject_model_label(metric_line: str, model: str) -> str:
    match = METRIC_LINE_RE.match(metric_line)
    if not match:
        return metric_line

    metric_name, labels, suffix = match.groups()
    if labels and "model=" in labels:
        return metric_line

    model_label = f'model="{escape_label_value(model)}"'
    if labels:
        return f"{metric_name}{labels[:-1]},{model_label}}}{suffix}"
    return f"{metric_name}{{{model_label}}}{suffix}"


def merge_metrics_for_models(model_to_metrics: dict[str, str]) -> str:
    lines: list[str] = []
    seen_headers: set[tuple[str, str]] = set()

    lines.extend(
        [
            "# HELP panther_llama_metrics_exporter_up Whether the router-safe llama metrics exporter succeeded.",
            "# TYPE panther_llama_metrics_exporter_up gauge",
            "panther_llama_metrics_exporter_up 1",
            "# HELP panther_llama_metrics_exporter_loaded_models Number of currently loaded models discovered via /slots.",
            "# TYPE panther_llama_metrics_exporter_loaded_models gauge",
            f"panther_llama_metrics_exporter_loaded_models {len(model_to_metrics)}",
        ]
    )

    for model, payload in sorted(model_to_metrics.items()):
        for raw_line in payload.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            header_match = HELP_TYPE_RE.match(line)
            if header_match:
                header_key = (header_match.group(1), header_match.group(2))
                if header_key in seen_headers:
                    continue
                seen_headers.add(header_key)
                lines.append(line)
                continue
            if line.startswith("#"):
                continue
            lines.append(inject_model_label(line, model))

    return "\n".join(lines) + "\n"


def build_metrics_payload() -> str:
    slot_payload = http_get_json("/slots")
    models = extract_loaded_models(slot_payload)

    if not models:
        return "\n".join(
            [
                "# HELP panther_llama_metrics_exporter_up Whether the router-safe llama metrics exporter succeeded.",
                "# TYPE panther_llama_metrics_exporter_up gauge",
                "panther_llama_metrics_exporter_up 1",
                "# HELP panther_llama_metrics_exporter_loaded_models Number of currently loaded models discovered via /slots.",
                "# TYPE panther_llama_metrics_exporter_loaded_models gauge",
                "panther_llama_metrics_exporter_loaded_models 0",
                "",
            ]
        )

    model_to_metrics: dict[str, str] = {}
    for model in models:
        model_to_metrics[model] = http_get_text("/metrics", {"model": model})

    return merge_metrics_for_models(model_to_metrics)


class Handler(BaseHTTPRequestHandler):
    server_version = "PantherLlamaMetricsExporter/1.0"

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/healthz":
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"ok\n")
            return

        if not self.path.startswith("/metrics"):
            self.send_response(HTTPStatus.NOT_FOUND)
            self.end_headers()
            return

        now = time.time()
        cached_at, cached_payload = CACHE.get()
        if cached_payload and now - cached_at < CACHE_TTL_SECONDS:
            payload = cached_payload
            status = HTTPStatus.OK
        else:
            try:
                payload = build_metrics_payload()
                CACHE.set(payload)
                status = HTTPStatus.OK
            except Exception as exc:  # noqa: BLE001
                if cached_payload:
                    payload = cached_payload + (
                        '# HELP panther_llama_metrics_exporter_stale Whether cached data is being served after an upstream error.\n'
                        '# TYPE panther_llama_metrics_exporter_stale gauge\n'
                        'panther_llama_metrics_exporter_stale 1\n'
                    )
                    status = HTTPStatus.OK
                else:
                    payload = (
                        "# HELP panther_llama_metrics_exporter_up Whether the router-safe llama metrics exporter succeeded.\n"
                        "# TYPE panther_llama_metrics_exporter_up gauge\n"
                        "panther_llama_metrics_exporter_up 0\n"
                        f"# upstream_error {type(exc).__name__}: {exc}\n"
                    )
                    status = HTTPStatus.SERVICE_UNAVAILABLE

        encoded = payload.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"[llama-metrics-exporter] {self.address_string()} - {fmt % args}")


def main() -> None:
    server = ThreadingHTTPServer(("0.0.0.0", EXPORTER_PORT), Handler)
    print(
        f"[llama-metrics-exporter] listening on 0.0.0.0:{EXPORTER_PORT}, "
        f"upstream={LLAMA_SERVER_URL}, cache_ttl={CACHE_TTL_SECONDS}s"
    )
    server.serve_forever()


if __name__ == "__main__":
    main()

