"""IPython startup: a live "still running" indicator and a duration log.

Auto-loaded on every IPython session start. Registers `pre_execute`/
`post_execute` hooks that:

1. Start a background thread ticking every `_TICK_INTERVAL` seconds while
   a cell runs, writing its elapsed time into the *tmux pane title* via
   the OSC 2 escape sequence (`\\033]2;...\\007`)--not printed inline,
   since that would be one more thing racing with whatever the cell's own
   code is writing to stdout. This dotfiles repo's tmux config already
   shows `#{pane_title}` in a border line whenever a window has 2+ panes
   (`~/.config/tmux/tmux.conf`)--exactly the nvim+ipython split this
   workflow uses--so the indicator shows up there with no further setup.
   Written directly to `sys.__stdout__` (the real, original stdout).
   `01-output-box.py`'s recoloring wrapper never sees it, and even if it
   did, it treats anything containing an ESC byte as pass-through.
2. Print a dim `⏱ N.NNs` line once a cell finishes, giving a persistent,
   scrollback-visible history of how long each cell took. Skipped for
   cells under `_MIN_LOGGED_DURATION` seconds, so instant one-liners
   (`2 + 2`) don't get a noisy `⏱ 0.00s` on every single cell.

Verified safe to interrupt: `post_execute` still fires on `Ctrl-C`
(confirmed empirically), so the ticker thread always gets stopped and the
pane title always gets reset--no leaked thread, no stuck "running" title.
"""

# %%
import sys
import threading
import time
from pathlib import Path

_TICK_INTERVAL = 0.5
_MIN_LOGGED_DURATION = 0.2

_GREY1 = {
    "dark": "#859289",
    "light": "#939f91",
}

_appearance_file = Path.home() / ".cache" / "appearance"
_appearance = "dark"
if _appearance_file.exists():
    _read = _appearance_file.read_text().strip()
    if _read in _GREY1:
        _appearance = _read

_r, _g, _b = (int(_GREY1[_appearance][i : i + 2], 16) for i in (1, 3, 5))
# Plain color, no `dim` (SGR 2): tmux doesn't reliably combine `dim` with
# 24-bit truecolor foreground codes (confirmed directly--even a bare
# `\033[2m\033[38;2;r;g;bm` sent straight to the pane loses the color part
# on screen). grey1 alone already reads as muted/de-emphasized--it's the
# same color `01-output-box.py` uses for its rules.
_TIMER_ON = f"\033[38;2;{_r};{_g};{_b}m"
_RESET = "\033[0m"

_state = {"thread": None, "stop": None, "start": None}


def _set_pane_title(text: str) -> None:
    sys.__stdout__.write(f"\033]2;{text}\007")
    sys.__stdout__.flush()


def _tick(stop_event: threading.Event, start: float) -> None:
    while not stop_event.wait(_TICK_INTERVAL):
        _set_pane_title(f"\u23f3 running {time.monotonic() - start:.1f}s")


def _pre_execute() -> None:
    start = time.monotonic()
    stop_event = threading.Event()
    thread = threading.Thread(
        target=_tick, args=(stop_event, start), daemon=True
    )
    _state.update(thread=thread, stop=stop_event, start=start)
    thread.start()


def _post_execute() -> None:
    thread = _state.get("thread")
    stop_event = _state.get("stop")
    start = _state.get("start")

    if stop_event is not None:
        stop_event.set()
    if thread is not None:
        thread.join(timeout=1)

    elapsed = time.monotonic() - start if start is not None else 0.0
    _set_pane_title("idle")
    if elapsed >= _MIN_LOGGED_DURATION:
        print(f"{_TIMER_ON}\u23f1 {elapsed:.2f}s{_RESET}")

    _state.update(thread=None, stop=None, start=None)


_ip = get_ipython()  # noqa: F821 -- injected by IPython at startup
if _ip is not None:
    _ip.events.register("pre_execute", _pre_execute)
    _ip.events.register("post_execute", _post_execute)
