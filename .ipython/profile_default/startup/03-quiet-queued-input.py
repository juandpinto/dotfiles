"""IPython startup: don't garble--or split apart--input sent while a cell
is still running.

vim-slime sends whole cells at once (see `~/.dotfiles/.config/nvim/lua/
plugins/vim-slime.lua`), so it's easy to paste a second cell into this
pane while a previous one is still executing. Without this file, that has
two separate problems:

1. **Garbled echo.** The terminal is in normal cooked/echoing mode for
   the duration of cell execution (confirmed directly: reading
   `termios.tcgetattr` from inside a running cell showed `ECHO` on), so
   whatever arrives on stdin gets echoed to the screen immediately,
   garbled into whatever else is happening, well before IPython is
   actually ready to read it as the next input.
2. **Silently split cells.** tmux only wraps a paste in bracketed-paste
   markers (`-p` on `paste-buffer`) "if the destination application has
   requested bracketed paste mode" (`man tmux`). `prompt_toolkit` only
   requests that mode while it's actively reading input--confirmed in its
   source (`renderer.py`): entering `Application.run()` calls
   `output.enable_bracketed_paste()` (`\033[?2004h`), and `reset()`,
   called once `run()` returns (i.e. for the entire cell-execution
   window), calls `output.disable_bracketed_paste()` (`\033[?2004l`). So
   a cell pasted while a previous one is executing arrives *without*
   bracket markers, and IPython's line-by-line reader treats any blank
   line in it as "submit now"--reproduced directly: a multi-statement
   cell (function def, blank line, then a call) queued behind a
   CPU-bound busy loop came back as two separate `In [n]:` submissions
   instead of one. (A `time.sleep()`-based busy cell didn't reliably
   reproduce this in testing--plausibly because it fully releases the
   GIL and keeps the system otherwise idle, whereas a tight Python loop
   pins the CPU while tmux is trying to track pane state--but the fix
   here doesn't depend on knowing exactly why; it just keeps bracketed
   paste mode on throughout, so it can't matter either way.)

This registers `pre_execute`/`post_execute` hooks that, for the duration
of each cell:

- Clear the `ECHO` bit (only `ECHO`--`ICANON` and everything else are
  left alone, so normal line editing/buffering still works), restoring
  the original settings once the cell finishes.
- Write `\033[?2004h`/`\033[?2004l` directly (bypassing `prompt_toolkit`
  entirely, straight to `sys.__stdout__`) to keep tmux's own
  bracketed-paste tracking enabled throughout, mirroring exactly what
  `prompt_toolkit` itself does while it's the active reader.

Verified empirically, including the exact failure case: pasting a
multi-statement cell behind a CPU-bound busy loop now arrives as nothing
visible until the first cell finishes, then executes as a single`In [n]:`
cell with full syntax highlighting--not two. Also verified safe across
`Ctrl-C`: `post_execute` still fires on `KeyboardInterrupt`, so the
terminal is never left in a "stuck silent" or bracket-paste-stuck-on
state.

One tradeoff: if a cell calls the builtin `input()` while you're typing
directly into this pane (not the vim-slime paste path this is designed
for), you won't see your own keystrokes echoed back until you press
Enter--`ECHO` is off for the whole cell, not just while something else
happens to be queued (there's no cheap way to tell those two cases apart
ahead of time). Reading still works correctly either way; it's a
blind-typing UX quirk, not a functional break, and this workflow doesn't
otherwise rely on interactive `input()` calls.
"""

# %%
import sys
import termios

_saved_attrs = None

_ENABLE_BRACKETED_PASTE = "\033[?2004h"
_DISABLE_BRACKETED_PASTE = "\033[?2004l"


def _pre_execute() -> None:
    global _saved_attrs
    try:
        fd = sys.stdin.fileno()
        _saved_attrs = termios.tcgetattr(fd)
        quieted = termios.tcgetattr(fd)
        quieted[3] &= ~termios.ECHO  # lflag, ECHO bit only
        termios.tcsetattr(fd, termios.TCSANOW, quieted)
    except (termios.error, OSError, ValueError):
        # Not a real tty (e.g. stdin redirected)--nothing to do.
        _saved_attrs = None

    sys.__stdout__.write(_ENABLE_BRACKETED_PASTE)
    sys.__stdout__.flush()


def _post_execute() -> None:
    global _saved_attrs
    if _saved_attrs is not None:
        try:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, _saved_attrs)
        except (termios.error, OSError, ValueError):
            pass
        _saved_attrs = None

    sys.__stdout__.write(_DISABLE_BRACKETED_PASTE)
    sys.__stdout__.flush()


_ip = get_ipython()  # noqa: F821 -- injected by IPython at startup
if _ip is not None:
    _ip.events.register("pre_execute", _pre_execute)
    _ip.events.register("post_execute", _post_execute)
