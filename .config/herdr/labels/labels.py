# %%
"""Sidebar numbers, clean pi titles, and automatic tab names for Herdr.

A small daemon subscribes to Herdr's layout events and, after each one, reads `session.snapshot` and derives three kinds of display values from it:

- `$idx` on every workspace and agent pane: its 1-based position in the expanded sidebar, which is the number that `prefix+w` + digit, `switch_workspace`, and `focus_agent` jump to.
- `$title` on every agent pane: the terminal title, where pi's `π - <session> - <dir>` becomes just `<session>`.
- Tab labels, like tmux's `#I:#W`: the tab's position, which is what `switch_tab` jumps to, then the session name of the tab's agent or the program named in its terminal title, like tmux's automatic-rename. Tabs you named yourself keep that name, numbered like the rest.

Only values that differ from what Herdr already shows are written, so a quiet session costs one snapshot read per event. Standard library only; Python 3.9+ on Linux and macOS.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import logging
import os
import re
import socket
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path

SOURCE = "labels"
MAX_TAB_LABEL = 15
TAB_SEPARATOR = ":"
# The index at the front of a label, "2:" in "2:bash", or a bare "2". The rename prompt starts with the full label, so a name typed there may still carry it.
TAB_INDEX = re.compile(r"^\d+(?::|$)")
# Everything that can reorder the sidebar, retitle a pane, or rename a tab. Focus and output events are left out; so is workspace.metadata_updated, which our own workspace writes emit. Pane writes echo as pane.updated, which the diff turns into one extra snapshot and nothing else.
EVENTS = (
    "workspace.created",
    "workspace.updated",
    "workspace.closed",
    "workspace.renamed",
    "workspace.moved",
    "workspace.reordered",
    "worktree.created",
    "worktree.opened",
    "worktree.removed",
    "tab.created",
    "tab.closed",
    "tab.renamed",
    "tab.moved",
    "pane.created",
    "pane.closed",
    "pane.updated",
    "pane.moved",
    "pane.exited",
    "pane.agent_detected",
    "layout.updated",
)
SETTLE_SECONDS = 0.15
IDLE_PING_SECONDS = 30.0
PI_TITLE = re.compile(r"π - (?:(.+) - )?.+")
# A program's title usually leads with its name: "bash - ~/x", "Yazi: x", "init.lua (~/x) - NVIM".
TITLE_SEPARATOR = re.compile(r" - | — |: | \(| \[")
log = logging.getLogger("labels")


# %%
def socket_path() -> Path:
    """Return the Herdr socket this invocation belongs to."""
    path = os.environ.get("HERDR_SOCKET_PATH")
    if not path:
        sys.exit("labels: HERDR_SOCKET_PATH is not set; run through Herdr")
    return Path(path)


def state_dir() -> Path:
    """Return the Herdr-provided plugin state directory."""
    path = os.environ.get("HERDR_PLUGIN_STATE_DIR")
    if not path:
        sys.exit("labels: HERDR_PLUGIN_STATE_DIR is not set; run through Herdr")
    directory = Path(path)
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def state_path(sock: Path) -> Path:
    """Return the state file for one Herdr server; sessions never share state."""
    key = hashlib.sha1(str(sock).encode()).hexdigest()[:16]
    return state_dir() / f"tabs-{key}.json"


def request(sock: Path, method: str, params: dict | None = None) -> dict:
    """Send one request on a fresh connection and return its result."""
    with socket.socket(socket.AF_UNIX) as conn:
        conn.settimeout(5)
        conn.connect(str(sock))
        send(conn, {"id": SOURCE, "method": method, "params": params or {}})
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


# %%
def sidebar_order(workspaces: list[dict]) -> list[int]:
    """Return workspace indices in sidebar order.

    Herdr lists workspaces in creation order, except that the checkouts of one Git repository are grouped: the main checkout comes first, where the group's first member was, and its worktrees follow it. A collapsed group hides its worktrees, but that is per-client display state Herdr does not expose, so numbers below a collapsed group run ahead of the sidebar.
    """
    members: dict[str, list[int]] = defaultdict(list)
    for index, workspace in enumerate(workspaces):
        if worktree := workspace.get("worktree"):
            members[worktree["repo_key"]].append(index)

    def is_main(index: int) -> bool:
        return not workspaces[index]["worktree"]["is_linked_worktree"]

    grouped = {
        key
        for key, indices in members.items()
        if len(indices) >= 2 and any(map(is_main, indices))
    }
    order: list[int] = []
    emitted: set[str] = set()
    for index, workspace in enumerate(workspaces):
        worktree = workspace.get("worktree")
        if worktree is None or worktree["repo_key"] not in grouped:
            order.append(index)
            continue
        key = worktree["repo_key"]
        if key in emitted:
            continue
        emitted.add(key)
        group = members[key]
        main = next(filter(is_main, group), index)
        order.append(main)
        order.extend(member for member in group if member != main)
    return order


def pi_session_name(title: str) -> str | None:
    """Return the session name from pi's terminal title.

    Pi titles its terminal `π - <session> - <dir>`, or `π - <dir>` while the session is unnamed. Returns the session name, "" for an unnamed session, or None when the title is not pi's (pi's external editor, for example).
    """
    match = PI_TITLE.fullmatch(title)
    if match is None:
        return None
    return match.group(1) or ""


def pane_title(pane: dict) -> str:
    """Return the pane's terminal title, with pi's π and directory removed."""
    title = (pane.get("terminal_title_stripped") or "").strip()
    if pane.get("agent") == "pi":
        session = pi_session_name(title)
        if session is not None:
            return session
    return title


def pane_program(pane: dict) -> str:
    """Return what to call the pane in a tab label: its pi session, else its program."""
    title = (pane.get("terminal_title_stripped") or "").strip()
    if pane.get("agent") == "pi":
        session = pi_session_name(title)
        if session is not None:
            return session or "pi"
    return TITLE_SEPARATOR.split(title, maxsplit=1)[0].strip()


def shorten(label: str) -> str:
    """Cut a label to MAX_TAB_LABEL characters, marking the cut like tmux's `#{=/15/…:}`."""
    if len(label) <= MAX_TAB_LABEL:
        return label
    return label[:MAX_TAB_LABEL].rstrip() + "…"


def tab_name(panes: list[dict]) -> str | None:
    """Name a tab after its first agent pane, else its first pane with a title."""
    ordered = [pane for pane in panes if pane.get("agent")] + [
        pane for pane in panes if not pane.get("agent")
    ]
    for pane in ordered:
        if name := pane_program(pane):
            return shorten(name)
    return None


def numbered(position: int, name: str | None) -> str:
    """Return a tab label: its position, then its name if it has one."""
    return f"{position}{TAB_SEPARATOR}{name}" if name else str(position)


def typed_name(label: str) -> str:
    """Return the name in a label typed by hand, without a leading index; "" for just a number."""
    return TAB_INDEX.sub("", label, count=1).strip()


# %%
def desired_tokens(snapshot: dict) -> tuple[dict[str, dict], dict[str, dict]]:
    """Return the tokens each workspace and agent pane should carry."""
    workspaces = snapshot["workspaces"]
    workspace_tokens = {
        workspaces[ws_index]["workspace_id"]: {"idx": str(position)}
        for position, ws_index in enumerate(sidebar_order(workspaces), start=1)
    }
    panes = {pane["pane_id"]: pane for pane in snapshot["panes"]}
    pane_tokens = {}
    for position, agent in enumerate(snapshot["agents"], start=1):
        pane = panes.get(agent["pane_id"])
        if pane is None:
            continue
        pane_tokens[agent["pane_id"]] = {
            "idx": str(position),
            "title": pane_title(pane),
        }
    return workspace_tokens, pane_tokens


def token_patch(current: dict | None, wanted: dict[str, str]) -> dict:
    """Return the token changes to send; an empty value clears the token."""
    current = current or {}
    return {
        name: (value or None)
        for name, value in wanted.items()
        if (current.get(name) or "") != value
    }


def publish(sock: Path, method: str, target: dict, patch: dict) -> None:
    """Report one token patch, tolerating a target that just closed."""
    try:
        request(sock, method, {**target, "source": SOURCE, "tokens": patch})
    except RuntimeError as error:
        log.warning("%s", error)


def sync_tokens(sock: Path, snapshot: dict) -> None:
    """Bring workspace and agent-pane tokens in line with the snapshot."""
    workspace_tokens, pane_tokens = desired_tokens(snapshot)
    for workspace in snapshot["workspaces"]:
        wanted = workspace_tokens.get(workspace["workspace_id"])
        if wanted and (patch := token_patch(workspace.get("tokens"), wanted)):
            publish(
                sock,
                "workspace.report_metadata",
                {"workspace_id": workspace["workspace_id"]},
                patch,
            )
    for pane in snapshot["panes"]:
        wanted = pane_tokens.get(pane["pane_id"])
        if wanted and (patch := token_patch(pane.get("tokens"), wanted)):
            publish(
                sock,
                "pane.report_metadata",
                {"pane_id": pane["pane_id"]},
                patch,
            )


def sync_tabs(
    sock: Path, snapshot: dict, state: dict[str, dict[str, str]]
) -> bool:
    """Number every tab and name the ones the user has not; return whether `state` changed.

    `state["tabs"]` holds the label this plugin last wrote to each tab, and `state["names"]` the names typed by hand. A label that differs from the one we wrote was typed by the user, or is Herdr's default for a new tab, which is its position. Its name without any leading index becomes the tab's fixed name; a bare number leaves the tab to automatic naming. Herdr has no way to drop a custom label, so renaming a tab to just its number is how it is handed back.
    """
    written, names = state["tabs"], state["names"]
    panes_by_tab: dict[str, list[dict]] = defaultdict(list)
    for pane in snapshot["panes"]:
        panes_by_tab[pane["tab_id"]].append(pane)
    positions: dict[str, int] = defaultdict(int)
    before = {key: dict(value) for key, value in state.items()}
    live = set()
    for tab in snapshot["tabs"]:
        tab_id, label = tab["tab_id"], tab["label"]
        live.add(tab_id)
        positions[tab["workspace_id"]] += 1
        if label != written.get(tab_id):
            if name := typed_name(label):
                names[tab_id] = name
            else:
                names.pop(tab_id, None)
        name = names.get(tab_id) or tab_name(panes_by_tab[tab_id])
        wanted = numbered(positions[tab["workspace_id"]], name)
        if wanted != label:
            try:
                request(sock, "tab.rename", {"tab_id": tab_id, "label": wanted})
                log.info("tab %s: %r -> %r", tab_id, label, wanted)
            except RuntimeError as error:
                log.warning("%s", error)
                continue
        written[tab_id] = wanted
    for tabs in (written, names):
        for tab_id in set(tabs) - live:
            del tabs[tab_id]
    return state != before


def load_state(path: Path) -> dict[str, dict[str, str]]:
    """Return the labels this plugin last wrote and the names typed by hand, by tab."""
    try:
        saved = json.loads(path.read_text())
    except (OSError, ValueError):
        saved = {}
    return {"tabs": saved.get("tabs", {}), "names": saved.get("names", {})}


def save_state(path: Path, state: dict[str, dict[str, str]]) -> None:
    """Write the tab state atomically."""
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state))
    tmp.replace(path)


def sync(sock: Path, path: Path) -> None:
    """Run one full pass: numbers and titles, then tab labels."""
    snapshot = request(sock, "session.snapshot")["snapshot"]
    sync_tokens(sock, snapshot)
    state = load_state(path)
    if sync_tabs(sock, snapshot, state):
        save_state(path, state)


# %%
def ensure_daemon() -> None:
    """Start the daemon for this server unless one is already running."""
    lock_path = state_path(socket_path()).with_suffix(".lock")
    with open(lock_path, "a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return  # A live daemon holds the lock.
        fcntl.flock(lock, fcntl.LOCK_UN)
    log_path = state_path(socket_path()).with_suffix(".log")
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
    """Keep labels in sync until the Herdr server goes away."""
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )
    sock = socket_path()
    path = state_path(sock)
    # Held open for the daemon's lifetime; the OS releases it when the process exits.
    lock = open(path.with_suffix(".lock"), "a+")  # noqa: SIM115
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log.info("another daemon already serves %s", sock)
        return
    pid_path = path.with_suffix(".pid")
    pid_path.write_text(str(os.getpid()))
    log.info("labelling %s (pid %d)", sock, os.getpid())
    backoff = 0.2
    try:
        while sock.exists():
            try:
                subscribe_and_sync(sock, path)
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
        # Tab ownership survives a server restart, since Herdr restores tab ids and custom labels. The empty .lock stays: unlinking it could let a late-starting sibling lock a fresh inode.
        for suffix in (".pid", ".log"):
            path.with_suffix(suffix).unlink(missing_ok=True)


def subscribe_and_sync(sock: Path, path: Path) -> None:
    """Hold one event subscription, syncing after each burst of events."""
    sync(sock, path)
    with socket.socket(socket.AF_UNIX) as conn:
        conn.connect(str(sock))
        send(
            conn,
            {
                "id": "sub",
                "method": "events.subscribe",
                "params": {
                    "subscriptions": [{"type": name} for name in EVENTS]
                },
            },
        )
        reader = LineReader(conn)
        ack = reader.next()
        if "error" in ack:
            raise RuntimeError(f"subscribe failed: {ack['error']}")
        while True:
            conn.settimeout(IDLE_PING_SECONDS)
            try:
                message = reader.next()
            except socket.timeout:  # noqa: UP041 (distinct from TimeoutError on 3.9)
                # Raises if the server is gone but its socket file lingers.
                request(sock, "ping")
                continue
            if "event" not in message:
                continue
            # Layout changes arrive in bursts; let one settle before reading the snapshot.
            conn.settimeout(SETTLE_SECONDS)
            try:
                while True:
                    reader.next()
            except socket.timeout:  # noqa: UP041
                pass
            sync(sock, path)


# %%
def main(argv: list[str]) -> None:
    """Dispatch `daemon --ensure|--run` or a one-off `sync`."""
    parser = argparse.ArgumentParser(
        prog="labels", description=__doc__.split("\n")[0]
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    daemon = subparsers.add_parser(
        "daemon", help="keep labels in sync for this Herdr server"
    )
    mode = daemon.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--ensure",
        action="store_true",
        help="start the daemon if none is running",
    )
    mode.add_argument(
        "--run", action="store_true", help="run the sync loop in the foreground"
    )
    subparsers.add_parser("sync", help="run one sync pass and exit")
    args = parser.parse_args(argv)
    if args.command == "daemon":
        run_daemon() if args.run else ensure_daemon()
    else:
        sync(socket_path(), state_path(socket_path()))


if __name__ == "__main__":
    main(sys.argv[1:])
