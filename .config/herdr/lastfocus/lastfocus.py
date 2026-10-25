# %%
"""tmux-style last-focused pane, tab, and workspace toggles for Herdr.

A small daemon subscribes to Herdr's focus events and records a history of focus positions per server. Three actions walk that history backwards the way tmux's `last-pane`, `last-window`, and `switch-client -l` do: the previous pane in the current tab, the previous tab in the current workspace, and the previous workspace. Design after pedrobarco/herdr-lastfocus, re-implemented to read focus from `session.snapshot` so it does not depend on the event delivery order.

Standard library only; Python 3.9+ on Linux and macOS.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import logging
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

HISTORY_CAP = 500
SCOPES = ("pane", "tab", "workspace")
FOCUS_EVENTS = ("pane.focused", "tab.focused", "workspace.focused")
IDLE_PING_SECONDS = 30.0
log = logging.getLogger("lastfocus")


# %%
def socket_path() -> Path:
    """Return the Herdr socket this invocation belongs to."""
    path = os.environ.get("HERDR_SOCKET_PATH")
    if not path:
        sys.exit("lastfocus: HERDR_SOCKET_PATH is not set; run through Herdr")
    return Path(path)


def state_dir() -> Path:
    """Return the Herdr-provided plugin state directory."""
    path = os.environ.get("HERDR_PLUGIN_STATE_DIR")
    if not path:
        sys.exit(
            "lastfocus: HERDR_PLUGIN_STATE_DIR is not set; run through Herdr"
        )
    directory = Path(path)
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def history_path(sock: Path) -> Path:
    """Return the history file for one Herdr server; sessions never share history."""
    key = hashlib.sha1(str(sock).encode()).hexdigest()[:16]
    return state_dir() / f"history-{key}.json"


def request(sock: Path, method: str, params: dict | None = None) -> dict:
    """Send one request on a fresh connection and return its result."""
    with socket.socket(socket.AF_UNIX) as conn:
        conn.settimeout(5)
        conn.connect(str(sock))
        send(
            conn, {"id": "lastfocus", "method": method, "params": params or {}}
        )
        reply = LineReader(conn).next()
    if "error" in reply:
        raise RuntimeError(
            f"{method}: {reply['error'].get('message', reply['error'])}"
        )
    return reply.get("result", {})


def send(conn: socket.socket, message: dict) -> None:
    """Write one newline-delimited JSON request."""
    conn.sendall(json.dumps(message).encode() + b"\n")


class LineReader:
    """Yield newline-delimited JSON messages, however the socket chunks them."""

    def __init__(self, conn: socket.socket) -> None:
        self.conn = conn
        self.buffer = b""

    def next(self) -> dict:
        while b"\n" not in self.buffer:
            chunk = self.conn.recv(65536)
            if not chunk:
                raise ConnectionError("Herdr closed the connection")
            self.buffer += chunk
        line, self.buffer = self.buffer.split(b"\n", 1)
        return json.loads(line)


def focused(sock: Path) -> dict | None:
    """Return the focused workspace, tab, and pane ids, plus the live id sets."""
    snapshot = request(sock, "session.snapshot")["snapshot"]
    entry = {scope: snapshot.get(f"focused_{scope}_id") for scope in SCOPES}
    if not all(entry.values()):
        return None
    entry["live"] = {
        "pane": {p["pane_id"] for p in snapshot["panes"]},
        "tab": {t["tab_id"] for t in snapshot["tabs"]},
        "workspace": {w["workspace_id"] for w in snapshot["workspaces"]},
    }
    return entry


def load_history(path: Path) -> list[dict[str, str]]:
    """Return the recorded focus history, oldest first."""
    try:
        return json.loads(path.read_text())["history"]
    except (OSError, ValueError, KeyError):
        return []


def save_history(path: Path, history: list[dict[str, str]]) -> None:
    """Write the history atomically so an action never reads a partial file."""
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps({"history": history[-HISTORY_CAP:]}))
    tmp.replace(path)


# %%
def toggle(scope: str) -> None:
    """Focus the previous pane in this tab, tab in this workspace, or workspace."""
    sock = socket_path()
    now = focused(sock)
    if now is None:
        return
    history = load_history(history_path(sock))
    # Walk backwards from the current position. Entries equal to the current focus are skipped, so a toggle still works when the daemon has not recorded the newest position yet.
    for entry in reversed(history):
        if entry[scope] == now[scope]:
            continue
        if scope == "pane" and entry["tab"] != now["tab"]:
            continue
        if scope == "tab" and entry["workspace"] != now["workspace"]:
            continue
        if entry[scope] not in now["live"][scope]:
            continue  # Closed since; keep looking.
        request(sock, f"{scope}.focus", {f"{scope}_id": entry[scope]})
        return


# %%
def ensure_daemon() -> None:
    """Start the recording daemon for this server unless one is already running."""
    lock_path = history_path(socket_path()).with_suffix(".lock")
    with open(lock_path, "a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return  # A live daemon holds the lock.
        fcntl.flock(lock, fcntl.LOCK_UN)
    log_path = history_path(socket_path()).with_suffix(".log")
    with open(log_path, "ab") as log_file:
        subprocess.Popen(
            [sys.executable, "-B", __file__, "daemon", "--run"],
            stdin=subprocess.DEVNULL,
            stdout=log_file,
            stderr=log_file,
            start_new_session=True,
            close_fds=True,
        )


def run_daemon() -> None:
    """Record focus history until the Herdr server goes away."""
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )
    sock = socket_path()
    path = history_path(sock)
    # Held open for the daemon's lifetime; the OS releases it when the process exits.
    lock = open(path.with_suffix(".lock"), "a+")  # noqa: SIM115
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log.info("another daemon already records %s", sock)
        return
    pid_path = path.with_suffix(".pid")
    pid_path.write_text(str(os.getpid()))
    log.info("recording focus for %s (pid %d)", sock, os.getpid())
    backoff = 0.2
    try:
        while sock.exists():
            try:
                subscribe_and_record(sock, path)
                backoff = 0.2
            except (OSError, RuntimeError, ValueError) as error:
                if not sock.exists():
                    break
                log.warning(
                    "stream ended (%s); reconnecting in %.1fs", error, backoff
                )
                time.sleep(backoff)
                backoff = min(backoff * 2, 5.0)
    finally:
        log.info("server socket gone; exiting")
        # The server is gone, so its history is stale. The empty .lock stays: unlinking it could let a late-starting sibling lock a fresh inode.
        for suffix in (".pid", ".json", ".log"):
            path.with_suffix(suffix).unlink(missing_ok=True)


def subscribe_and_record(sock: Path, path: Path) -> None:
    """Hold one event subscription, snapshotting focus after each focus event."""
    record(sock, path)
    with socket.socket(socket.AF_UNIX) as conn:
        conn.connect(str(sock))
        subscriptions = [{"type": name} for name in FOCUS_EVENTS]
        send(
            conn,
            {
                "id": "sub",
                "method": "events.subscribe",
                "params": {"subscriptions": subscriptions},
            },
        )
        reader = LineReader(conn)
        ack = reader.next()
        if "error" in ack:
            raise RuntimeError(f"subscribe failed: {ack['error']}")
        conn.settimeout(IDLE_PING_SECONDS)
        while True:
            try:
                message = reader.next()
            except socket.timeout:  # noqa: UP041 (distinct from TimeoutError on 3.9)
                # Raises if the server is gone but its socket file lingers.
                request(sock, "ping")
                continue
            if "event" in message:
                record(sock, path)


def record(sock: Path, path: Path) -> None:
    """Append the current focus to history when it changed."""
    now = focused(sock)
    if now is None:
        return
    entry = {scope: now[scope] for scope in SCOPES}
    history = load_history(path)
    if history and history[-1] == entry:
        return
    history.append(entry)
    save_history(path, history)


# %%
def main(argv: list[str]) -> None:
    """Dispatch `daemon --ensure|--run` or one of the toggle actions."""
    parser = argparse.ArgumentParser(
        prog="lastfocus", description=__doc__.split("\n")[0]
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    daemon = subparsers.add_parser(
        "daemon", help="record focus history for this Herdr server"
    )
    mode = daemon.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--ensure",
        action="store_true",
        help="start the daemon if none is running",
    )
    mode.add_argument(
        "--run",
        action="store_true",
        help="run the recording loop in the foreground",
    )
    for scope in SCOPES:
        subparsers.add_parser(
            f"last-{scope}", help=f"focus the previously focused {scope}"
        )
    args = parser.parse_args(argv)
    if args.command == "daemon":
        run_daemon() if args.run else ensure_daemon()
    else:
        toggle(args.command.split("-", 1)[1])


if __name__ == "__main__":
    main(sys.argv[1:])
