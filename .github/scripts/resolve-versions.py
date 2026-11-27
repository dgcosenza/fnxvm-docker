#!/usr/bin/env python3
"""Resolve upstream dockur/windows, qemus/qemu, base image digests, and live guest OS versions.

Uses the authenticated GitHub API (GH_TOKEN) for upstream releases and Docker Hub API
for Debian/Go base digests, plus src/fnxvm-resolve for current guest OS metadata.
Maintainer: Daniel G. Cosenza from FNX Labs
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

DEBIAN_TAG = "13.8-slim"
GO_TAG = "1.27.4-trixie"
HELPER_PINS = {
    "qemus/websocketd": "WEBSOCKETD_VERSION",
    "qemus/boot-logo": "BOOT_LOGO_VERSION",
    "qemus/udfread": "UDFREAD_VERSION",
    "novnc/noVNC": "NOVNC_VERSION",
    "qemus/virtiso-whql": "VIRTIO_AMD64_RELEASE",
    "qemus/virtiso-arm": "VIRTIO_ARM64_RELEASE",
}


def fetch_json(url: str, token: str = "") -> dict:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "dgcosenza-fnxvm-docker-ci",
    }
    if token and "api.github.com" in url:
        headers["Authorization"] = f"Bearer {token}"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
    with urlopen(Request(url, headers=headers), timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def pinned_arg(dockerfile: str, name: str) -> str:
    m = re.search(rf"^ARG {re.escape(name)}=(.+)$", dockerfile, re.MULTILINE)
    return m.group(1).strip().strip('"') if m else ""


def resolve_guest(os_name: str, arch: str = "amd64", extra: list[str] | None = None) -> dict:
    cmd = [sys.executable, "src/fnxvm-resolve", os_name, "--arch", arch, "--json"]
    if extra:
        cmd.extend(extra)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60, check=False)
    if proc.returncode != 0:
        return {"os": os_name, "arch": arch, "error": proc.stderr.strip()}
    return json.loads(proc.stdout)


def main() -> int:
    dockerfile = Path("Dockerfile").read_text(encoding="utf-8")
    token = os.environ.get("GH_TOKEN", "").strip()
    if not token:
        raise SystemExit("ERROR: GH_TOKEN is required for authenticated release resolution")

    pin_win = pinned_arg(dockerfile, "WINDOWS_VERSION") or "6.06"
    pin_qemu = pinned_arg(dockerfile, "QEMU_VERSION") or "7.50"

    win_rel = fetch_json("https://api.github.com/repos/dockur/windows/releases/latest", token)
    qemu_rel = fetch_json("https://api.github.com/repos/qemus/qemu/releases/latest", token)

    win_ver = (os.environ.get("OVERRIDE_WINDOWS") or "").strip().lstrip("v") or (
        (win_rel.get("tag_name") or pin_win).strip().lstrip("v")
    )
    qemu_ver = (os.environ.get("OVERRIDE_QEMU") or "").strip().lstrip("v") or (
        (qemu_rel.get("tag_name") or pin_qemu).strip().lstrip("v")
    )
    fnxvm_ver = win_ver

    deb_hub = fetch_json(f"https://hub.docker.com/v2/repositories/library/debian/tags/{DEBIAN_TAG}")
    base_digest = (deb_hub.get("digest") or "").strip()
    if not base_digest.startswith("sha256:"):
        raise SystemExit(f"ERROR: could not resolve digest for debian:{DEBIAN_TAG}")
    debian_base = f"debian:{DEBIAN_TAG}@{base_digest}"

    go_hub = fetch_json(f"https://hub.docker.com/v2/repositories/library/golang/tags/{GO_TAG}")
    go_digest = (go_hub.get("digest") or "").strip()
    if not go_digest.startswith("sha256:"):
        raise SystemExit(f"ERROR: could not resolve digest for golang:{GO_TAG}")
    go_base = f"golang:{GO_TAG}@{go_digest}"

    helper_releases: dict[str, str] = {}
    for repo in HELPER_PINS:
        try:
            helper_releases[repo] = (
                fetch_json(f"https://api.github.com/repos/{repo}/releases/latest", token).get("tag_name") or ""
            ).strip()
        except Exception:
            helper_releases[repo] = ""

    # Record current dynamically resolved guest OS versions for versions.json / README docs
    guest_probes = {
        "windows": resolve_guest("windows", "amd64", ["--version", "11"]),
        "windows_ltsc": resolve_guest("windows", "amd64", ["--version", "ltsc"]),
        "haiku": resolve_guest("haiku", "amd64"),
        "freebsd": resolve_guest("freebsd", "amd64"),
        "debian_gnome": resolve_guest("debian", "amd64", ["--desktop", "gnome"]),
        "debian_kde": resolve_guest("debian", "amd64", ["--desktop", "kde"]),
        "ubuntu": resolve_guest("ubuntu", "amd64"),
        "omarchy": resolve_guest("omarchy", "amd64"),
    }
    guests_summary = {
        "windows": guest_probes["windows"].get("version") or "latest Microsoft",
        "haiku": f"{guest_probes['haiku'].get('version') or 'latest'} (amd64)",
        "freebsd": guest_probes["freebsd"].get("version") or "latest -RELEASE",
        "debian": f"{guest_probes['debian_gnome'].get('version') or 'latest'} (GNOME / KDE)",
        "ubuntu": guest_probes["ubuntu"].get("version") or "latest LTS",
        "omarchy": f"{guest_probes['omarchy'].get('version') or 'latest'} (rolling, no LTS)",
    }
    Path("guests-resolved.json").write_text(
        json.dumps({"summary": guests_summary, "resolved": guest_probes}, indent=2) + "\n",
        encoding="utf-8",
    )

    prev = {}
    vpath = Path("versions.json")
    if vpath.exists():
        try:
            prev = json.loads(vpath.read_text(encoding="utf-8"))
        except Exception:
            prev = {}

    prev_win = prev.get("windows_version", "")
    prev_qemu = prev.get("qemu_version", "")
    prev_base = prev.get("base_digest", "")

    lines = [
        "# Upstream changes — FNXVM",
        "",
        f"- **dockur/windows:** `{prev_win or 'none'}` -> `{win_ver}`",
        f"- **qemus/qemu:** `{prev_qemu or 'none'}` -> `{qemu_ver}`",
        f"- **Base image:** `debian:{DEBIAN_TAG}` pinned at `{base_digest}`"
        + (" (refreshed)" if base_digest != prev_base else ""),
        f"- **Go builder:** `golang:{GO_TAG}` pinned at `{go_digest}`",
        "",
        "## Resolved guest OS versions (build-time snapshot)",
        "",
    ]
    for k, v in guests_summary.items():
        lines.append(f"- `{k}`: `{v}`")

    lines.extend(["", "## Upstream release notes", ""])
    if win_ver != prev_win and win_rel.get("body"):
        lines.append(f"### dockur/windows v{win_ver}")
        for ln in str(win_rel["body"]).splitlines()[:10]:
            if ln.strip():
                lines.append(ln.strip())
    if qemu_ver != prev_qemu and qemu_rel.get("body"):
        lines.append(f"### qemus/qemu v{qemu_ver}")
        for ln in str(qemu_rel["body"]).splitlines()[:10]:
            if ln.strip():
                lines.append(ln.strip())

    lines.extend(["", "## Helper component pins", ""])
    for repo, arg in HELPER_PINS.items():
        pin = pinned_arg(dockerfile, arg)
        latest = helper_releases.get(repo, "")
        note = " (up to date)" if latest and latest.lstrip("v") == pin.lstrip("v") else ""
        lines.append(f"- `{repo}`: pinned `{pin or 'n/a'}`; latest `{latest or 'unavailable'}`{note}")

    Path("upstream-changes.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    now = datetime.now(timezone.utc)
    outputs = {
        "fnxvm_version": fnxvm_ver,
        "windows_version": win_ver,
        "qemu_version": qemu_ver,
        "debian_base": debian_base,
        "go_base": go_base,
        "base_digest": base_digest,
        "build_date": now.strftime("%Y%m%d"),
        "build_date_iso": now.strftime("%Y-%m-%d"),
        "created": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    gh_out = os.environ.get("GITHUB_OUTPUT")
    if gh_out:
        with open(gh_out, "a", encoding="utf-8") as fh:
            for k, v in outputs.items():
                fh.write(f"{k}={v}\n")
    for k, v in outputs.items():
        print(f"{k}={v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
