"""IPython config: everforest syntax-highlighting theme + blank continuation prompt.

Registers "everforest-dark"/"everforest-light" IPython themes and
activates whichever matches the current macOS appearance, read from
~/.cache/appearance (the single source of truth maintained by the
appearance-watcher LaunchAgent; see ~/.dotfiles/AGENTS.md). Token colors
are the same everforest palette used everywhere else in this dotfiles
repo (bat, the pi CLI--see
~/.dotfiles/.config/pi/agent/themes/everforest-*.json), mapped onto
Pygments token types to match what nvim-treesitter actually renders for
Python (see `_make_theme` below for exactly how).

Also blanks out the `...:` continuation prompt on wrapped/multi-line
input, removes `Out[n]:` entirely, and puts `In [n]:` on its own line
above the code instead of inline with it, so pasted code renders flush
left with its original indentation intact (see `StackedPrompt` below).
"""

# %%
from pathlib import Path

from IPython.terminal.prompts import Prompts
from IPython.utils.PyColorize import Theme, theme_table
from pygments.token import Token

c = get_config()  # noqa: F821 -- injected by IPython's config loader


# %%
class StackedPrompt(Prompts):
    """`In [n]:` renders alone on its own line, with the code starting
    flush left on the line below--rather than inline with the code
    indented to align under it. `Out[n]:` is dropped entirely (its value
    still prints, just with no label--input/output are told apart by
    color and the rules `01-output-box.py` draws around output instead,
    not by this marker). The `...:` continuation prompt on wrapped/
    multi-line input is blank for the same reason `in_prompt_tokens`
    moved to its own line: there's no longer a column to align under, so
    continuation lines are just flush left too.
    """

    def in_prompt_tokens(self):
        return [
            (Token.Prompt, "In ["),
            (Token.PromptNum, str(self.shell.execution_count)),
            (Token.Prompt, "]:\n"),
        ]

    def out_prompt_tokens(self):
        return []

    def continuation_prompt_tokens(
        self, width: int | None = None, *, lineno=None, wrap_count=None
    ):
        return []


c.TerminalInteractiveShell.prompts_class = StackedPrompt

# %%
_PALETTES = {
    "everforest-dark": {
        "bg_red": "#514045",
        "fg": "#d3c6aa",
        "red": "#e67e80",
        "orange": "#e69875",
        "yellow": "#dbbc7f",
        "green": "#a7c080",
        "aqua": "#83c092",
        "blue": "#7fbbb3",
        "purple": "#d699b6",
        "grey1": "#859289",
    },
    "everforest-light": {
        "bg_red": "#fde3da",
        "fg": "#5c6a72",
        "red": "#f85552",
        "orange": "#f57d26",
        "yellow": "#dfa000",
        "green": "#8da101",
        "aqua": "#35a77c",
        "blue": "#3a94c5",
        "purple": "#df69ba",
        "grey1": "#939f91",
    },
}


def _make_theme(name: str, p: dict[str, str]) -> Theme:
    """Build an IPython Theme from an everforest palette.

    Colors are pulled directly from nvim-treesitter's Python highlight
    query (`queries/python/highlights.scm`) resolved through everforest's
    actual `@capture -> TS... -> color` chain (`colors/everforest.vim`),
    not the legacy (non-treesitter) `after/syntax/python/` overrides--this
    is genuinely what renders in the editor. A couple of gaps are
    inherent to Pygments' lexer-only tokenizer, which can't see the parse
    tree treesitter uses to draw these distinctions:

    - Builtins (`len`, `str`, `int`, ...) are always green here, matching
      the common "called as a function" case (`@function.builtin`).
      Treesitter colors a bare type annotation like `x: int` yellow
      (`@type.builtin`) instead, since it can tell it isn't a call--
      Pygments tags both forms identically.
    - Exception names (`ValueError`, etc.) are always yellow here
      (`@type.builtin`), matching bare references (`except ValueError:`,
      `isinstance(e, ValueError)`). Treesitter colors `raise ValueError(x)`
      green instead (`@constructor`, since it's a call)--again
      indistinguishable to Pygments.
    - Attribute/member access (`self.foo`) and brackets vs. delimiters
      (`@punctuation.bracket` vs. `@punctuation.delimiter`) aren't split
      out by Pygments' tokenizer at all, so both just fall back to the
      plain variable/punctuation color.
    """
    return Theme(
        name,
        None,
        {
            # General syntax
            Token.Comment: f"italic {p['grey1']}",
            Token.Keyword: p["red"],  # covers every keyword, incl. import/from
            Token.Keyword.Constant: p["purple"],  # True/False/None
            Token.Name: p["fg"],
            Token.Name.Function: p["green"],
            Token.Name.Class: p["yellow"],
            Token.Name.Builtin: p["green"],  # len, str, int, range, ...
            Token.Name.Builtin.Pseudo: p["purple"],  # self, cls
            Token.Name.Decorator: p["purple"],
            Token.Name.Exception: p["yellow"],  # ValueError, etc.
            Token.String: p["aqua"],
            Token.Number: p["purple"],
            Token.Operator: p["orange"],
            Token.Punctuation: p["fg"],
            Token.Error: f"bold {p['red']}",
            # Prompt and traceback formatting
            Token.Prompt: p["green"],
            Token.PromptNum: f"bold {p['green']}",
            Token.Prompt.Continuation: p["green"],
            Token.OutPrompt: p["purple"],
            Token.OutPromptNum: f"bold {p['purple']}",
            Token.Header: p["red"],
            Token.Topline: p["red"],
            Token.ExcName: f"bold {p['red']}",
            Token.Filename: p["green"],
            Token.FilenameEm: f"bold {p['green']}",
            Token.Lineno: p["aqua"],
            Token.LinenoEm: f"bold {p['aqua']}",
            Token.VName: p["blue"],
            Token.Caret: p["yellow"],
            Token.TbHighlight: f"bg:{p['bg_red']}",
        },
    )


for _name, _palette in _PALETTES.items():
    theme_table[_name] = _make_theme(_name, _palette)

# %%
# True 24-bit colors, otherwise the palette above gets quantized down to the
# nearest of the 256-color terminal palette and loses its everforest tones.
# (Tracebacks and object-inspection output still go through a formatter that
# IPython 9.x hardcodes to 256-color regardless of this setting--only live
# input highlighting gets true color. This is an IPython limitation, not
# something this file controls.)
c.TerminalInteractiveShell.true_color = True

_appearance_file = Path.home() / ".cache" / "appearance"
_appearance = "dark"
if _appearance_file.exists():
    _read = _appearance_file.read_text().strip()
    if _read in ("dark", "light"):
        _appearance = _read

c.InteractiveShell.colors = f"everforest-{_appearance}"
