# %%
"""End-to-end check of the labels plugin against a disposable Herdr session.

First checks the pure functions (sidebar order with worktree groups, pi title parsing, tab names). Then starts a throwaway named session, starts the daemon the way Herdr's startup hook does, changes the layout with CLI calls and checks the numbers, titles, and tab labels it publishes, including that a tab named by hand is left alone and that the daemon exits when the server stops. If `pi` is on PATH it is started in one pane, offline and with a scratch session directory, to check agent numbering against a real agent. The user's default Herdr session is never contacted. Run with `uv run --no-project tests/test_labels.py`.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import labels

PLUGIN = Path(labels.__file__)
SESSION = f"labels-test-{os.getpid()}"
failures = []


def check(label: str, actual: object, expected: object) -> None:
    """Record whether a value matches."""
    ok = actual == expected
    if not ok:
        failures.append(label)
    print(
        f"{'PASS' if ok else 'FAIL'} {label}"
        + ("" if ok else f": {actual!r}, expected {expected!r}")
    )


# %%
# Pure functions.
def workspace(key: str | None = None, linked: bool = False) -> dict:
    return {
        "worktree": {"repo_key": key, "is_linked_worktree": linked}
        if key
        else None
    }


check(
    "plain workspaces keep creation order",
    labels.sidebar_order([workspace(), workspace(), workspace()]),
    [0, 1, 2],
)
check(
    "a repo's worktrees follow its main checkout",
    labels.sidebar_order(
        [
            workspace("a", linked=True),
            workspace(),
            workspace("a"),
            workspace("a", linked=True),
        ]
    ),
    [2, 0, 3, 1],
)
check(
    "worktrees without an open main checkout are not grouped",
    labels.sidebar_order(
        [workspace("a", linked=True), workspace(), workspace("a", linked=True)]
    ),
    [0, 1, 2],
)
check(
    "pi named session",
    labels.pi_session_name("π - bar config - jdpinto"),
    "bar config",
)
check(
    "pi session name may contain the separator",
    labels.pi_session_name("π - fix - bar - jdpinto"),
    "fix - bar",
)
check("pi unnamed session", labels.pi_session_name("π - .dotfiles"), "")
check("not a pi title", labels.pi_session_name("prompt.md"), None)
pi = {
    "agent": "pi",
    "terminal_title_stripped": "π - touch bar flashing bug - .dotfiles",
}
check(
    "$title drops π and directory",
    labels.pane_title(pi),
    "touch bar flashing bug",
)
check(
    "$title is empty for an unnamed pi session",
    labels.pane_title({"agent": "pi", "terminal_title_stripped": "π - x"}),
    "",
)
check(
    "tab after the pi session, shortened",
    labels.tab_name([pi]),
    "touch bar flash…",
)
check(
    "tab after an unnamed pi session",
    labels.tab_name([{"agent": "pi", "terminal_title_stripped": "π - x"}]),
    "pi",
)
check(
    "tab after pi's editor when pi is not titling",
    labels.tab_name([{"agent": "pi", "terminal_title_stripped": "prompt.md"}]),
    "prompt.md",
)
check(
    "tab after the shell",
    labels.tab_name([{"terminal_title_stripped": "bash - ~/.dotfiles"}]),
    "bash",
)
check(
    "tab after yazi",
    labels.tab_name(
        [{"terminal_title_stripped": "Yazi: app-icon-research.ZBiQnD"}]
    ),
    "Yazi",
)
check(
    "tab after neovim's file",
    labels.tab_name(
        [{"terminal_title_stripped": "init.lua (~/.config/nvim) - NVIM"}]
    ),
    "init.lua",
)
check(
    "the agent pane names the tab even when it is not first",
    labels.tab_name([{"terminal_title_stripped": "bash - ~"}, pi]),
    "touch bar flash…",
)
check(
    "a tab with no titles has no name",
    labels.tab_name([{"terminal_title_stripped": ""}]),
    None,
)
check(
    "token patch sends only changes and clears with null",
    labels.token_patch({"idx": "1", "title": "old"}, {"idx": "1", "title": ""}),
    {"title": None},
)
check(
    "a named tab leads with its position", labels.numbered(2, "bash"), "2:bash"
)
check(
    "a tab without a name is just its position", labels.numbered(1, None), "1"
)
check("a typed name keeps no index", labels.typed_name("2:notes "), "notes")
check("a typed name without an index", labels.typed_name("work"), "work")
check("a bare number is no name", labels.typed_name("3"), "")
check(
    "a name that starts with digits",
    labels.typed_name("2024 plan"),
    "2024 plan",
)


# %%
# Live session.
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
STATE = Path(tempfile.mkdtemp(prefix="labels-state."))
WORKDIR = Path(tempfile.mkdtemp(prefix="labels-work."))
SOCKET = Path.home() / ".config/herdr/sessions" / SESSION / "herdr.sock"
PLUGIN_ENV = {
    **ENV,
    "HERDR_SOCKET_PATH": str(SOCKET),
    "HERDR_PLUGIN_STATE_DIR": str(STATE),
}


def cli(*args: str, check: bool = True) -> dict:
    """Run a Herdr CLI command against the disposable session."""
    out = subprocess.run(
        ["herdr", "--session", SESSION, *args],
        env=ENV,
        capture_output=True,
        text=True,
        timeout=60,
        check=check,
    )
    return json.loads(out.stdout) if out.stdout.strip() else {}


def snapshot() -> dict:
    return cli("api", "snapshot")["result"]["snapshot"]


def wait_for(label: str, predicate, timeout: float = 8.0) -> dict:
    """Poll the snapshot until `predicate(snapshot)` holds; record a failure otherwise."""
    deadline = time.monotonic() + timeout
    while True:
        snap = snapshot()
        if predicate(snap):
            print(f"PASS {label}")
            return snap
        if time.monotonic() > deadline:
            failures.append(label)
            print(f"FAIL {label}")
            return snap
        time.sleep(0.25)


def tokens(snap: dict, kind: str, item_id: str) -> dict:
    key = "workspace_id" if kind == "workspaces" else "pane_id"
    return next(
        item.get("tokens") or {} for item in snap[kind] if item[key] == item_id
    )


def tab_label(snap: dict, tab_id: str) -> str:
    return next(tab["label"] for tab in snap["tabs"] if tab["tab_id"] == tab_id)


def set_title(pane_id: str, title: str) -> None:
    """Have the pane's shell set its terminal title."""
    cli("pane", "run", pane_id, f"printf '\\033]2;{title}\\007'")


daemon_pid = None
# A headless server is enough; no client needs to attach. It starts empty.
server = subprocess.Popen(
    ["herdr", "--session", SESSION, "server"],
    env=ENV,
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
try:
    for _ in range(100):
        if SOCKET.exists():
            break
        time.sleep(0.1)
    created = cli(
        "workspace", "create", "--label", "alpha", "--cwd", str(WORKDIR)
    )["result"]
    w1 = created["workspace"]["workspace_id"]
    t1 = created["tab"]["tab_id"]
    p1 = created["root_pane"]["pane_id"]
    w2 = cli(
        "workspace",
        "create",
        "--label",
        "beta",
        "--cwd",
        str(WORKDIR),
        "--no-focus",
    )["result"]["workspace"]["workspace_id"]
    t2 = cli("tab", "create", "--workspace", w1, "--no-focus")["result"]["tab"][
        "tab_id"
    ]
    t3 = cli(
        "tab", "create", "--workspace", w1, "--label", "mine", "--no-focus"
    )["result"]["tab"]["tab_id"]
    time.sleep(1.5)  # Shells start.

    subprocess.run(
        [sys.executable, "-B", str(PLUGIN), "daemon", "--ensure"],
        env=PLUGIN_ENV,
        cwd=PLUGIN.parent,
        check=True,
        timeout=15,
    )
    for _ in range(50):
        if pid_files := list(STATE.glob("tabs-*.pid")):
            break
        time.sleep(0.1)
    daemon_pid = int(pid_files[0].read_text())
    print(f"daemon pid {daemon_pid}")
    subprocess.run(
        [sys.executable, "-B", str(PLUGIN), "daemon", "--ensure"],
        env=PLUGIN_ENV,
        cwd=PLUGIN.parent,
        check=True,
        timeout=15,
    )
    time.sleep(0.5)
    check(
        "second --ensure keeps the same daemon",
        int(pid_files[0].read_text()),
        daemon_pid,
    )

    wait_for(
        "workspaces are numbered in sidebar order",
        lambda s: (
            tokens(s, "workspaces", w1).get("idx") == "1"
            and tokens(s, "workspaces", w2).get("idx") == "2"
        ),
    )
    snap = wait_for(
        "a hand-named tab keeps its name, numbered",
        lambda s: tab_label(s, t3) == "3:mine",
    )
    print(
        f"     default-labelled tabs: {tab_label(snap, t1)!r}, {tab_label(snap, t2)!r}"
    )

    set_title(p1, "bash - ~/x")
    wait_for(
        "a tab is named after its shell's title",
        lambda s: tab_label(s, t1) == "1:bash",
    )
    # bash retitles at every prompt; plain sh leaves a cleared title alone.
    cli("pane", "run", p1, "exec sh")
    time.sleep(0.5)
    set_title(p1, "")
    wait_for(
        "a tab with no title goes back to its position",
        lambda s: tab_label(s, t1) == "1",
    )

    cli("tab", "rename", t1, "work")
    wait_for(
        "a tab renamed by hand is numbered",
        lambda s: tab_label(s, t1) == "1:work",
    )
    set_title(p1, "nvim")
    time.sleep(1.5)
    check(
        "renaming a tab by hand takes its name away from the plugin",
        tab_label(snapshot(), t1),
        "1:work",
    )
    cli("tab", "rename", t1, "1:notes")
    wait_for(
        "the index left in the rename prompt is not doubled",
        lambda s: tab_label(s, t1) == "1:notes",
    )
    cli("tab", "rename", t1, "1")
    wait_for(
        "renaming a tab to its number hands it back to the plugin",
        lambda s: tab_label(s, t1) == "1:nvim",
    )
    cli("tab", "close", t2)
    wait_for(
        "closing a tab renumbers the rest",
        lambda s: tab_label(s, t3) == "2:mine",
    )

    cli("workspace", "close", w1)
    wait_for(
        "closing a workspace renumbers the rest",
        lambda s: tokens(s, "workspaces", w2).get("idx") == "1",
    )

    if shutil.which("pi"):
        scratch = WORKDIR / "pi-sessions"
        scratch.mkdir()
        tab = cli(
            "tab",
            "create",
            "--workspace",
            w2,
            "--cwd",
            str(WORKDIR),
            "--env",
            f"PI_CODING_AGENT_SESSION_DIR={scratch}",
            "--env",
            "PI_OFFLINE=1",
            "--no-focus",
        )["result"]
        agent_pane = tab["root_pane"]["pane_id"]
        time.sleep(1.5)
        started = cli(
            "agent",
            "start",
            "one",
            "--kind",
            "pi",
            "--pane",
            agent_pane,
            check=False,
        )
        if started.get("result"):
            snap = wait_for(
                "the agent is numbered and its tab is named '2:pi'",
                lambda s: (
                    tokens(s, "panes", agent_pane).get("idx") == "1"
                    and tab_label(s, tab["tab"]["tab_id"]) == "2:pi"
                ),
                timeout=20,
            )
            check(
                "an unnamed pi session has no $title",
                tokens(snap, "panes", agent_pane).get("title"),
                None,
            )
            cli("agent", "send-keys", "one", "ctrl+c", check=False)
            cli("agent", "send-keys", "one", "ctrl+c", check=False)
        else:
            print("SKIP agent checks: pi did not start in the test session")
    else:
        print("SKIP agent checks: pi is not on PATH")
finally:
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
        except (ProcessLookupError, TypeError):
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
    try:
        server.wait(timeout=10)
    except subprocess.TimeoutExpired:
        server.terminate()
        server.wait(timeout=10)
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
