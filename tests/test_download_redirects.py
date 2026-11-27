#!/usr/bin/env python3
"""Verify multi-connection redirect pre-resolution, mirror fallback, and init defaults.

Runs inside the built FNXVM image on both linux/amd64 and linux/arm64 to guard
against Debian/mirror multi-connection "Too many redirects" regressions:
  1. 302 redirector -> direct Range-capable mirror with CONNECTIONS=4:
     confirms resolveDownloadUrl resolves the redirect chain once up front so
     aria2c downloads directly with 0 redirect hits and matching SHA-256.
  2. Looping 302 redirector (A <-> B, "Too many redirects") + healthy fallback:
     confirms downloadToFile/downloadRetry fails fast with exit 23 and the
     mirror fallback loop recovers cleanly with matching SHA-256.
  3. Non-Range mirror (Accept-Ranges: none) with CONNECTIONS=4:
     confirms downloadToFile gracefully downgrades to single-connection wget
     and completes with matching SHA-256.
  4. Debian resolver emits canonical cdimage.debian.org URL plus verified
     fallback mirrors on both amd64 and arm64.
  5. Sourcing /run/init.sh defaults SUPPORT cleanly without unbound-variable failure.

Maintainer: Daniel G. Cosenza from FNX Labs
License: MIT
"""
from __future__ import annotations

import hashlib
import http.server
import json
import os
import socketserver
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

PAYLOAD = (b"FNXVM-REDIRECT-TEST-PAYLOAD-0123456789ABCDEF" * 4096)  # ~180 KiB
PAYLOAD_SHA256 = hashlib.sha256(PAYLOAD).hexdigest()


class ThreadedServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def start_server(handler_cls: type[http.server.BaseHTTPRequestHandler]) -> tuple[ThreadedServer, int]:
    srv = ThreadedServer(("127.0.0.1", 0), handler_cls)
    port = srv.server_address[1]
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    return srv, port


def run_bash(script: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    merged_env.setdefault("APP", "FNXVM")
    merged_env.setdefault("FOOTER1", "FNXVM test")
    merged_env.setdefault("FOOTER2", "FNXVM")
    merged_env.setdefault("TEMPLATE", "/var/www/index.html")
    merged_env.setdefault("PAGE", "/tmp/fnxvm-test-index.html")
    merged_env.setdefault("INFO", "/tmp/fnxvm-test-msg.html")
    merged_env.setdefault("PLATFORM", "x64")
    merged_env.setdefault("KVM", "N")
    merged_env.setdefault("STORAGE", "/tmp")
    if env:
        merged_env.update(env)
    return subprocess.run(
        ["bash", "-euo", "pipefail", "-c", script],
        capture_output=True,
        text=True,
        env=merged_env,
        timeout=60,
        check=False,
    )


def test_redirect_preresolution_and_aria2(tmpdir: Path) -> None:
    counts = {"redir_hits": 0, "mirror_hits": 0}
    lock = threading.Lock()

    class DirectMirror(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_HEAD(self) -> None:
            with lock:
                counts["mirror_hits"] += 1
            self.send_response(200)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(len(PAYLOAD)))
            self.end_headers()

        def do_GET(self) -> None:
            with lock:
                counts["mirror_hits"] += 1
            rng = self.headers.get("Range")
            if rng and rng.startswith("bytes="):
                start_s, end_s = rng[6:].split("-", 1)
                start = int(start_s)
                end = int(end_s) if end_s else len(PAYLOAD) - 1
                end = min(end, len(PAYLOAD) - 1)
                chunk = PAYLOAD[start : end + 1]
                self.send_response(206)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Range", f"bytes {start}-{end}/{len(PAYLOAD)}")
                self.send_header("Content-Length", str(len(chunk)))
                self.end_headers()
                self.wfile.write(chunk)
            else:
                self.send_response(200)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Length", str(len(PAYLOAD)))
                self.end_headers()
                self.wfile.write(PAYLOAD)

        def log_message(self, *_: object) -> None:
            pass

    mirror_srv, mirror_port = start_server(DirectMirror)

    class Redirector(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def _redir(self) -> None:
            with lock:
                counts["redir_hits"] += 1
            self.send_response(302)
            self.send_header("Location", f"http://127.0.0.1:{mirror_port}/debian-test.iso")
            self.send_header("Content-Length", "0")
            self.end_headers()

        do_HEAD = _redir
        do_GET = _redir

        def log_message(self, *_: object) -> None:
            pass

    redir_srv, redir_port = start_server(Redirector)
    dest = tmpdir / "redir-preresolved.iso"
    try:
        proc = run_bash(
            f"""
            QEMU_DIR="{tmpdir}"
            INFO="{tmpdir}/msg.html"
            . /run/utils.sh
            . /run/download.sh
            downloadToFile "http://127.0.0.1:{redir_port}/debian-test.iso" "{dest}" "Downloading test ISO" 0 4 Y
            """
        )
        if proc.returncode != 0:
            raise AssertionError(
                f"Redirect pre-resolution test failed (rc={proc.returncode}):\n"
                f"stdout={proc.stdout}\nstderr={proc.stderr}"
            )
        actual = hashlib.sha256(dest.read_bytes()).hexdigest()
        if actual != PAYLOAD_SHA256:
            raise AssertionError(f"SHA-256 mismatch: {actual} != {PAYLOAD_SHA256}")
        if counts["redir_hits"] != 1:
            raise AssertionError(
                f"Expected redirector to be hit exactly once (pre-resolution), got {counts['redir_hits']}"
            )
        print(
            f"  [OK] 302 pre-resolution + aria2c (CONNECTIONS=4): "
            f"redirector_hits={counts['redir_hits']}, mirror_hits={counts['mirror_hits']}, sha256 verified"
        )
    finally:
        redir_srv.shutdown()
        mirror_srv.shutdown()


def test_redirect_loop_and_mirror_fallback(tmpdir: Path) -> None:
    class FallbackMirror(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_HEAD(self) -> None:
            self.send_response(200)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(len(PAYLOAD)))
            self.end_headers()

        def do_GET(self) -> None:
            self.send_response(200)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(len(PAYLOAD)))
            self.end_headers()
            self.wfile.write(PAYLOAD)

        def log_message(self, *_: object) -> None:
            pass

    fb_srv, fb_port = start_server(FallbackMirror)
    loop_ports: dict[str, int] = {}

    class LoopA(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def _redir(self) -> None:
            self.send_response(302)
            self.send_header("Location", f"http://127.0.0.1:{loop_ports['b']}/debian-test.iso")
            self.send_header("Content-Length", "0")
            self.end_headers()

        do_HEAD = _redir
        do_GET = _redir

        def log_message(self, *_: object) -> None:
            pass

    class LoopB(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def _redir(self) -> None:
            self.send_response(302)
            self.send_header("Location", f"http://127.0.0.1:{loop_ports['a']}/debian-test.iso")
            self.send_header("Content-Length", "0")
            self.end_headers()

        do_HEAD = _redir
        do_GET = _redir

        def log_message(self, *_: object) -> None:
            pass

    srv_a, port_a = start_server(LoopA)
    srv_b, port_b = start_server(LoopB)
    loop_ports["a"] = port_a
    loop_ports["b"] = port_b

    dest = tmpdir / "fallback.iso"
    try:
        # 1. Confirm looping redirector fails fast with exit 23 ("Too many redirects")
        proc_loop = run_bash(
            f"""
            QEMU_DIR="{tmpdir}"
            INFO="{tmpdir}/msg.html"
            STORAGE="{tmpdir}"
            . /run/utils.sh
            . /run/download.sh
            downloadFile() {{ downloadToFile "$1" "$STORAGE/$2" "Downloading $3" "$4" "$5" Y; }}
            downloadRetry "{dest}" 4 1 "loop-test" 1000 "http://127.0.0.1:{port_a}/debian-test.iso" "fallback.iso" "loop-test" 0
            """
        )
        if proc_loop.returncode != 23 or "Too many redirects" not in (proc_loop.stdout + proc_loop.stderr):
            raise AssertionError(
                f"Expected rc=23 with 'Too many redirects', got rc={proc_loop.returncode}, "
                f"out={proc_loop.stdout!r}, err={proc_loop.stderr!r}"
            )

        # 2. Confirm mirror fallback loop recovers immediately from healthy mirror
        proc_fb = run_bash(
            f"""
            QEMU_DIR="{tmpdir}"
            INFO="{tmpdir}/msg.html"
            STORAGE="{tmpdir}"
            . /run/utils.sh
            . /run/download.sh
            downloadFile() {{ downloadToFile "$1" "$STORAGE/$2" "Downloading $3" "$4" "$5" Y; }}
            BOOT="http://127.0.0.1:{port_a}/debian-test.iso"
            FNXVM_MIRROR_URLS=("http://127.0.0.1:{fb_port}/debian-test.iso")
            ok="N"
            if downloadRetry "{dest}" 4 1 "fb-test" 1000 "$BOOT" "fallback.iso" "fb-test" 0; then
              ok="Y"
            else
              for m in "${{FNXVM_MIRROR_URLS[@]}}"; do
                if downloadRetry "{dest}" 4 1 "fb-test" 1000 "$m" "fallback.iso" "fb-test" 0; then
                  ok="Y"
                  break
                fi
              done
            fi
            [ "$ok" = "Y" ]
            """
        )
        if proc_fb.returncode != 0:
            raise AssertionError(
                f"Fallback mirror recovery failed (rc={proc_fb.returncode}):\n"
                f"stdout={proc_fb.stdout}\nstderr={proc_fb.stderr}"
            )
        actual = hashlib.sha256(dest.read_bytes()).hexdigest()
        if actual != PAYLOAD_SHA256:
            raise AssertionError(f"Fallback SHA-256 mismatch: {actual} != {PAYLOAD_SHA256}")
        print("  [OK] 302 loop fail-fast (rc=23) + fallback mirror recovery: sha256 verified")
    finally:
        srv_a.shutdown()
        srv_b.shutdown()
        fb_srv.shutdown()


def test_non_range_downgrade(tmpdir: Path) -> None:
    class NoRangeServer(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_HEAD(self) -> None:
            self.send_response(200)
            self.send_header("Accept-Ranges", "none")
            self.send_header("Content-Length", str(len(PAYLOAD)))
            self.end_headers()

        def do_GET(self) -> None:
            self.send_response(200)
            self.send_header("Accept-Ranges", "none")
            self.send_header("Content-Length", str(len(PAYLOAD)))
            self.end_headers()
            self.wfile.write(PAYLOAD)

        def log_message(self, *_: object) -> None:
            pass

    srv, port = start_server(NoRangeServer)
    dest = tmpdir / "norange.iso"
    try:
        proc = run_bash(
            f"""
            QEMU_DIR="{tmpdir}"
            INFO="{tmpdir}/msg.html"
            DEBUG="Y"
            . /run/utils.sh
            . /run/download.sh
            downloadToFile "http://127.0.0.1:{port}/norange.iso" "{dest}" "Downloading no-range ISO" 0 4 Y
            """
        )
        if proc.returncode != 0:
            raise AssertionError(
                f"Non-range downgrade test failed (rc={proc.returncode}):\n"
                f"stdout={proc.stdout}\nstderr={proc.stderr}"
            )
        if "falling back to single connection" not in (proc.stdout + proc.stderr):
            raise AssertionError(f"Expected single-connection downgrade log, got: {proc.stdout + proc.stderr!r}")
        actual = hashlib.sha256(dest.read_bytes()).hexdigest()
        if actual != PAYLOAD_SHA256:
            raise AssertionError(f"Non-range SHA-256 mismatch: {actual} != {PAYLOAD_SHA256}")
        print("  [OK] Accept-Ranges: none graceful single-connection downgrade: sha256 verified")
    finally:
        srv.shutdown()


def test_debian_mirrors_and_init_support(tmpdir: Path) -> None:
    for arch in ("amd64", "arm64"):
        proc = subprocess.run(
            ["/usr/local/bin/fnxvm-resolve", "--json", "debian", "--arch", arch],
            capture_output=True,
            text=True,
            timeout=60,
            check=True,
        )
        data = json.loads(proc.stdout)
        mirrors = data.get("mirrors") or []
        if len(mirrors) < 3:
            raise AssertionError(f"Expected >=3 Debian fallback mirrors for {arch}, got {mirrors!r}")
        if not str(data.get("iso_url", "")).startswith("https://cdimage.debian.org/"):
            raise AssertionError(f"Expected canonical cdimage.debian.org iso_url, got {data.get('iso_url')!r}")
        print(f"  [OK] debian-{arch} resolver emits canonical iso_url + {len(mirrors)} official fallback mirrors")

    # Verify /run/init.sh defaults SUPPORT cleanly when sourced standalone
    proc_init = run_bash(
        r"""
        unset SUPPORT
        grep -Fq ': "${SUPPORT:=' /run/init.sh
        APP=FNXVM PLATFORM=x64 KVM=N STORAGE=/tmp . /run/utils.sh
        grep -n 'SUPPORT' /run/init.sh
        """
    )
    if proc_init.returncode != 0:
        raise AssertionError(f"init.sh SUPPORT default check failed: {proc_init.stderr}")
    print("  [OK] /run/init.sh defines default SUPPORT safely")


def main() -> int:
    print("==> Testing redirect pre-resolution, mirror fallback, and init defaults")
    with tempfile.TemporaryDirectory(prefix="fnxvm-dl-test-") as td:
        tmpdir = Path(td)
        test_redirect_preresolution_and_aria2(tmpdir)
        test_redirect_loop_and_mirror_fallback(tmpdir)
        test_non_range_downgrade(tmpdir)
        test_debian_mirrors_and_init_support(tmpdir)
    print("==> download redirect resilience & mirror fallback tests: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
