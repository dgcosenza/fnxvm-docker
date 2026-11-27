#!/usr/bin/env python3
"""Headless Chromium (Playwright) test for FNXVM noVNC universal clipboard & TLS.

Verifies against a live running FNXVM container:
  1. HTTP Basic Authentication login to vnc.html without uncaught JS/console errors.
  2. VNC authentication via the noVNC credentials dialog.
  3. Clipboard panel UI controls load and negotiate Extended Clipboard (UTF-8).
  4. Bidirectional UTF-8 clipboard round-trip between the browser and a live
     RFB peer connected to the same QEMU instance:
       - Guest/RFB peer -> noVNC panel AND navigator.clipboard (writeText).
       - noVNC panel ("Copy to VM") -> QEMU -> RFB peer.
       - Device clipboard ("Paste from Device" / readText) -> QEMU -> RFB peer.
       - Canvas Ctrl+V shortcut interception -> QEMU -> RFB peer.
  5. "Type (ASCII)" fallback handles non-ASCII characters gracefully without
     throwing uncaught JS exceptions and reports skipped characters in status.
  6. Optional HTTPS/WSS (--tls-only) verification with WEB_TLS=Y.

Maintainer: Daniel G. Cosenza from FNX Labs
License: MIT
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_rfb_clipboard import BackgroundRFBPeer  # noqa: E402


def run_browser_test(
    web_url: str,
    web_user: str,
    web_password: str,
    vnc_host: str,
    vnc_port: int,
    vnc_password: str,
    tls_only: bool = False,
) -> None:
    page_errors: list[str] = []
    console_errors: list[str] = []

    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True)
        context = browser.new_context(
            http_credentials={"username": web_user, "password": web_password},
            permissions=["clipboard-read", "clipboard-write"],
            ignore_https_errors=web_url.startswith("https://"),
        )
        page = context.new_page()
        page.on("pageerror", lambda err: page_errors.append(str(err)))
        page.on(
            "console",
            lambda msg: console_errors.append(msg.text) if msg.type == "error" else None,
        )

        target_url = f"{web_url.rstrip('/')}/vnc.html"
        resp = page.goto(target_url, wait_until="domcontentloaded", timeout=30000)
        if resp is None or resp.status != 200:
            raise AssertionError(
                f"Expected HTTP 200 for {target_url}, got {resp.status if resp else None}"
            )

        is_secure = page.evaluate("() => window.isSecureContext")
        if not is_secure:
            raise AssertionError(f"Expected window.isSecureContext=true on {target_url}")

        # Authenticate at the VNC credentials prompt
        page.wait_for_selector("#noVNC_credentials_dlg.noVNC_open", timeout=20000)
        page.fill("#noVNC_password_input", vnc_password)
        page.click("#noVNC_credentials_button")

        # Wait until noVNC reports connected
        page.wait_for_selector(":root.noVNC_connected", timeout=20000)
        print(f"Playwright noVNC connected ({target_url}, secureContext={is_secure}): ok")

        # Open Clipboard panel and assert controls + Extended Clipboard status
        page.click("#noVNC_clipboard_button")
        page.wait_for_selector("#noVNC_clipboard.noVNC_open", timeout=10000)

        for sel in (
            "#noVNC_clipboard_status",
            "#noVNC_clipboard_text",
            "#noVNC_clipboard_read_button",
            "#noVNC_clipboard_copy_button",
            "#noVNC_clipboard_send_button",
            "#noVNC_clipboard_type_button",
            "#noVNC_setting_clipboard_sync",
        ):
            if page.locator(sel).count() != 1:
                raise AssertionError(f"Expected exactly 1 element matching {sel}")

        if not page.is_checked("#noVNC_setting_clipboard_sync"):
            raise AssertionError("Expected #noVNC_setting_clipboard_sync to be checked by default")

        page.wait_for_function(
            """() => {
                const el = document.getElementById('noVNC_clipboard_status');
                return el && el.textContent.includes('Extended Clipboard (UTF-8)');
            }""",
            timeout=10000,
        )
        print("Playwright noVNC clipboard panel + Extended Clipboard (UTF-8) status: ok")

        if not tls_only:
            peer = BackgroundRFBPeer(vnc_host, vnc_port, vnc_password)
            try:
                peer.start()

                # 1. Guest/RFB peer -> Browser (panel + system clipboard via writeText)
                guest_msg = "from-vm-café-✓-日本語"
                peer.publish_text(guest_msg)
                page.wait_for_function(
                    """(expected) => {
                        const ta = document.getElementById('noVNC_clipboard_text');
                        return ta && ta.value === expected;
                    }""",
                    arg=guest_msg,
                    timeout=10000,
                )
                sys_clip = page.evaluate("() => navigator.clipboard.readText()")
                if sys_clip != guest_msg:
                    raise AssertionError(
                        f"Expected system clipboard to sync {guest_msg!r}, got {sys_clip!r}"
                    )
                print("Playwright Guest/Peer -> noVNC panel + navigator.clipboard.writeText: ok")

                # 2. Browser panel ("Copy to VM") -> QEMU -> RFB peer
                panel_msg = "from-novnc-panel-ñ-€42"
                page.fill("#noVNC_clipboard_text", panel_msg)
                page.click("#noVNC_clipboard_send_button")
                got_panel = peer.wait_received(timeout=10.0)
                if got_panel != panel_msg:
                    raise AssertionError(
                        f"Expected RFB peer to receive {panel_msg!r}, got {got_panel!r}"
                    )
                print("Playwright noVNC panel 'Copy to VM' -> QEMU -> RFB peer: ok")

                # 3. Browser "Paste from Device" (navigator.clipboard.readText) -> RFB peer
                device_msg = "from-device-clipboard-api-2026"
                page.evaluate("(txt) => navigator.clipboard.writeText(txt)", device_msg)
                page.click("#noVNC_clipboard_read_button")
                got_device = peer.wait_received(timeout=10.0)
                if got_device != device_msg:
                    raise AssertionError(
                        f"Expected RFB peer to receive {device_msg!r}, got {got_device!r}"
                    )
                print("Playwright 'Paste from Device' (readText) -> QEMU -> RFB peer: ok")

                # 4. Canvas Ctrl+V shortcut interception -> QEMU -> RFB peer
                # Focus the canvas first so pointerdown does not pre-sync shortcut_msg,
                # then update the clipboard and verify Ctrl+V triggers sync.
                shortcut_msg = "from-canvas-ctrl-v-sync"
                page.click("#noVNC_clipboard_button")  # close panel
                page.wait_for_selector("#noVNC_clipboard:not(.noVNC_open)", timeout=5000)
                canvas = page.locator("#noVNC_container canvas").first
                canvas.click()
                page.evaluate("(txt) => navigator.clipboard.writeText(txt)", shortcut_msg)
                page.keyboard.press("Control+v")
                got_shortcut = peer.wait_received(timeout=10.0)
                if got_shortcut != shortcut_msg:
                    raise AssertionError(
                        f"Expected Ctrl+V interception to sync {shortcut_msg!r}, got {got_shortcut!r}"
                    )
                print("Playwright canvas Ctrl+V interception -> QEMU -> RFB peer: ok")

                # 5. Type (ASCII) fallback handles non-ASCII cleanly without JS error
                page.click("#noVNC_clipboard_button")
                page.wait_for_selector("#noVNC_clipboard.noVNC_open", timeout=5000)
                page.fill("#noVNC_clipboard_text", "hi café")
                page.click("#noVNC_clipboard_type_button")
                page.wait_for_function(
                    """() => {
                        const el = document.getElementById('noVNC_clipboard_status');
                        return el && el.textContent.includes('skipped 1 non-ASCII');
                    }""",
                    timeout=10000,
                )
                print("Playwright Type (ASCII) non-ASCII graceful handling: ok")
            finally:
                peer.stop()

        browser.close()

    if page_errors or console_errors:
        raise AssertionError(
            f"Browser JS errors detected: page_errors={page_errors!r}, console_errors={console_errors!r}"
        )
    print("Playwright zero JS page/console errors: ok")


def main() -> int:
    parser = argparse.ArgumentParser(description="Playwright noVNC universal clipboard test.")
    parser.add_argument("--web-url", required=True)
    parser.add_argument("--web-user", required=True)
    parser.add_argument("--web-password", required=True)
    parser.add_argument("--vnc-host", default="127.0.0.1")
    parser.add_argument("--vnc-port", type=int, required=True)
    parser.add_argument("--vnc-password", required=True)
    parser.add_argument("--tls-only", action="store_true")
    args = parser.parse_args()

    run_browser_test(
        web_url=args.web_url,
        web_user=args.web_user,
        web_password=args.web_password,
        vnc_host=args.vnc_host,
        vnc_port=args.vnc_port,
        vnc_password=args.vnc_password,
        tls_only=args.tls_only,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
