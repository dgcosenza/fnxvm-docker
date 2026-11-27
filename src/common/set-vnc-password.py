#!/usr/bin/env python3
"""Set QEMU VNC (and optional SPICE) password via the private QMP Unix socket.

Reads the password from a mode-0600 ephemeral tmpfs file, deletes that file
immediately, waits for QEMU's QMP socket to appear, and executes QMP
`set_password` so no password ever appears in QEMU command-line arguments.

Maintainer: Daniel G. Cosenza from FNX Labs
License: MIT
"""
from __future__ import annotations

import argparse
import asyncio
import os
import sys
import time

from qemu.qmp import QMPClient


def read_and_remove_secret(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            secret = fh.read().rstrip("\r\n")
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    return secret


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return True
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False


async def apply_passwords(
    qmp_sock: str,
    password: str,
    protocols: list[str],
    timeout: float,
    qemu_pid: int,
) -> int:
    deadline = time.monotonic() + timeout
    last_err: Exception | None = None

    while time.monotonic() < deadline:
        if qemu_pid > 0 and not pid_alive(qemu_pid):
            print("ERROR: QEMU exited before VNC password could be applied via QMP.", file=sys.stderr)
            return 1
        if os.path.exists(qmp_sock):
            qmp = QMPClient("fnxvm-auth")
            try:
                await qmp.connect(qmp_sock)
                for proto in protocols:
                    await qmp.execute(
                        "set_password",
                        {"protocol": proto, "password": password},
                    )
                await qmp.disconnect()
                ready_marker = os.path.join(os.path.dirname(qmp_sock), "vnc-auth.ready")
                try:
                    with open(ready_marker, "w", encoding="utf-8") as fh:
                        fh.write(",".join(protocols) + "\n")
                except OSError:
                    pass
                return 0
            except Exception as exc:
                last_err = exc
                try:
                    await qmp.disconnect()
                except Exception:
                    pass
        await asyncio.sleep(0.15)

    print(
        f"ERROR: Timed out waiting for QMP socket {qmp_sock} to set password ({last_err}).",
        file=sys.stderr,
    )
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply VNC/SPICE password over QEMU QMP.")
    parser.add_argument("--qmp-sock", required=True)
    parser.add_argument("--password-file", required=True)
    parser.add_argument("--protocols", default="vnc")
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--qemu-pid", type=int, default=0)
    args = parser.parse_args()

    password = read_and_remove_secret(args.password_file)
    if not password:
        print("ERROR: VNC password file was empty; refusing to leave VNC unconfigured.", file=sys.stderr)
        return 1

    protocols = [p.strip() for p in args.protocols.split(",") if p.strip()]
    return asyncio.run(
        apply_passwords(args.qmp_sock, password, protocols, args.timeout, args.qemu_pid)
    )


if __name__ == "__main__":
    raise SystemExit(main())
