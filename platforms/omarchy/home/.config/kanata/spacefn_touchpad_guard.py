#!/usr/bin/env python3
"""Linux palm safeguard for Kanata 1.12.0's layer log (trials and user session).

Runs as the desktop user, not root. No TCP server, input-device access,
persistent Hyprland changes, or raw-key logging. A detached pidfd watchdog
restores the touchpad if this log consumer dies, including SIGKILL.
"""
import argparse
import contextlib
import fcntl
import json
import os
import pathlib
import re
import secrets
import select
import signal
import subprocess
import sys
import time


DEVICE = "apple-spi-trackpad"
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
LAYER = re.compile(r"^\s*\(deflayer\s+([A-Za-z0-9_-]+)\b")
PERSISTED_DISABLE = pathlib.Path.home() / ".local/state/omarchy/toggles/hypr/touchpad-disabled-name"


class LayerParser:
    def __init__(self):
        self.waiting = False

    def feed(self, line):
        text = ANSI.sub("", line)
        if "Entered layer:" in text:
            self.waiting = True
            return None
        if self.waiting and (match := LAYER.match(text)):
            self.waiting = False
            return match.group(1)
        return None


def set_enabled(enabled, inherited_fd=None):
    # DEVICE is a fixed, known Hyprland name, still JSON-quoted as Lua data.
    lua = f"hl.device({{ name = {json.dumps(DEVICE)}, enabled = {str(enabled).lower()} }})"
    result = subprocess.run(
        # An independent timeout bounds IPC even if this Python process dies.
        ["/usr/bin/timeout", "--kill-after=1s", "2s", "/usr/bin/hyprctl", "eval", lua],
        capture_output=True, text=True, timeout=4,
        pass_fds=() if inherited_fd is None else (inherited_fd,),
    )
    if result.returncode or result.stdout.strip() != "ok":
        raise RuntimeError(f"touchpad IPC failed: {result.stdout.strip()} {result.stderr.strip()}")


def restore_enabled():
    # Respect an explicit Omarchy disable made by the user during the trial.
    try:
        return PERSISTED_DISABLE.read_text().strip() != DEVICE
    except FileNotFoundError:
        return True


class TouchpadGuard:
    def __init__(self, marker, token, apply=None):
        self.marker = marker
        self.token = token
        self.apply = apply

    def owns_marker(self):
        try:
            return self.marker.read_text().strip() == self.token
        except FileNotFoundError:
            return False

    @contextlib.contextmanager
    def locked(self):
        with self.marker.with_name(self.marker.name + ".lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield lock.fileno()

    def apply_locked(self, enabled, fd):
        if self.apply is None:
            # Inherit the lock through timeout/hyprctl. If this monitor dies
            # mid-IPC, recovery waits for the in-flight disable to finish,
            # rather than racing an enable against a late disable request.
            set_enabled(enabled, inherited_fd=fd)
        else:
            self.apply(enabled)

    def pause(self, force=False):
        with self.locked() as fd:
            owned = self.owns_marker()
            if not owned:
                # Mark BEFORE IPC to cover death immediately after a disable.
                self.marker.write_text(self.token + "\n")
            if force or not owned:
                self.apply_locked(False, fd)

    def restore(self):
        with self.locked() as fd:
            if not self.owns_marker():
                return
            self.apply_locked(restore_enabled(), fd)
            if self.owns_marker():
                self.marker.unlink(missing_ok=True)


def restore_with_retry(guard):
    for attempt in range(3):
        try:
            guard.restore()
            return True
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            if attempt == 2:
                print(f"[SpaceFN guard] Recovery failed: {error}", file=sys.stderr)
                print("Recovery command: omarchy toggle touchpad on", file=sys.stderr)
                return False
            time.sleep(0.1)
    return False


def watchdog(args):
    guard = TouchpadGuard(args.marker, args.token)
    try:
        fd = os.pidfd_open(args.watchdog)
    except ProcessLookupError:
        return 0 if restore_with_retry(guard) else 1
    try:
        poller = select.poll()
        poller.register(fd, select.POLLIN)
        os.write(args.ready_fd, b"1")
        os.close(args.ready_fd)
        # Trials use a 330 s fail-open cap. The session observer uses -1:
        # wait for its death, without silently expiring after five minutes.
        poller.poll(args.watchdog_timeout_ms)
        return 0 if restore_with_retry(guard) else 1
    finally:
        os.close(fd)


def arm_watchdog(marker, token, timeout_ms=330_000):
    read_fd, write_fd = os.pipe()
    child = subprocess.Popen(
        [sys.executable, str(pathlib.Path(__file__).resolve()),
         "--marker", str(marker), "--watchdog", str(os.getpid()),
         "--token", token, "--ready-fd", str(write_fd),
         "--watchdog-timeout-ms", str(timeout_ms)],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        pass_fds=(write_fd,), start_new_session=True,
    )
    os.close(write_fd)
    try:
        readable, _, _ = select.select([read_fd], [], [], 3)
        if not readable or os.read(read_fd, 1) != b"1":
            raise RuntimeError("Could not arm the touchpad recovery watchdog")
    finally:
        os.close(read_fd)
    return child


def require_device(allow_disabled=False):
    if PERSISTED_DISABLE.exists() and not allow_disabled:
        raise RuntimeError("A touchpad is already disabled in Omarchy; enable it before this trial")
    result = subprocess.run(
        ["/usr/bin/hyprctl", "-j", "devices"],
        capture_output=True, text=True, check=True, timeout=2,
    )
    if DEVICE not in {device["name"] for device in json.loads(result.stdout)["mice"]}:
        raise RuntimeError(f"Built-in touchpad {DEVICE!r} is unavailable")


def monitor(args):
    require_device()
    args.marker.parent.mkdir(parents=True, exist_ok=True)
    token = secrets.token_hex(16)
    guard = TouchpadGuard(args.marker, token)
    # Recover a stale marker from a prior interrupted trial before arming.
    if args.marker.exists():
        stale = TouchpadGuard(args.marker, args.marker.read_text().strip())
        if not restore_with_retry(stale):
            raise RuntimeError("Could not recover the prior trial's touchpad state")
    child = arm_watchdog(args.marker, token)
    parser = LayerParser()
    try:
        with args.log.open("w", buffering=1) as log:
            for line in sys.stdin:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)
                layer = parser.feed(line)
                if layer == "nav":
                    guard.pause()
                elif layer is not None:
                    guard.restore()
    finally:
        if restore_with_retry(guard):
            # Normal EOF/signals already restored the device. SIGKILL skips
            # this finally; the detached watchdog then does the restoration.
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=2)
        else:
            # Leave the watchdog armed for another recovery attempt on exit.
            raise RuntimeError("Could not restore the touchpad")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--marker", required=True, type=pathlib.Path)
    parser.add_argument("--log", type=pathlib.Path)
    parser.add_argument("--restore", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--watchdog", type=int)
    parser.add_argument("--token")
    parser.add_argument("--ready-fd", type=int)
    parser.add_argument("--watchdog-timeout-ms", type=int, default=330_000)
    args = parser.parse_args()
    if args.watchdog is not None:
        if args.token is None or args.ready_fd is None:
            parser.error("watchdog requires a token and ready fd")
        return watchdog(args)
    if args.restore:
        if not args.marker.exists():
            return 0
        guard = TouchpadGuard(args.marker, args.marker.read_text().strip())
        return 0 if restore_with_retry(guard) else 1
    if args.check:
        require_device()
        return 0
    if args.log is None:
        parser.error("monitor requires --log")
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda signum, _frame: sys.exit(128 + signum))
    monitor(args)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"[SpaceFN guard] {error}", file=sys.stderr)
        raise SystemExit(1)
