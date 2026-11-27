#!/usr/bin/env python3
"""Verify bundled vendor GPG keyrings and live OS verification inputs inside FNXVM.

Runs inside the built container image on both linux/amd64 and linux/arm64 to make
broken, UID-less, or mismatched vendor keyrings impossible to ship again:
  1. Parses every bundled binary keyring in /etc/fnxvm/keys/*.gpg at the OpenPGP
     packet level and asserts every primary key has a User ID packet, a User ID
     self-signature, and matches the pinned official vendor fingerprints.
  2. Exercises the exact live gpgv + SHA256SUMS verification path from
     src/generic/install.sh for:
       - Debian amd64 live (GNOME + KDE) and Debian arm64 DVD-1
       - Ubuntu amd64 LTS and Ubuntu arm64 LTS
       - Plus fail-closed negative tests on tampered SHA256SUMS payloads.
  3. Verifies Omarchy (amd64 + arm64):
       - Fetches .iso.sha256 and detached .iso.sig, asserting the .iso.sig issuer
         fingerprint matches the bundled Omarchy key.
       - Fetches the small (~6.4 KB) official signed omarchy-keyring package from
         pkgs.omarchy.org/stable/x86_64/ and verifies it with gpgv against
         /etc/fnxvm/keys/omarchy.gpg (plus a negative tampered-file test).
         Full detached signature verification of the multi-GB ISO runs at runtime.
  4. Fetches and parses live small checksum files for Daemonarchy (amd64 + arm64),
     FreeBSD (amd64 + arm64), and Haiku (amd64, including .minisig) so every
     resolver's verification inputs are exercised in CI.

Maintainer: Daniel G. Cosenza from FNX Labs
License: MIT
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

USER_AGENT = "fnxvm-ci-keyring-verifier/1.0"
HTTP_TIMEOUT = 30
HTTP_RETRIES = 3

# Pinned official vendor OpenPGP primary key fingerprints and expected UID substrings.
EXPECTED_KEYRINGS: dict[str, dict[str, str]] = {
    "debian-cd.gpg": {
        "10460DAD76165AD81FBC0CE9988021A964E6EA7D": "Debian CD signing key <debian-cd@lists.debian.org>",
        "DF9B9C49EAA9298432589D76DA87E80D6294BE9B": "Debian CD signing key <debian-cd@lists.debian.org>",
        "F41D30342F3546695F65C66942468F4009EA8AC3": "Debian Testing CDs Automatic Signing Key <debian-cd@lists.debian.org>",
    },
    "ubuntu-cd.gpg": {
        "843938DF228D22F7B3742BC0D94AA3F0EFE21092": "Ubuntu CD Image Automatic Signing Key (2012) <cdimage@ubuntu.com>",
    },
    "omarchy.gpg": {
        "40DFB630FF42BCFFB047046CF0134EE680CAC571": "Omarchy <pkgs@omarchy.org>",
    },
}


def fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def parse_openpgp_packets(data: bytes) -> list[tuple[int, bytes]]:
    """Parse binary RFC 4880/9580 OpenPGP packets into (tag, body) tuples."""
    packets: list[tuple[int, bytes]] = []
    pos = 0
    total = len(data)
    while pos < total:
        b0 = data[pos]
        if (b0 & 0x80) == 0:
            fail(f"Invalid OpenPGP packet header byte 0x{b0:02x} at offset {pos}")
        pos += 1
        if b0 & 0x40:
            # New packet format
            tag = b0 & 0x3F
            if pos >= total:
                fail("Truncated new-format OpenPGP packet length")
            l0 = data[pos]
            pos += 1
            if l0 < 192:
                length = l0
            elif l0 < 224:
                if pos >= total:
                    fail("Truncated 2-octet OpenPGP packet length")
                length = ((l0 - 192) << 8) + data[pos] + 192
                pos += 1
            elif l0 == 255:
                if pos + 4 > total:
                    fail("Truncated 5-octet OpenPGP packet length")
                length = struct.unpack(">I", data[pos : pos + 4])[0]
                pos += 4
            else:
                fail(f"Unsupported partial OpenPGP packet length {l0} at offset {pos - 1}")
        else:
            # Legacy packet format
            tag = (b0 >> 2) & 0x0F
            ltype = b0 & 0x03
            if ltype == 0:
                length = data[pos]
                pos += 1
            elif ltype == 1:
                length = struct.unpack(">H", data[pos : pos + 2])[0]
                pos += 2
            elif ltype == 2:
                length = struct.unpack(">I", data[pos : pos + 4])[0]
                pos += 4
            else:
                length = total - pos
        if pos + length > total:
            fail(f"Truncated OpenPGP packet body (tag={tag}, need={length}, have={total - pos})")
        packets.append((tag, data[pos : pos + length]))
        pos += length
    return packets


def public_key_v4_fingerprint(body: bytes) -> str:
    if not body or body[0] != 4:
        fail(f"Expected OpenPGP v4 public key packet, got version {body[0] if body else 'empty'}")
    prefix = b"\x99" + struct.pack(">H", len(body))
    return hashlib.sha1(prefix + body).hexdigest().upper()


def parse_signature_packet(body: bytes) -> dict[str, Any]:
    """Extract version, sigclass, issuer fingerprint, and issuer keyid from a Tag 2 packet."""
    if len(body) < 6:
        fail("Signature packet too short")
    ver = body[0]
    if ver != 4:
        fail(f"Expected OpenPGP v4 signature packet, got version {ver}")
    sigclass = body[1]
    hashed_len = struct.unpack(">H", body[4:6])[0]
    pos = 6
    hashed_end = pos + hashed_len
    if hashed_end + 2 > len(body):
        fail("Truncated hashed subpackets in signature packet")
    unhashed_len = struct.unpack(">H", body[hashed_end : hashed_end + 2])[0]
    unhashed_start = hashed_end + 2
    unhashed_end = unhashed_start + unhashed_len
    if unhashed_end > len(body):
        fail("Truncated unhashed subpackets in signature packet")

    issuer_fpr = ""
    issuer_keyid = ""
    for start, end in ((pos, hashed_end), (unhashed_start, unhashed_end)):
        sp = start
        while sp < end:
            l0 = body[sp]
            sp += 1
            if l0 < 192:
                slen = l0
            elif l0 < 255:
                slen = ((l0 - 192) << 8) + body[sp] + 192
                sp += 1
            else:
                slen = struct.unpack(">I", body[sp : sp + 4])[0]
                sp += 4
            stype = body[sp] & 0x7F
            sdata = body[sp + 1 : sp + slen]
            if stype == 33 and len(sdata) >= 21 and sdata[0] == 4:
                issuer_fpr = sdata[1:21].hex().upper()
            elif stype == 16 and len(sdata) == 8:
                issuer_keyid = sdata.hex().upper()
            sp += slen

    return {
        "version": ver,
        "sigclass": sigclass,
        "issuer_fpr": issuer_fpr,
        "issuer_keyid": issuer_keyid,
    }


def check_bundled_keyrings(keyring_dir: Path) -> None:
    print(f"==> Checking bundled OpenPGP keyrings in {keyring_dir}")
    for filename, expected_map in EXPECTED_KEYRINGS.items():
        path = keyring_dir / filename
        if not path.is_file() or path.stat().st_size == 0:
            fail(f"Missing or empty keyring: {path}")
        raw = path.read_bytes()
        if raw.startswith(b"-----BEGIN PGP"):
            fail(f"Keyring {path} is ASCII-armored instead of binary dearmored OpenPGP")
        packets = parse_openpgp_packets(raw)

        keys: dict[str, dict[str, Any]] = {}
        current_fpr: str | None = None
        seen_uid_for_current = False

        for tag, body in packets:
            if tag == 6:  # Public-Key (primary)
                current_fpr = public_key_v4_fingerprint(body)
                seen_uid_for_current = False
                keys[current_fpr] = {"uids": [], "uid_self_sigs": 0, "subkeys": 0}
            elif tag == 13:  # User ID
                if current_fpr is None:
                    fail(f"{filename}: User ID packet before any Primary Key packet")
                uid = body.decode("utf-8", errors="replace").strip()
                if uid:
                    keys[current_fpr]["uids"].append(uid)
                    seen_uid_for_current = True
            elif tag == 14:  # Public-Subkey
                if current_fpr is None:
                    fail(f"{filename}: Subkey packet before any Primary Key packet")
                keys[current_fpr]["subkeys"] += 1
            elif tag == 2 and current_fpr is not None:  # Signature
                sig = parse_signature_packet(body)
                # 0x10..0x13 are User ID certification signatures
                if seen_uid_for_current and sig["sigclass"] in (0x10, 0x11, 0x12, 0x13):
                    if sig["issuer_fpr"] == current_fpr or sig["issuer_keyid"] == current_fpr[-16:]:
                        keys[current_fpr]["uid_self_sigs"] += 1

        if not keys:
            fail(f"{filename}: contains 0 primary keys")

        actual_fprs = set(keys.keys())
        expected_fprs = set(expected_map.keys())
        if actual_fprs != expected_fprs:
            fail(
                f"{filename}: fingerprint mismatch.\n"
                f"  expected: {sorted(expected_fprs)}\n"
                f"  actual:   {sorted(actual_fprs)}"
            )

        for fpr, expected_uid in expected_map.items():
            info = keys[fpr]
            if not info["uids"]:
                fail(f"{filename}: key {fpr} has NO User ID packet (gpgv will refuse to use it!)")
            if info["uid_self_sigs"] < 1:
                fail(f"{filename}: key {fpr} has NO User ID self-signature packet")
            if expected_uid not in info["uids"]:
                fail(
                    f"{filename}: key {fpr} UID mismatch (expected {expected_uid!r}, got {info['uids']!r})"
                )
            print(
                f"  [OK] {filename}: fpr={fpr} uid={info['uids'][0]!r} "
                f"(uid_self_sigs={info['uid_self_sigs']}, subkeys={info['subkeys']})"
            )


def fetch_bytes(url: str, dest: Path | None = None) -> bytes:
    last_err: Exception | None = None
    for attempt in range(1, HTTP_RETRIES + 1):
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
                data = resp.read()
                if dest is not None:
                    dest.write_bytes(data)
                return data
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
            last_err = exc
            if attempt < HTTP_RETRIES:
                time.sleep(2 * attempt)
    fail(f"Failed to download {url} after {HTTP_RETRIES} attempts: {last_err}")
    raise AssertionError("unreachable")


def run_resolve(resolver: str, os_name: str, arch: str, extra: list[str] | None = None) -> dict[str, Any]:
    cmd = [sys.executable, resolver, "--json", os_name, "--arch", arch]
    if extra:
        cmd.extend(extra)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60, check=False)
    if proc.returncode != 0:
        fail(f"Resolver failed ({' '.join(cmd)}): {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def run_gpgv(keyring: Path, sig_path: Path, data_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["gpgv", "--keyring", str(keyring), str(sig_path), str(data_path)],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


def parse_sums_like_install_sh(sums_text: str, iso_name: str) -> str:
    """Mirror the exact awk parser from src/generic/install.sh."""
    for line in sums_text.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        fname = parts[1].lstrip("*")
        if fname == iso_name:
            return parts[0].lower()
    return ""


def verify_signed_sha256sums(
    label: str,
    resolved_list: list[dict[str, Any]],
    keyring: Path,
    tmpdir: Path,
) -> None:
    first = resolved_list[0]
    checksum_url = first["checksum_url"]
    sig_url = first["signature_url"]
    sums_path = tmpdir / f"{label}.SHA256SUMS"
    sig_path = tmpdir / f"{label}.SHA256SUMS.sig"

    sums_bytes = fetch_bytes(checksum_url, sums_path)
    fetch_bytes(sig_url, sig_path)

    res = run_gpgv(keyring, sig_path, sums_path)
    combined = (res.stdout + res.stderr).strip()
    if res.returncode != 0 or "Good signature" not in combined:
        fail(f"gpgv FAILED for {label} ({checksum_url} + {sig_url}):\n{combined}")

    print(f"  [OK] {label}: gpgv verified {sig_url}")
    for line in combined.splitlines():
        print(f"       {line}")

    sums_text = sums_bytes.decode("utf-8", errors="replace")
    for item in resolved_list:
        iso_name = item["iso_filename"]
        expected = item["checksum_value"].lower()
        found = parse_sums_like_install_sh(sums_text, iso_name)
        if not found or found != expected:
            fail(
                f"{label}: SHA256SUMS entry mismatch for {iso_name} "
                f"(got {found!r}, resolver expected {expected!r})"
            )
        print(f"       verified entry: {iso_name} -> sha256:{found[:16]}...")

    # Fail-closed negative check: tamper with 1 byte of SHA256SUMS and confirm gpgv rejects it.
    tampered_path = tmpdir / f"{label}.SHA256SUMS.tampered"
    tampered_bytes = bytearray(sums_bytes)
    tampered_bytes[0] ^= 0x01
    tampered_path.write_bytes(bytes(tampered_bytes))
    neg = run_gpgv(keyring, sig_path, tampered_path)
    if neg.returncode == 0:
        fail(f"{label}: negative test FAILED — gpgv accepted tampered SHA256SUMS!")
    print(f"       negative tamper check: rejected (exit {neg.returncode})")


def extract_tar_zst_member(archive: Path, member: str | None = None) -> tuple[list[str], bytes]:
    """List or extract a member from a zstd-compressed pacman repo DB using bsdtar or tar."""
    if shutil.which("bsdtar"):
        if member is None:
            p = subprocess.run(["bsdtar", "-tf", str(archive)], capture_output=True, text=True, check=True)
            return p.stdout.splitlines(), b""
        p = subprocess.run(["bsdtar", "-xOf", str(archive), member], capture_output=True, check=True)
        return [], p.stdout
    if shutil.which("tar"):
        if member is None:
            p = subprocess.run(["tar", "-tf", str(archive)], capture_output=True, text=True, check=True)
            return p.stdout.splitlines(), b""
        p = subprocess.run(["tar", "-xOf", str(archive), member], capture_output=True, check=True)
        return [], p.stdout
    fail("Neither bsdtar nor tar is available to inspect omarchy.db")
    raise AssertionError("unreachable")


def verify_omarchy(resolver: str, keyring: Path, tmpdir: Path) -> None:
    expected_fpr = "40DFB630FF42BCFFB047046CF0134EE680CAC571"
    for arch in ("amd64", "arm64"):
        res = run_resolve(resolver, "omarchy", arch)
        sums_text = fetch_bytes(res["checksum_url"]).decode("utf-8", errors="replace")
        m_sha = re.search(r"([0-9a-fA-F]{64})", sums_text)
        if not m_sha or m_sha.group(1).lower() != res["checksum_value"].lower():
            fail(f"omarchy-{arch}: .iso.sha256 mismatch from {res['checksum_url']}")

        sig_bytes = fetch_bytes(res["signature_url"])
        packets = parse_openpgp_packets(sig_bytes)
        sig_packets = [parse_signature_packet(body) for tag, body in packets if tag == 2]
        if not sig_packets:
            fail(f"omarchy-{arch}: no OpenPGP signature packet in {res['signature_url']}")
        issuer = sig_packets[0]["issuer_fpr"]
        if issuer != expected_fpr:
            fail(
                f"omarchy-{arch}: .iso.sig issuer mismatch "
                f"(got {issuer!r}, expected {expected_fpr!r})"
            )
        print(
            f"  [OK] omarchy-{arch}: .iso.sha256 verified ({res['checksum_value'][:16]}...), "
            f".iso.sig issuer={issuer} (full ISO gpgv check runs at runtime)"
        )

    # Cryptographically exercise /etc/fnxvm/keys/omarchy.gpg via gpgv against Omarchy's
    # small official signed package (omarchy-keyring, ~6.4 KB) signed by the same key.
    repo_base = "https://pkgs.omarchy.org/stable/x86_64"
    db_path = tmpdir / "omarchy.db"
    fetch_bytes(f"{repo_base}/omarchy.db", db_path)
    members, _ = extract_tar_zst_member(db_path)
    desc_members = [m for m in members if m.endswith("/desc")]
    preferred = [m for m in desc_members if m.startswith("omarchy-keyring-")]
    chosen_pkg = ""
    chosen_size = 10**9

    for desc in preferred or desc_members:
        _, raw_desc = extract_tar_zst_member(db_path, desc)
        txt = raw_desc.decode("utf-8", errors="replace")
        m_fn = re.search(r"%FILENAME%\s*\n([^\n]+)", txt)
        m_sz = re.search(r"%CSIZE%\s*\n([0-9]+)", txt)
        if not m_fn:
            continue
        sz = int(m_sz.group(1)) if m_sz else 0
        if preferred:
            chosen_pkg = m_fn.group(1).strip()
            chosen_size = sz
            break
        if 0 < sz < chosen_size and sz <= 1024 * 1024:
            chosen_pkg = m_fn.group(1).strip()
            chosen_size = sz

    if not chosen_pkg:
        fail("omarchy: could not find a small signed package in pkgs.omarchy.org/stable/x86_64/omarchy.db")

    pkg_path = tmpdir / chosen_pkg
    pkg_sig_path = tmpdir / f"{chosen_pkg}.sig"
    pkg_bytes = fetch_bytes(f"{repo_base}/{chosen_pkg}", pkg_path)
    fetch_bytes(f"{repo_base}/{chosen_pkg}.sig", pkg_sig_path)

    res = run_gpgv(keyring, pkg_sig_path, pkg_path)
    combined = (res.stdout + res.stderr).strip()
    if res.returncode != 0 or "Good signature" not in combined:
        fail(f"gpgv FAILED for Omarchy signed package {chosen_pkg}:\n{combined}")
    print(f"  [OK] omarchy-pkg: gpgv verified {repo_base}/{chosen_pkg} ({chosen_size} bytes)")
    for line in combined.splitlines():
        print(f"       {line}")

    tampered = tmpdir / f"{chosen_pkg}.tampered"
    tb = bytearray(pkg_bytes)
    tb[0] ^= 0x01
    tampered.write_bytes(bytes(tb))
    neg = run_gpgv(keyring, pkg_sig_path, tampered)
    if neg.returncode == 0:
        fail("omarchy-pkg: negative test FAILED — gpgv accepted tampered package!")
    print(f"       negative tamper check: rejected (exit {neg.returncode})")


def verify_checksum_only_guests(resolver: str) -> None:
    print("==> Checking live small checksum files for Daemonarchy, FreeBSD, and Haiku")

    # Daemonarchy (amd64 + arm64): .iso.xz.sha256
    for arch in ("amd64", "arm64"):
        res = run_resolve(resolver, "daemonarchy", arch)
        txt = fetch_bytes(res["checksum_url"]).decode("utf-8", errors="replace")
        iso_name = res["iso_filename"]
        expected = res["checksum_value"].lower()
        m = re.search(rf"^([0-9a-fA-F]{{64}})\s+\*?{re.escape(iso_name)}$", txt, re.MULTILINE)
        if not m:
            m = re.search(rf"^SHA256\s+\({re.escape(iso_name)}\)\s+=\s+([0-9a-fA-F]{{64}})$", txt, re.MULTILINE)
        if not m or m.group(1).lower() != expected:
            fail(f"daemonarchy-{arch}: checksum file verification failed for {res['checksum_url']}")
        print(f"  [OK] daemonarchy-{arch}: {iso_name} -> sha256:{expected[:16]}... ({res['checksum_url']})")

    # FreeBSD (amd64 + arm64): CHECKSUM.SHA256-FreeBSD-...
    for arch in ("amd64", "arm64"):
        res = run_resolve(resolver, "freebsd", arch)
        txt = fetch_bytes(res["checksum_url"]).decode("utf-8", errors="replace")
        iso_name = res["iso_filename"]
        expected = res["checksum_value"].lower()
        m = re.search(rf"^SHA256\s+\({re.escape(iso_name)}\)\s+=\s+([0-9a-fA-F]{{64}})$", txt, re.MULTILINE)
        if not m or m.group(1).lower() != expected:
            fail(f"freebsd-{arch}: checksum file verification failed for {res['checksum_url']}")
        print(f"  [OK] freebsd-{arch}: {iso_name} -> sha256:{expected[:16]}... ({res['checksum_url']})")

    # Haiku (amd64 only): .iso.sha256 + .minisig
    res = run_resolve(resolver, "haiku", "amd64")
    txt = fetch_bytes(res["checksum_url"]).decode("utf-8", errors="replace")
    iso_name = res["iso_filename"]
    expected = res["checksum_value"].lower()
    if expected not in txt.lower() or iso_name not in txt:
        fail(f"haiku-amd64: checksum file verification failed for {res['checksum_url']}")
    minisig_text = fetch_bytes(res["signature_url"]).decode("utf-8", errors="replace")
    if "untrusted comment:" not in minisig_text:
        fail(f"haiku-amd64: unexpected .minisig content from {res['signature_url']}")
    print(
        f"  [OK] haiku-amd64: {iso_name} -> sha256:{expected[:16]}... "
        f"(+ .minisig fetched from {res['signature_url']})"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify FNXVM vendor GPG keyrings and live checksum/signature inputs.")
    parser.add_argument("--keyring-dir", default="/etc/fnxvm/keys")
    parser.add_argument("--resolver", default="/usr/local/bin/fnxvm-resolve")
    args = parser.parse_args()

    keyring_dir = Path(args.keyring_dir)
    if not shutil.which("gpgv"):
        fail("gpgv is not installed in PATH")

    check_bundled_keyrings(keyring_dir)

    with tempfile.TemporaryDirectory(prefix="fnxvm-verify-") as tmp:
        tmpdir = Path(tmp)

        print("==> Live gpgv verification of vendor SHA256SUMS + signatures (Debian, Ubuntu, Omarchy)")
        deb_amd64_gnome = run_resolve(args.resolver, "debian", "amd64", ["--desktop", "gnome"])
        deb_amd64_kde = run_resolve(args.resolver, "debian", "amd64", ["--desktop", "kde"])
        verify_signed_sha256sums(
            "debian-amd64-live",
            [deb_amd64_gnome, deb_amd64_kde],
            keyring_dir / "debian-cd.gpg",
            tmpdir,
        )

        deb_arm64_dvd = run_resolve(args.resolver, "debian", "arm64", ["--desktop", "gnome"])
        verify_signed_sha256sums(
            "debian-arm64-dvd",
            [deb_arm64_dvd],
            keyring_dir / "debian-cd.gpg",
            tmpdir,
        )

        ubu_amd64 = run_resolve(args.resolver, "ubuntu", "amd64")
        verify_signed_sha256sums(
            "ubuntu-amd64",
            [ubu_amd64],
            keyring_dir / "ubuntu-cd.gpg",
            tmpdir,
        )

        ubu_arm64 = run_resolve(args.resolver, "ubuntu", "arm64")
        verify_signed_sha256sums(
            "ubuntu-arm64",
            [ubu_arm64],
            keyring_dir / "ubuntu-cd.gpg",
            tmpdir,
        )

        verify_omarchy(args.resolver, keyring_dir / "omarchy.gpg", tmpdir)
        verify_checksum_only_guests(args.resolver)

    print("==> vendor GPG keyrings & live signature/checksum verification: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
