#!/usr/bin/env python3
"""Authenticated RFB 3.8 + Extended Clipboard protocol test client for FNXVM.

Pure Python 3 standard library implementation (no external crypto dependencies):
  1. Verifies VNC server offers RFB VNC Authentication (security type 2) only,
     never unauthenticated None (type 1), and rejects a wrong password.
  2. Authenticates two concurrent shared RFB peers with the real QMP-configured
     VNC password using standard RFB DES challenge-response (RFC 6143 §7.2.2).
  3. Negotiates QEMU's Extended Clipboard pseudo-encoding (-1063131698 /
     0xC0A1E5CE) and verifies QEMU advertises CAPS|REQUEST|NOTIFY|PROVIDE|TEXT.
  4. Exercises bidirectional multi-byte UTF-8 Extended Clipboard round-trips
     (Peer A -> QEMU clipboard hub -> Peer B and reverse) plus legacy
     ClientCutText (ISO-8859-1) interoperability.

Note: QEMU's clipboard manager broadcasts every clipboard update to all
registered peers (connected VNC clients AND the qemu-vdagent chardev). Full
guest-side spice-vdagent delivery requires a booted guest OS running
spice-vdagent; this test verifies the complete RFB/QEMU server side live.

Maintainer: Daniel G. Cosenza from FNX Labs
License: MIT
"""
from __future__ import annotations

import argparse
import queue
import socket
import struct
import sys
import threading
import time
import zlib

# RFB encodings and Extended Clipboard constants (RFC 6143 / QEMU ui/vnc.h)
ENCODING_RAW = 0
ENCODING_EXTENDED_CLIPBOARD = -1063131698  # 0xC0A1E5CE

EXT_CLIP_TEXT = 1 << 0
EXT_CLIP_CAPS = 1 << 24
EXT_CLIP_REQUEST = 1 << 25
EXT_CLIP_PEEK = 1 << 26
EXT_CLIP_NOTIFY = 1 << 27
EXT_CLIP_PROVIDE = 1 << 28

# Standard FIPS 46-3 DES tables for RFB VNC Authentication (RFC 6143 §7.2.2)
_IP = (
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7,
)
_FP = (
    40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25,
)
_E = (
    32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9,
    8, 9, 10, 11, 12, 13, 12, 13, 14, 15, 16, 17,
    16, 17, 18, 19, 20, 21, 20, 21, 22, 23, 24, 25,
    24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1,
)
_P = (
    16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10,
    2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25,
)
_PC1 = (
    57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18,
    10, 2, 59, 51, 43, 35, 27, 19, 11, 3, 60, 52, 44, 36,
    63, 55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22,
    14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 28, 20, 12, 4,
)
_PC2 = (
    14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10,
    23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2,
    41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
    44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32,
)
_SHIFTS = (1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1)
_SBOX = (
    (14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7,
     0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8,
     4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0,
     15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13),
    (15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10,
     3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5,
     0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15,
     13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9),
    (10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8,
     13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1,
     13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7,
     1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12),
    (7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15,
     13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9,
     10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4,
     3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14),
    (2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9,
     14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6,
     4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14,
     11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3),
    (12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11,
     10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8,
     9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6,
     4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13),
    (4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1,
     13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6,
     1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2,
     6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12),
    (13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7,
     1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2,
     7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8,
     2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11),
)


def _permute(val: int, table: tuple[int, ...], width: int) -> int:
    out = 0
    for pos in table:
        out = (out << 1) | ((val >> (width - pos)) & 1)
    return out


def _des_subkeys(key8: bytes) -> list[int]:
    key_int = int.from_bytes(key8, "big")
    k56 = _permute(key_int, _PC1, 64)
    c = (k56 >> 28) & 0x0FFFFFFF
    d = k56 & 0x0FFFFFFF
    subkeys = []
    for shift in _SHIFTS:
        c = ((c << shift) | (c >> (28 - shift))) & 0x0FFFFFFF
        d = ((d << shift) | (d >> (28 - shift))) & 0x0FFFFFFF
        subkeys.append(_permute((c << 28) | d, _PC2, 56))
    return subkeys


def des_encrypt_block(key8: bytes, block8: bytes) -> bytes:
    subkeys = _des_subkeys(key8)
    state = _permute(int.from_bytes(block8, "big"), _IP, 64)
    left = (state >> 32) & 0xFFFFFFFF
    right = state & 0xFFFFFFFF
    for sk in subkeys:
        expanded = _permute(right, _E, 32) ^ sk
        s_out = 0
        for idx in range(8):
            chunk = (expanded >> (42 - 6 * idx)) & 0x3F
            row = ((chunk & 0x20) >> 4) | (chunk & 0x01)
            col = (chunk >> 1) & 0x0F
            s_out = (s_out << 4) | _SBOX[idx][row * 16 + col]
        f_val = _permute(s_out, _P, 32)
        left, right = right, left ^ f_val
    pre_out = (right << 32) | left
    return _permute(pre_out, _FP, 64).to_bytes(8, "big")


def vnc_auth_response(password: str, challenge: bytes) -> bytes:
    if len(challenge) != 16:
        raise ValueError(f"Expected 16-byte RFB challenge, got {len(challenge)}")
    raw = password.encode("latin-1", errors="ignore")[:8].ljust(8, b"\x00")
    # RFC 6143 §7.2.2 reverses the bit order in each key byte.
    key = bytes(int(f"{b:08b}"[::-1], 2) for b in raw)
    return des_encrypt_block(key, challenge[:8]) + des_encrypt_block(key, challenge[8:16])


class RFBClient:
    """Minimal authenticated RFB 3.8 client supporting Extended Clipboard."""

    def __init__(self, host: str, port: int, password: str, timeout: float = 10.0) -> None:
        self.host = host
        self.port = port
        self.password = password
        self.timeout = timeout
        self.sock: socket.socket | None = None
        self.bpp = 4
        self.desktop_name = ""
        self.server_clip_caps = 0
        self.ext_clip_ready = False
        self._lock = threading.Lock()

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None

    def __enter__(self) -> "RFBClient":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _recv_exact(self, n: int) -> bytes:
        assert self.sock is not None
        buf = bytearray()
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise EOFError(f"RFB socket closed after {len(buf)}/{n} bytes")
            buf.extend(chunk)
        return bytes(buf)

    def _sendall(self, data: bytes) -> None:
        assert self.sock is not None
        with self._lock:
            self.sock.sendall(data)

    def connect(self, *, expect_auth_failure: bool = False, negotiate_ext_clip: bool = True) -> int:
        self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
        self.sock.settimeout(self.timeout)

        banner = self._recv_exact(12)
        if not banner.startswith(b"RFB "):
            raise AssertionError(f"Invalid RFB banner: {banner!r}")
        self._sendall(b"RFB 003.008\n")

        n_types = self._recv_exact(1)[0]
        if n_types == 0:
            raise AssertionError("RFB server offered 0 security types")
        sec_types = list(self._recv_exact(n_types))
        if 1 in sec_types:
            raise AssertionError(f"VNC allows unauthenticated security type None (1): {sec_types}")
        if 2 not in sec_types:
            raise AssertionError(f"VNC does not advertise VNC Auth (2): {sec_types}")

        self._sendall(b"\x02")
        challenge = self._recv_exact(16)
        self._sendall(vnc_auth_response(self.password, challenge))

        result = struct.unpack("!I", self._recv_exact(4))[0]
        if expect_auth_failure:
            if result == 0:
                raise AssertionError("Expected VNC authentication failure, but server accepted wrong password")
            return result
        if result != 0:
            raise AssertionError(f"VNC authentication failed with SecurityResult={result}")

        # ClientInit: shared-flag = 1 so multiple clients (and noVNC) can attach.
        self._sendall(b"\x01")
        header = self._recv_exact(24)
        _w, _h = struct.unpack("!HH", header[:4])
        bits_per_pixel = header[4]
        self.bpp = max(1, bits_per_pixel // 8)
        name_len = struct.unpack("!I", header[20:24])[0]
        self.desktop_name = self._recv_exact(name_len).decode("utf-8", errors="replace")

        if negotiate_ext_clip:
            self.send_set_encodings([ENCODING_RAW, ENCODING_EXTENDED_CLIPBOARD])
            self._wait_for_server_caps()

        return result

    def send_set_encodings(self, encodings: list[int]) -> None:
        payload = struct.pack("!BBH", 2, 0, len(encodings))
        payload += b"".join(struct.pack("!i", enc) for enc in encodings)
        self._sendall(payload)

    def send_ext_cut_text(self, flags: int, extra: bytes = b"") -> None:
        body = struct.pack("!I", flags) + extra
        msg = struct.pack("!BBBBi", 6, 0, 0, 0, -len(body)) + body
        self._sendall(msg)

    def send_ext_caps(self) -> None:
        flags = (
            EXT_CLIP_CAPS
            | EXT_CLIP_REQUEST
            | EXT_CLIP_PEEK
            | EXT_CLIP_NOTIFY
            | EXT_CLIP_PROVIDE
            | EXT_CLIP_TEXT
        )
        # Max unsolicited text payload size = 0 (always use NOTIFY -> REQUEST -> PROVIDE)
        self.send_ext_cut_text(flags, struct.pack("!I", 0))

    def send_ext_notify(self) -> None:
        self.send_ext_cut_text(EXT_CLIP_NOTIFY | EXT_CLIP_TEXT)

    def send_ext_request(self) -> None:
        self.send_ext_cut_text(EXT_CLIP_REQUEST | EXT_CLIP_TEXT)

    def send_ext_provide(self, text: str) -> None:
        normalized = text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n")
        utf8 = (normalized + "\0").encode("utf-8")
        raw = struct.pack("!I", len(utf8)) + utf8
        compressed = zlib.compress(raw)
        self.send_ext_cut_text(EXT_CLIP_PROVIDE | EXT_CLIP_TEXT, compressed)

    def send_legacy_cut_text(self, text: str) -> None:
        data = text.encode("latin-1", errors="replace")
        msg = struct.pack("!BBBBI", 6, 0, 0, 0, len(data)) + data
        self._sendall(msg)

    def read_message(self, timeout: float | None = None) -> tuple[str, object]:
        assert self.sock is not None
        prev_timeout = self.sock.gettimeout()
        if timeout is not None:
            self.sock.settimeout(timeout)
        try:
            msg_type = self._recv_exact(1)[0]
            if msg_type == 0:  # FramebufferUpdate
                _pad, n_rects = struct.unpack("!BH", self._recv_exact(3))
                for _ in range(n_rects):
                    _x, _y, w, h, enc = struct.unpack("!HHHHi", self._recv_exact(12))
                    if enc == ENCODING_RAW:
                        self._recv_exact(w * h * self.bpp)
                return ("fb_update", n_rects)
            if msg_type == 1:  # SetColourMapEntries
                _pad, _first, count = struct.unpack("!BHH", self._recv_exact(5))
                self._recv_exact(count * 6)
                return ("cmap", count)
            if msg_type == 2:  # Bell
                return ("bell", None)
            if msg_type == 3:  # ServerCutText
                self._recv_exact(3)  # padding
                length = struct.unpack("!i", self._recv_exact(4))[0]
                if length >= 0:
                    data = self._recv_exact(length)
                    return ("legacy_cut_text", data.decode("latin-1", errors="replace"))
                payload = self._recv_exact(-length)
                flags = struct.unpack("!I", payload[:4])[0]
                return ("ext_cut_text", (flags, payload[4:]))
            raise AssertionError(f"Unsupported RFB server message type: {msg_type}")
        finally:
            self.sock.settimeout(prev_timeout)

    def _wait_for_server_caps(self, timeout: float = 5.0) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            remaining = max(0.1, deadline - time.monotonic())
            kind, payload = self.read_message(timeout=remaining)
            if kind == "ext_cut_text":
                flags, _rest = payload  # type: ignore[misc]
                if flags & EXT_CLIP_CAPS:
                    required = (
                        EXT_CLIP_CAPS
                        | EXT_CLIP_REQUEST
                        | EXT_CLIP_NOTIFY
                        | EXT_CLIP_PROVIDE
                        | EXT_CLIP_TEXT
                    )
                    if (flags & required) != required:
                        raise AssertionError(
                            f"Server Extended Clipboard CAPS missing required bits: 0x{flags:08x}"
                        )
                    self.server_clip_caps = flags
                    self.send_ext_caps()
                    self.ext_clip_ready = True
                    return
        raise TimeoutError("Timed out waiting for QEMU Extended Clipboard CAPS")

    @staticmethod
    def decode_ext_provide(rest: bytes) -> str:
        raw = zlib.decompress(rest)
        if len(raw) < 4:
            raise AssertionError(f"Extended Clipboard PROVIDE payload too short: {len(raw)}")
        tlen = struct.unpack("!I", raw[:4])[0]
        if 4 + tlen > len(raw):
            raise AssertionError(f"Truncated PROVIDE text length {tlen} > {len(raw) - 4}")
        text = raw[4 : 4 + tlen].decode("utf-8")
        if text.endswith("\0"):
            text = text[:-1]
        return text.replace("\r\n", "\n")


class BackgroundRFBPeer:
    """Runs an RFBClient in a background thread for live browser <-> QEMU testing."""

    def __init__(self, host: str, port: int, password: str) -> None:
        self.client = RFBClient(host, port, password, timeout=10.0)
        self.received: queue.Queue[str] = queue.Queue()
        self._stop = threading.Event()
        self._pending_text: str | None = None
        self._thread: threading.Thread | None = None
        self.error: Exception | None = None

    def start(self) -> None:
        self.client.connect(negotiate_ext_clip=True)
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self.client.close()
        if self._thread is not None:
            self._thread.join(timeout=3.0)

    def publish_text(self, text: str) -> None:
        self._pending_text = text
        self.client.send_ext_notify()

    def wait_received(self, timeout: float = 10.0) -> str:
        if self.error is not None:
            raise RuntimeError(f"Background RFB peer failed: {self.error}") from self.error
        return self.received.get(timeout=timeout)

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                kind, payload = self.client.read_message(timeout=0.3)
            except socket.timeout:
                continue
            except (EOFError, OSError):
                if self._stop.is_set():
                    return
                raise
            except Exception as exc:
                self.error = exc
                return

            if kind == "legacy_cut_text":
                self.received.put(str(payload))
            elif kind == "ext_cut_text":
                flags, rest = payload  # type: ignore[misc]
                if (flags & EXT_CLIP_NOTIFY) and (flags & EXT_CLIP_TEXT):
                    self.client.send_ext_request()
                elif (flags & EXT_CLIP_REQUEST) and (flags & EXT_CLIP_TEXT):
                    if self._pending_text is not None:
                        self.client.send_ext_provide(self._pending_text)
                elif (flags & EXT_CLIP_PROVIDE) and (flags & EXT_CLIP_TEXT):
                    self.received.put(RFBClient.decode_ext_provide(rest))


def run_protocol_suite(host: str, port: int, password: str) -> None:
    # 1. Negative auth check: wrong password must be rejected.
    with RFBClient(host, port, "wrongpw1", timeout=5.0) as bad:
        res = bad.connect(expect_auth_failure=True, negotiate_ext_clip=False)
        print(f"RFB wrong password rejected (SecurityResult={res}): ok")

    # 2. Connect two authenticated shared peers and negotiate Extended Clipboard.
    peer_a = BackgroundRFBPeer(host, port, password)
    peer_b = BackgroundRFBPeer(host, port, password)
    try:
        peer_a.start()
        peer_b.start()
        print(
            f"RFB Extended Clipboard CAPS negotiated on both peers "
            f"(desktop={peer_a.client.desktop_name!r}, flags=0x{peer_a.client.server_clip_caps:08x}): ok"
        )

        # 3. Forward multi-byte UTF-8 Extended Clipboard round-trip (Peer A -> QEMU -> Peer B)
        msg_forward = "FNXVM clipboard UTF-8: café — 日本語 ✓ €100\nline 2"
        peer_a.publish_text(msg_forward)
        got_b = peer_b.wait_received(timeout=10.0)
        if got_b != msg_forward:
            raise AssertionError(f"Forward UTF-8 mismatch: got {got_b!r}, expected {msg_forward!r}")
        print("RFB Extended Clipboard forward UTF-8 round-trip (Peer A -> QEMU -> Peer B): ok")

        # 4. Reverse multi-byte UTF-8 Extended Clipboard round-trip (Peer B -> QEMU -> Peer A)
        msg_reverse = "reverse clipboard sync: áéíóú ñ ¿¡"
        peer_b.publish_text(msg_reverse)
        got_a = peer_a.wait_received(timeout=10.0)
        if got_a != msg_reverse:
            raise AssertionError(f"Reverse UTF-8 mismatch: got {got_a!r}, expected {msg_reverse!r}")
        print("RFB Extended Clipboard reverse UTF-8 round-trip (Peer B -> QEMU -> Peer A): ok")

        # 5. Legacy ClientCutText (ISO-8859-1) -> QEMU clipboard manager -> Extended peer
        msg_legacy = "legacy-client-cut-text-latin1-cafe"
        peer_a.client.send_legacy_cut_text(msg_legacy)
        got_legacy = peer_b.wait_received(timeout=10.0)
        if got_legacy != msg_legacy:
            raise AssertionError(
                f"Legacy ClientCutText mismatch: got {got_legacy!r}, expected {msg_legacy!r}"
            )
        print("RFB legacy ClientCutText -> QEMU -> Extended Clipboard peer: ok")
    finally:
        peer_a.stop()
        peer_b.stop()


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify FNXVM RFB auth and Extended Clipboard.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--password", required=True)
    args = parser.parse_args()
    run_protocol_suite(args.host, args.port, args.password)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
