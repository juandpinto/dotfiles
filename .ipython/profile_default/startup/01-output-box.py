"""IPython startup: bound each cell's output with rules, and recolor it.

Auto-loaded on every IPython session start. With `Out[n]:` removed (see
`ipython_config.py`) and `In [n]:` the only prompt left, this:

1. Registers `pre_execute`/`post_execute` hooks that print a thin
   horizontal rule right after a cell's input is echoed and right after
   its output ends, bounding the output top and bottom like a borderless
   box--the same thing this file did before, just extended below.
2. Between those two rules, swaps `sys.stdout` for a wrapper that
   recolors whatever plain text the cell prints (stdout, the value of a
   bare expression, everforest's `blue`--the one color unused anywhere
   in the syntax theme in `ipython_config.py`, so output never looks like
   input--rendered bold too, per request.

Anything that already contains an ESC byte is passed through untouched
instead of being recolored: a traceback already carries its own theme
colors (see `ipython_config.py`), and `show_fig` (`00-nvim-helpers.py`)
writes raw sixel/kitty image bytes via `sys.stdout.buffer`, not this
wrapper's text-mode `.write()`, so those never even reach this logic in
the first place--`__getattr__` just proxies `.buffer` straight through to
the real stdout.

Mirrors the cell-separator virtual text already drawn above every `# %%`
marker in nvim (see `~/.dotfiles/.config/nvim/lua/plugins/vim-slime.lua`)--
same visual language, now on the REPL side of the same workflow.
"""

# %%
import re
import shutil
import sys
from pathlib import Path

_PALETTE = {
    "dark": {"rule": "#859289", "output": "#7fbbb3"},
    "light": {"rule": "#939f91", "output": "#3a94c5"},
}

_appearance_file = Path.home() / ".cache" / "appearance"
_appearance = "dark"
if _appearance_file.exists():
    _read = _appearance_file.read_text().strip()
    if _read in _PALETTE:
        _appearance = _read

_colors = _PALETTE[_appearance]


def _rgb(hex_color: str) -> tuple[int, int, int]:
    return tuple(int(hex_color[i : i + 2], 16) for i in (1, 3, 5))


_rr, _rg, _rb = _rgb(_colors["rule"])
_or, _og, _ob = _rgb(_colors["output"])

_RULE_ON = f"\033[38;2;{_rr};{_rg};{_rb}m"
_OUTPUT_ON = f"\033[1m\033[38;2;{_or};{_og};{_ob}m"
_RESET = "\033[0m"

_LINE_SPLIT = re.compile(r"(\r\n|\r|\n)")


def _print_rule() -> None:
    width = shutil.get_terminal_size().columns
    print(f"{_RULE_ON}{'─' * width}{_RESET}")


class _RecoloringStdout:
    """Proxies `sys.stdout`, recoloring plain text and passing everything
    else through untouched--see the module docstring for why.
    """

    def __init__(self, real) -> None:
        self._real = real
        self._buf = ""

    def __getattr__(self, name):
        return getattr(self._real, name)

    def _emit(self, text: str) -> None:
        if not text:
            return
        if "\x1b" in text:
            self._real.write(text)
        else:
            self._real.write(f"{_OUTPUT_ON}{text}{_RESET}")

    def write(self, s: str) -> int:
        self._buf += s
        parts = _LINE_SPLIT.split(self._buf)
        self._buf = parts.pop()
        for i in range(0, len(parts), 2):
            self._emit(parts[i])
            self._real.write(parts[i + 1])
        return len(s)

    def flush(self) -> None:
        if self._buf:
            self._emit(self._buf)
            self._buf = ""
        self._real.flush()


_real_stdout = None


def _start_cell() -> None:
    global _real_stdout
    _print_rule()
    _real_stdout = sys.stdout
    sys.stdout = _RecoloringStdout(_real_stdout)


def _end_cell() -> None:
    global _real_stdout
    if _real_stdout is not None:
        sys.stdout.flush()
        sys.stdout = _real_stdout
        _real_stdout = None
    _print_rule()


_ip = get_ipython()  # noqa: F821 -- injected by IPython at startup
if _ip is not None:
    _ip.events.register("pre_execute", _start_cell)
    _ip.events.register("post_execute", _end_cell)
