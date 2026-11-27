#!/usr/bin/env python3
"""push-chart.sh with the pinned Helm against a real loopback registry.

The registry can lag like GHCR did for chart 0.12.3 (404 for the first lookup of a manifest it has just
accepted, which fails helm's tag step) or deny every push. Helm talks plain HTTP to localhost.
"""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/push-chart.sh"
UNKNOWN = b'{"errors":[{"code":"MANIFEST_UNKNOWN","message":"manifest unknown"}]}'


class Registry(ThreadingHTTPServer):
    def __init__(self, mode):
        super().__init__(("127.0.0.1", 0), Handler)
        self.mode, self.blobs, self.manifests, self.tags = mode, {}, {}, {}
        self.lagging, self.lagged = set(), set()
        threading.Thread(target=self.serve_forever, daemon=True).start()

    def handle_error(self, request, client_address):
        pass  # Helm closing a connection early is not a test failure; keep CI logs clean.


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def reply(self, code, headers=None, body=b""):
        self.send_response(code)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def read_body(self):
        length = int(self.headers.get("Content-Length", "0"))
        return self.rfile.read(length) if length else b""

    def route(self):
        registry, path = self.server, self.path.split("?")[0]
        if path == "/v2/":
            return self.reply(200)
        if registry.mode == "deny" and self.command in ("POST", "PUT"):
            self.read_body()
            return self.reply(403, {"Content-Type": "application/json"}, b'{"errors":[{"code":"DENIED","message":"denied"}]}')
        upload = re.fullmatch(r"/v2/(.+)/blobs/uploads/(.*)", path)
        if upload and self.command == "POST":
            self.read_body()
            return self.reply(202, {"Location": f"/v2/{upload[1]}/blobs/uploads/session"})
        if upload and self.command == "PUT":
            data, digest = self.read_body(), re.search(r"digest=([^&]+)", self.path)[1].replace("%3A", ":")
            registry.blobs[digest] = data
            return self.reply(201, {"Docker-Content-Digest": digest})
        match = re.fullmatch(r"/v2/(.+)/(blobs|manifests)/(.+)", path)
        if not match:
            return self.reply(404)
        kind, reference = match[2], match[3]
        if kind == "blobs":
            if reference not in registry.blobs:
                return self.reply(404)
            return self.reply(200, {"Docker-Content-Digest": reference}, registry.blobs[reference])
        if self.command == "PUT":
            data = self.read_body()
            digest = "sha256:" + hashlib.sha256(data).hexdigest()
            registry.manifests[digest] = (self.headers["Content-Type"], data)
            if not reference.startswith("sha256:"):
                registry.tags[reference] = digest
            # GHCR lagged once per new manifest; a repeated push of the same bytes is served.
            if registry.mode == "lag" and digest not in registry.lagged:
                registry.lagging.add(digest)
                registry.lagged.add(digest)
            return self.reply(201, {"Docker-Content-Digest": digest})
        digest = registry.tags.get(reference, reference)
        if registry.mode == "lag-forever" and reference.startswith("sha256:"):
            return self.reply(404, {"Content-Type": "application/json"}, UNKNOWN)
        if digest not in registry.manifests or digest in registry.lagging:
            registry.lagging.discard(digest)
            return self.reply(404, {"Content-Type": "application/json"}, UNKNOWN)
        media, data = registry.manifests[digest]
        return self.reply(200, {"Docker-Content-Digest": digest, "Content-Type": media}, data)

    do_GET = do_HEAD = do_PUT = do_POST = route


class PushChartTest(unittest.TestCase):
    def push(self, mode):
        registry = Registry(mode)
        self.addCleanup(registry.server_close)
        self.addCleanup(registry.shutdown)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "example"
            (source / "templates").mkdir(parents=True)
            (source / "Chart.yaml").write_text("apiVersion: v2\nname: example\nversion: 0.1.0\n")
            subprocess.run(["helm", "package", str(source), "--destination", directory], check=True,
                           capture_output=True, timeout=60)
            env = dict(os.environ, PUBLISH_RETRY_PAUSE_SECONDS="0", HELM_REGISTRY_CONFIG=f"{directory}/registry.json",
                       HELM_CACHE_HOME=f"{directory}/cache", HELM_CONFIG_HOME=f"{directory}/config")
            result = subprocess.run(["bash", str(SCRIPT), f"{directory}/example-0.1.0.tgz",
                                     f"oci://localhost:{registry.server_address[1]}/charts", "--plain-http"],
                                    env=env, capture_output=True, text=True, timeout=120)
        return registry, result

    def test_repeats_the_push_while_the_registry_lags(self):
        registry, result = self.push("lag")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0.1.0", registry.tags)
        self.assertIn("push attempt 1 of 6, retrying", result.stderr)

    def test_normal_push_runs_once(self):
        registry, result = self.push("normal")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0.1.0", registry.tags)
        self.assertNotIn("retrying", result.stderr)

    def test_denied_push_is_not_repeated(self):
        registry, result = self.push("deny")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("retrying", result.stderr)
        self.assertEqual(registry.tags, {})

    def test_gives_up_after_six_attempts_and_never_reports_success(self):
        registry, result = self.push("lag-forever")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stderr.count("retrying"), 5)
        self.assertEqual(registry.tags, {})


if __name__ == "__main__":
    unittest.main()
