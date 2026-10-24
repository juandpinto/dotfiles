#!/usr/bin/env python3
"""Unprivileged, graphical-session palm guard for the root Kanata service.

Reads only filtered layer/service journal messages. A compositor event socket
is used only to detect config reloads; window titles/events are never logged.
"""
import json
import os
import pathlib
import re
import secrets
import selectors
import signal
import socket
import subprocess
import sys
import time

from spacefn_touchpad_guard import (
    LayerParser, TouchpadGuard, arm_watchdog, require_device, restore_with_retry,
)


UNIT = "kanata.service"
ACTIVE = {"active", "activating", "reloading"}
JOURNAL_FILTER = r"Entered layer:|\(deflayer[[:space:]]|kanata\.service"


def service_snapshot():
    result = subprocess.run(
        ["/usr/bin/systemctl", "show", UNIT, "--property=ActiveState,InvocationID", "--no-pager"],
        capture_output=True, text=True, check=True, timeout=3,
    )
    fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    return fields.get("ActiveState", "inactive"), fields.get("InvocationID", "")


class SessionState:
    def __init__(self, guard, publish=lambda: None):
        self.guard = guard
        self.publish = publish
        self.service_state = "inactive"
        self.invocation = ""
        self.layer = "base"
        self.parser = LayerParser()

    def update_service(self, state, invocation):
        changed = invocation != self.invocation or state not in ACTIVE
        if changed:
            self.guard.restore()
            self.layer = "base"
            self.parser = LayerParser()
        self.service_state, self.invocation = state, invocation
        self.publish()

    def journal(self, record, refresh):
        # Manager lifecycle messages trigger a real snapshot rather than
        # trusting/replaying an old 'stopped' entry from a prior invocation.
        if record.get("UNIT") == UNIT:
            refresh()
            return
        invocation = record.get("_SYSTEMD_INVOCATION_ID", "")
        if invocation != self.invocation:
            refresh()
        if self.service_state not in ACTIVE or not invocation or invocation != self.invocation:
            return
        self.message(record)

    def apply_layer(self):
        if self.layer == "nav" and self.service_state in ACTIVE:
            self.guard.pause()
        else:
            self.guard.restore()
        self.publish()

    def message(self, record, apply=True):
        message = record.get("MESSAGE", "")
        if isinstance(message, list):
            message = bytes(message).decode(errors="replace")
        for line in str(message).splitlines():
            layer = self.parser.feed(line)
            if layer is None:
                continue
            self.layer = layer
            if apply:
                self.apply_layer()

    def compositor_reload(self):
        if self.layer == "nav" and self.service_state in ACTIVE:
            self.guard.pause(force=True)
        self.publish()


def run():
    require_device(allow_disabled=True)
    runtime = pathlib.Path(os.environ["XDG_RUNTIME_DIR"]) / "kanata"
    runtime.mkdir(mode=0o700, exist_ok=True)
    marker = runtime / "touchpad-paused"
    if marker.exists():
        stale = TouchpadGuard(marker, marker.read_text().strip())
        if not restore_with_retry(stale):
            raise RuntimeError("could not recover a prior palm-guard marker")
    guard = TouchpadGuard(marker, secrets.token_hex(16))
    watchdog = arm_watchdog(marker, guard.token, timeout_ms=-1)
    state = SessionState(guard)

    def publish():
        value = {"service": state.service_state, "layer": state.layer,
                 "invocation": state.invocation, "touchpad_paused": guard.owns_marker()}
        temporary = runtime / "guard-state.tmp"
        temporary.write_text(json.dumps(value) + "\n")
        temporary.replace(runtime / "guard-state.json")

    state.publish = publish

    def refresh():
        state.update_service(*service_snapshot())

    # Recover the current layer once, not dozens of historical toggles. Follow
    # from the exact journal cursor so changes during startup cannot be missed.
    since = f"@{time.time():.6f}"
    command = ["/usr/bin/journalctl", "--system", "--unit", UNIT,
               "--output=json", "--no-pager", "--grep", JOURNAL_FILTER]
    history_result = subprocess.run(command + ["--lines=64"], capture_output=True,
                                    text=True, timeout=5)
    # journalctl --grep returns 1 when the service has no matching entries yet.
    if history_result.returncode not in (0, 1) or (history_result.returncode and history_result.stderr.strip()):
        raise RuntimeError(f"cannot read service journal: {history_result.stderr.strip()}")
    history = [json.loads(line) for line in history_result.stdout.splitlines() if line]
    refresh()
    if state.service_state in ACTIVE:
        for record in history:
            if record.get("_SYSTEMD_INVOCATION_ID") == state.invocation:
                state.message(record, apply=False)
    state.apply_layer()
    cursor = history[-1].get("__CURSOR") if history else None
    position = ["--after-cursor", cursor] if cursor else ["--since", since]
    selector = selectors.DefaultSelector()
    follower = subprocess.Popen(
        command + ["--follow", "--no-tail", *position],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
    )
    os.set_blocking(follower.stdout.fileno(), False)
    selector.register(follower.stdout, selectors.EVENT_READ, "journal")
    signature = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", signature):
        raise RuntimeError("invalid compositor instance signature")
    event_path = runtime.parent / "hypr" / signature / ".socket2.sock"
    compositor = None
    journal_buffer = b""
    event_buffer = b""
    next_snapshot = 0.0
    next_connect = 0.0
    try:
        refresh()
        print("Kanata palm guard ready; reading layer logs without input-device permissions.", flush=True)
        while True:
            now = time.monotonic()
            if now >= next_snapshot:
                refresh()  # Safety fallback if a lifecycle event was missed.
                next_snapshot = now + 15
            if compositor is None and now >= next_connect:
                candidate = socket.socket(socket.AF_UNIX)
                candidate.settimeout(1)
                try:
                    candidate.connect(str(event_path))
                    candidate.setblocking(False)
                    selector.register(candidate, selectors.EVENT_READ, "compositor")
                    compositor = candidate
                    event_buffer = b""
                    state.compositor_reload()
                except OSError:
                    candidate.close()
                next_connect = now + 2
            if follower.poll() is not None:
                raise RuntimeError(f"journal follower exited: {follower.returncode}")
            for key, _ in selector.select(timeout=1):
                if key.data == "journal":
                    chunk = os.read(follower.stdout.fileno(), 65536)
                    if not chunk:
                        raise RuntimeError("journal stream closed")
                    journal_buffer += chunk
                    while b"\n" in journal_buffer:
                        line, journal_buffer = journal_buffer.split(b"\n", 1)
                        if line:
                            state.journal(json.loads(line), refresh)
                else:
                    chunk = compositor.recv(65536)
                    if not chunk:
                        selector.unregister(compositor)
                        compositor.close()
                        compositor = None
                        guard.restore()  # Fail open while the event connection is down.
                        publish()
                        continue
                    event_buffer += chunk
                    while b"\n" in event_buffer:
                        line, event_buffer = event_buffer.split(b"\n", 1)
                        if line.split(b">>", 1)[0] == b"configreloaded":
                            state.compositor_reload()
                    # No event payloads are logged or retained after framing.
                    if len(event_buffer) > 1_048_576:
                        raise RuntimeError("oversized compositor event")
    finally:
        selector.close()
        if compositor is not None:
            compositor.close()
        follower.terminate()
        try:
            follower.wait(timeout=3)
        except subprocess.TimeoutExpired:
            follower.kill()
            follower.wait(timeout=3)
        restored = restore_with_retry(guard)
        if restored:
            watchdog.terminate()
            watchdog.wait(timeout=3)
        # If recovery failed, leave the pidfd watchdog armed for another try.


def main():
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda signum, _frame: sys.exit(128 + signum))
    run()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Kanata palm guard: {error}", file=sys.stderr)
        raise SystemExit(1)
