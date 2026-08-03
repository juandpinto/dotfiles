"""IPython startup helpers for Neovim data science workflow.

Auto-loaded by IPython on every session start. Provides figure rendering,
HTML output, and other utilities used by vim-slime keybindings.
"""

# %%
import base64
import io
import os
import shutil
import subprocess
import sys
import tempfile
import webbrowser

import matplotlib

matplotlib.use("Agg")  # non-interactive backend; rendering is handled manually below
import matplotlib.pyplot as plt

_IMG2SIXEL = shutil.which("img2sixel")  # resolved once at startup


# %%
def _in_tmux() -> bool:
    return "TMUX" in os.environ


def _open_in_preview(png_bytes: bytes) -> None:
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        f.write(png_bytes)
        tmp_path = f.name
    subprocess.Popen(["open", "-a", "Preview", tmp_path])


def _send_kitty_image(png_bytes: bytes) -> None:
    """Transmit PNG bytes inline using the kitty graphics protocol.

    Works in a bare WezTerm pane. Not used inside tmux—sixel is used there
    instead, since tmux stores sixel as part of its screen state whereas kitty
    graphics use absolute screen coordinates that are broken by pane offsets.
    """
    encoded = base64.standard_b64encode(png_bytes).decode()
    chunks = [encoded[i : i + 4096] for i in range(0, len(encoded), 4096)]
    out = sys.stdout.buffer
    for i, chunk in enumerate(chunks):
        m = 0 if i == len(chunks) - 1 else 1
        header = f"a=T,f=100,m={m}" if i == 0 else f"m={m}"
        out.write(f"\x1b_G{header};{chunk}\x1b\\".encode())
    out.write(b"\n")
    out.flush()


def _send_sixel_image(png_bytes: bytes) -> None:
    """Transmit PNG bytes inline using sixel graphics.

    Sixel is stored as part of tmux's screen state (unlike kitty graphics),
    so it renders correctly inside tmux panes and survives pane switches.
    Requires img2sixel (brew install libsixel) and tmux built with sixel support
    (tmux 3.4+) with `set -as terminal-features '*:sixel'` in tmux.conf.
    Falls back to macOS Preview if img2sixel is not available.
    """
    if _IMG2SIXEL is None:
        print("[show_fig] img2sixel not found; falling back to Preview. Install: brew install libsixel")
        _open_in_preview(png_bytes)
        return
    proc = subprocess.run([_IMG2SIXEL, "-"], input=png_bytes, capture_output=True)
    if proc.returncode != 0:
        _open_in_preview(png_bytes)
        return
    sys.stdout.buffer.write(proc.stdout)
    sys.stdout.buffer.write(b"\n")
    sys.stdout.buffer.flush()


# %%
def show_fig(fig=None, dpi: int = 150, preview: bool = False) -> None:
    """Display a matplotlib figure.

    Args:
        fig: Figure to display. Defaults to the current active figure.
        dpi: Resolution for the rendered image.
        preview: If True, always open in macOS Preview regardless of context.

    Rendering strategy by context:
    - Inside tmux: sixel graphics (inline, survives pane switches). Requires
      img2sixel and tmux sixel support. Falls back to Preview if unavailable.
    - Outside tmux (bare WezTerm pane): kitty graphics protocol (inline).
    - preview=True: always open in macOS Preview.
    """
    if fig is None:
        fig = plt.gcf()

    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=dpi, bbox_inches="tight")
    buf.seek(0)
    png_bytes = buf.read()

    if preview:
        _open_in_preview(png_bytes)
    elif _in_tmux():
        _send_sixel_image(png_bytes)
    else:
        _send_kitty_image(png_bytes)


# %%
def show_html(obj) -> None:
    """Open any object with _repr_html_() in the default browser.

    Args:
        obj: Any object with a _repr_html_() method (DataFrame, Styler, etc.).
            Use show_html(_) to show the last IPython result.
    """
    try:
        html = obj._repr_html_()
    except AttributeError:
        print(f"Object of type {type(obj).__name__} has no _repr_html_() method.")
        return

    page = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body  {{ font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 24px; }}
    table {{ border-collapse: collapse; font-size: 14px; }}
    th, td {{ border: 1px solid #ddd; padding: 6px 12px; text-align: left; }}
    th {{ background: #f5f5f5; font-weight: 600; }}
    tr:nth-child(even) {{ background: #fafafa; }}
  </style>
</head>
<body>{html}</body>
</html>"""

    with tempfile.NamedTemporaryFile(mode="w", suffix=".html", delete=False, encoding="utf-8") as f:
        f.write(page)
        tmp_path = f.name

    webbrowser.open(f"file://{tmp_path}")


# %%
def _auto_show_figures() -> None:
    """post_execute hook: auto-display any figures produced during a cell."""
    figs = [plt.figure(n) for n in plt.get_fignums()]
    for fig in figs:
        if fig.get_axes():
            show_fig(fig)
    if figs:
        plt.close("all")


_ip = get_ipython()
if _ip is not None:
    _ip.events.register("post_execute", _auto_show_figures)
