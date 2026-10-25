# %%
"""End-to-end check of the lastfocus plugin against a disposable Herdr session.

Starts a throwaway named session, attaches a client in a pseudo-terminal, starts the recording daemon the way Herdr's startup hook does, navigates with real keys and CLI calls, then runs the three actions and checks where focus lands. The user's default Herdr session is never contacted. Run with `uv run --no-project tests/test_lastfocus.py`.
"""

import fcntl
import json
import os
import pty
import select
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1] / "lastfocus.py"
SESSION = f"lastfocus-test-{os.getpid()}"
PREFIX = b"\x02"
RIGHT, LEFT = b"\x1b[C", b"\x1b[D"


def clean_env() -> dict:
    """Return an environment that cannot reach the user's running Herdr session."""
    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith("HERDR_") and k != "TMUX"
    }
    env.update(TERM="xterm-256color", COLORTERM="truecolor")
    return env


ENV = clean_env()
STATE = Path(tempfile.mkdtemp(prefix="lastfocus-state."))
WORKDIR = Path(tempfile.mkdtemp(prefix="lastfocus-work."))
SOCKET = Path.home() / ".config/herdr/sessions" / SESSION / "herdr.sock"
PLUGIN_ENV = {
    **ENV,
    "HERDR_SOCKET_PATH": str(SOCKET),
    "HERDR_PLUGIN_STATE_DIR": str(STATE),
}


def cli(*args: str) -> dict:
    """Run a Herdr CLI command against the disposable session."""
    out = subprocess.run(
        ["herdr", "--session", SESSION, *args],
        env=ENV,
        capture_output=True,
        text=True,
        timeout=15,
        check=True,
    )
    return json.loads(out.stdout) if out.stdout.strip() else {}


def focus() -> dict:
    """Return the focused workspace, tab, and pane ids."""
    snap = cli("api", "snapshot")["result"]["snapshot"]
    return {k: snap[f"focused_{k}_id"] for k in ("workspace", "tab", "pane")}


def focus_pane(pane_id: str) -> None:
    """Focus a pane by id over the socket, like clicking it."""
    with socket.socket(socket.AF_UNIX) as conn:
        conn.connect(str(SOCKET))
        conn.sendall(
            json.dumps(
                {
                    "id": "t",
                    "method": "pane.focus",
                    "params": {"pane_id": pane_id},
                }
            ).encode()
            + b"\n"
        )
        reply = json.loads(conn.makefile("rb").readline())
    assert "error" not in reply, reply


def action(name: str) -> None:
    """Invoke one plugin action exactly as Herdr's keybinding would."""
    subprocess.run(
        [sys.executable, "-B", str(PLUGIN), name],
        env=PLUGIN_ENV,
        cwd=PLUGIN.parent,
        check=True,
        timeout=15,
    )
    time.sleep(0.4)  # Let the daemon record the resulting focus.


class Client:
    """A Herdr client attached in a pseudo-terminal."""

    def __init__(self) -> None:
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            fcntl.ioctl(
                0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0)
            )
            os.chdir(WORKDIR)
            os.execvpe("herdr", ["herdr", "--session", SESSION], ENV)

    def pump(self, seconds: float) -> None:
        """Drain output, answering host color queries as a dark terminal would."""
        deadline = time.monotonic() + seconds
        while (remaining := deadline - time.monotonic()) > 0:
            if not select.select([self.fd], [], [], min(remaining, 0.1))[0]:
                continue
            try:
                chunk = os.read(self.fd, 65536)
            except OSError:
                return
            if b"\x1b]11;?" in chunk:
                os.write(self.fd, b"\x1b]11;rgb:2d2d/3535/3b3b\x1b\\")
            if b"\x1b]10;?" in chunk:
                os.write(self.fd, b"\x1b]10;rgb:d3d3/c6c6/aaaa\x1b\\")
            if b"\x1b[?996n" in chunk:
                os.write(self.fd, b"\x1b[?997;1n")
            if b"\x1b[c" in chunk:
                os.write(self.fd, b"\x1b[?62;22c")

    def key(self, key: bytes) -> None:
        """Press prefix, then a key, as the user would."""
        os.write(self.fd, PREFIX)
        self.pump(0.3)
        os.write(self.fd, key)
        self.pump(0.8)

    def close(self) -> None:
        os.write(self.fd, PREFIX + b"d")
        self.pump(1)
        try:
            os.kill(self.pid, 15)
        except ProcessLookupError:
            pass
        os.waitpid(self.pid, 0)


failures = []


def check(label: str, expected: dict) -> None:
    """Record whether the focused ids match the expected ones."""
    actual = focus()
    ok = all(actual[k] == v for k, v in expected.items())
    if not ok:
        failures.append(label)
    print(
        f"{'PASS' if ok else 'FAIL'} {label}: focus {actual['pane']}"
        + ("" if ok else f", expected {expected}")
    )


# %%
client = Client()
try:
    client.pump(6)
    start = focus()
    w1, t1, p1 = start["workspace"], start["tab"], start["pane"]
    p2 = cli("pane", "split", p1, "--direction", "right")["result"]["pane"][
        "pane_id"
    ]
    t2 = cli("tab", "create", "--workspace", w1, "--label", "two")["result"][
        "tab"
    ]["tab_id"]
    w2 = cli("workspace", "create", "--label", "beta", "--cwd", str(WORKDIR))[
        "result"
    ]["workspace"]["workspace_id"]
    cli("workspace", "focus", w1)
    cli("tab", "focus", t1)
    client.pump(1)
    cli("pane", "focus", "--direction", "left")
    client.pump(1)
    assert focus() == {"workspace": w1, "tab": t1, "pane": p1}, focus()

    # Start the recorder exactly as the manifest's startup hook does.
    subprocess.run(
        [sys.executable, "-B", str(PLUGIN), "daemon", "--ensure"],
        env=PLUGIN_ENV,
        cwd=PLUGIN.parent,
        check=True,
        timeout=15,
    )
    for _ in range(50):
        pid_files = list(STATE.glob("history-*.pid"))
        if pid_files:
            break
        time.sleep(0.1)
    daemon_pid = int(pid_files[0].read_text())
    print(f"daemon pid {daemon_pid}")
    # Idempotent: a second --ensure must not start another daemon.
    subprocess.run(
        [sys.executable, "-B", str(PLUGIN), "daemon", "--ensure"],
        env=PLUGIN_ENV,
        cwd=PLUGIN.parent,
        check=True,
        timeout=15,
    )
    time.sleep(0.5)
    assert int(pid_files[0].read_text()) == daemon_pid, (
        "second --ensure replaced the daemon"
    )

    # Panes within a tab.
    client.key(RIGHT)
    action("last-pane")
    check("prefix+; returns to the first pane", {"tab": t1, "pane": p1})
    action("last-pane")
    check("prefix+; again toggles back", {"tab": t1, "pane": p2})

    # Tabs within a workspace; the other tab must not disturb pane history.
    client.key(b"n")
    time.sleep(0.4)
    action("last-tab")
    check(
        "prefix+l returns to the first tab, on its remembered pane",
        {"tab": t1, "pane": p2},
    )
    action("last-tab")
    check("prefix+l again toggles to the second tab", {"tab": t2})
    action("last-pane")
    check("prefix+; in a single-pane tab does nothing", {"tab": t2})

    # Workspaces.
    client.key(b")")
    time.sleep(0.4)
    action("last-workspace")
    check(
        "prefix+L returns to the first workspace, on its remembered tab",
        {"workspace": w1, "tab": t2},
    )
    action("last-workspace")
    check("prefix+L again toggles to the second workspace", {"workspace": w2})
    action("last-workspace")
    action("last-tab")
    check(
        "tab history survived the workspace round-trip",
        {"workspace": w1, "tab": t1, "pane": p2},
    )

    # A closed target is skipped in favour of the next most recent one.
    # History in t1 becomes p4 -> p2 -> p1 -> p2 -> p4; then p2 is closed.
    p4 = cli("pane", "split", p2, "--direction", "down")["result"]["pane"][
        "pane_id"
    ]
    client.pump(0.6)
    for pane in (p2, p1, p2, p4):
        focus_pane(pane)
        client.pump(0.5)
    assert focus()["pane"] == p4, focus()
    cli("pane", "close", p2)
    client.pump(0.8)
    action("last-pane")
    check(
        "prefix+; skips the closed pane and uses the next most recent",
        {"tab": t1, "pane": p1},
    )

    history = json.loads(next(STATE.glob("history-*.json")).read_text())[
        "history"
    ]
    print(f"\nrecorded {len(history)} focus positions")
finally:
    client.close()
    subprocess.run(
        ["herdr", "--session", SESSION, "server", "stop"],
        env=ENV,
        capture_output=True,
        timeout=15,
        check=False,
    )
    for _ in range(60):
        try:
            os.kill(daemon_pid, 0)
        except (ProcessLookupError, NameError):
            break
        time.sleep(0.1)
    else:
        failures.append("daemon did not exit after the server stopped")
        os.kill(daemon_pid, 15)
    print(
        "daemon exited after server stop"
        if "daemon did not exit after the server stopped" not in failures
        else "FAIL daemon still running"
    )
    time.sleep(0.5)
    subprocess.run(
        ["herdr", "session", "delete", SESSION],
        env=ENV,
        capture_output=True,
        timeout=15,
        check=False,
    )
    shutil.rmtree(STATE)
    shutil.rmtree(WORKDIR)

print(
    f"\n{len(failures)} failure(s)"
    + (": " + ", ".join(failures) if failures else "")
)
sys.exit(1 if failures else 0)
