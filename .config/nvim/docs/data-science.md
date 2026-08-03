# Data science setup

Neovim configuration for Python data science work with `# %%` cell-based files, using a separate IPython REPL in a tmux pane—similar to VSCode's Interactive Window.

## Design decisions

### Plugin: vim-slime + IPython in tmux

[vim-slime](https://github.com/jpalardy/vim-slime) sends code from a buffer to any running process in a tmux pane. We run IPython there manually and send cells to it. Chosen over iron.nvim (the previous setup) because:

- **REPL survives nvim restarts**—the IPython process lives in tmux, not inside nvim. Crashes and restarts don't kill your session or variables.
- **Real terminal pane**—full interactivity, scroll history, direct typing, and paste all work natively.
- **Simpler mental model**—vim-slime is just text being sent to a pane. No plugin magic managing process lifecycle.
- **Target flexibility**—the same keybindings can send to a Jupyter console, ptpython, or any other REPL without reconfiguring the plugin.
- **Remote-friendly**—if your tmux session is on a remote machine over SSH, it works without modification.

**Tradeoffs vs iron.nvim:**

- **No auto-start**—you must manually open a tmux pane and start IPython before sending code. iron.nvim opened and managed the REPL pane for you.
- **No pane management from nvim**—toggling or focusing the REPL pane uses tmux bindings (`<prefix>+l` to switch to the last pane), not nvim keymaps (though `<leader>rf` wraps `tmux select-pane -l` as a convenience).
- **Manual retargeting**—if your target pane changes (new window, re-layout), you need to run `:SlimeConfig` to update the target. iron.nvim tracked its own pane automatically.
- **No visual send feedback**—iron.nvim highlighted the region being sent; vim-slime does not.

### Sending code: bracketed paste, not `%cpaste`

Python's indentation-sensitive syntax makes naively piping multi-line text into a REPL unsafe: a blank line inside an otherwise-complete block (e.g. between an `if`/`else` and a following `for` in the same function) can make IPython treat it as "submit now," silently splitting the block into two separate executions instead of one—no error, just wrong behavior. We tested this against a real IPython session and confirmed it happens.

vim-slime's usual fix for this is `g:slime_python_ipython`, which wraps every multi-line send in IPython's `%cpaste -q` magic (buffers everything up to a `--` sentinel and executes it as one atomic block). We use tmux's native bracketed-paste mode instead (`vim.g.slime_bracketed_paste = 1`), which solves the same problem—the whole cell arrives as a single paste event, so IPython's parser never sees a false stopping point—while also preserving `prompt_toolkit`'s live syntax highlighting and `...:` continuation prompts in the REPL, which `%cpaste`'s mode does not render. We verified both behaviors end-to-end (real tmux pane, real IPython, real `<leader>rc`).

> **Don't also enable `slime_python_ipython`.** Combining it with bracketed paste is a known breakage (see [vim-slime#265](https://github.com/jpalardy/vim-slime/issues/265)): the bracket-paste escape codes swallow `%cpaste`'s `--` sentinel and hang the REPL. Use one or the other, not both.

### uv workflow

Vim-slime doesn't launch IPython—you do. `<leader>rr` is a convenience that sends the appropriate start command to the target pane, assuming a shell is already running there.

| Context                                    | Command sent                        |
|--------------------------------------------|-------------------------------------|
| Inside a uv project (`pyproject.toml` found) | `uv run ipython --no-autoindent`  |
| No project                                 | `uvx ipython --no-autoindent`       |
| No uv                                      | `ipython --no-autoindent`           |

The global uv tool env is set up once for ad-hoc sessions:

```bash
uv tool install --force ipython --with matplotlib --with pandas --with numpy
```

**Per-project packages:** do not add visualization tooling (e.g., `matplotlib-backend-kitty`) to shared `pyproject.toml`—it would appear in collaborators' environments. The `00-nvim-helpers.py` startup script implements figure rendering directly and requires only `matplotlib`, which is typically already a project dependency. If a project needs additional personal dev tools, install them transiently with `uv run --with <package> ipython` instead of modifying `pyproject.toml`.

### Image rendering

Matplotlib figures are displayed automatically after each cell via IPython's `post_execute` hook in `00-nvim-helpers.py`. The backend is set to `Agg` (non-interactive) and rendering is handled manually.

Rendering strategy by context:

- **Inside tmux (our case)**—figures render **inline via sixel graphics**. Sixel is stored as part of tmux's screen state, so it renders at the correct cursor position and survives pane switches. Requires `img2sixel` and tmux built with sixel support (tmux 3.4+).
- **Outside tmux (bare WezTerm pane)**—figures render **inline via the kitty graphics protocol**, which WezTerm supports natively. The startup script implements this directly without the `matplotlib-backend-kitty` package.
- **`preview=True` or `<leader>ri`**—always opens in macOS Preview regardless of context.

> **Why sixel and not kitty in tmux?** The kitty graphics protocol places images using absolute screen coordinates relative to the terminal window's top-left corner. tmux panes are sub-regions of that window, so kitty images render at the wrong position (usually off-screen). Sixel images are stored as part of tmux's character-grid state and render inline at the cursor position—no coordinate transformation needed.

### DataFrame display

DataFrames show as text in the REPL. For rich HTML tables, end a cell with the bare DataFrame expression (not `print(df)`) so IPython stores it in `_`, then use `<leader>rb` to open it in the browser.

### IPython startup helpers

`~/.ipython/profile_default/startup/00-nvim-helpers.py` is auto-loaded on every IPython session start. It provides:

- **`show_html(obj)`**—opens any object with `_repr_html_()` in the browser as a styled HTML page. `show_html(_)` shows the last result.
- **`show_fig(fig, dpi, preview)`**—displays a matplotlib figure inline (outside tmux) or in Preview (inside tmux). Pass `preview=True` to always use Preview.
- **`_auto_show_figures()`**—`post_execute` hook; auto-displays and closes all figures after each cell.
- Sets matplotlib backend to `Agg`.

This file is tracked in the dotfiles repo at `~/.dotfiles/.ipython/profile_default/startup/00-nvim-helpers.py` and symlinked into place by Stow (see the syntax theme note below for how that works alongside IPython's own untracked runtime state in the same directory).

### IPython syntax theme

`~/.ipython/profile_default/ipython_config.py` registers `everforest-dark`/`everforest-light` as IPython 9.x `Theme` objects (`IPython.utils.PyColorize.theme_table`) and activates whichever matches the current macOS appearance, read once at startup from `~/.cache/appearance` (the same single source of truth used by nvim/tmux/sketchybar/btop—see the dotfiles repo's `AGENTS.md`). It also sets `TerminalInteractiveShell.true_color = True` so the palette renders as exact 24-bit hex instead of being quantized to the nearest 256-color approximation.

Token colors are resolved from nvim-treesitter's actual Python highlight query (`queries/python/highlights.scm`) through everforest's `@capture -> color` chain (`colors/everforest.vim`)—i.e. what genuinely renders in the editor, not the legacy non-treesitter `after/syntax/python/` overrides. A couple of gaps are inherent to Pygments being a lexer with no parse tree: it can't distinguish `len` called as a function (green, `@function.builtin`) from `len` referenced bare, or `raise ValueError(x)` (green, `@constructor`, since it's a call) from `except ValueError:` (yellow, `@type.builtin`)—both pairs get one Pygments token type each, so this theme picks whichever case is more common. See the comment on `_make_theme` in `ipython_config.py` for the full list.

> **Known limitation:** this only affects live input highlighting (what you see while typing or pasting code). Tracebacks and object-inspection output (`obj??`) go through a different formatter that IPython 9.x hardcodes to 256-color regardless of `true_color`—an upstream limitation, not something this config controls.

This file is tracked at `~/.dotfiles/.ipython/profile_default/ipython_config.py` and symlinked into place by Stow, the same way as `00-nvim-helpers.py` above. `~/.ipython/profile_default/` tree-folds the same way `~/.config/pi/agent/` does (see the dotfiles repo's `AGENTS.md`): Stow descends into the existing real directory and links only the tracked files, leaving IPython's own runtime state alone.

> **Also in this file:** a `StackedPrompt` class (via `TerminalInteractiveShell.prompts_class`) puts `In [n]:` on its own line above the code instead of inline with it, so pasted code renders flush left with its original indentation intact rather than offset to align under the prompt. `Out[n]:` is dropped entirely (the value still prints, just unlabeled), and the `...:` continuation prompt is blank for the same reason--there's no longer a column to align continuation lines under.

### Input/output boundary

With `Out[n]:` gone, input and output need another way to be told apart--`~/.ipython/profile_default/startup/01-output-box.py` handles this two ways:

- **Rules.** `pre_execute`/`post_execute` hooks print a thin horizontal rule (colored to match the current everforest appearance) right after a cell's input is echoed and right after its output ends, bounding the output top and bottom like a borderless box.
- **Color.** Between those two rules, `sys.stdout` is swapped for a wrapper that recolors plain output text bold everforest `blue`--the one color unused anywhere in the syntax theme in `ipython_config.py`, so output is never mistaken for input at a glance.

Anything that already contains an ESC byte is left alone rather than recolored, so this can't corrupt a traceback's own theme coloring or `show_fig`'s raw sixel/kitty image bytes--those go through `sys.stdout.buffer` directly (bytes, not this wrapper's text `.write()`), and the wrapper's `__getattr__` proxies `.buffer` (and `.isatty()`, `.encoding`, everything else it doesn't explicitly override) straight through to the real stdout untouched. Verified directly: a raw `sys.stdout.buffer.write(...)` passes through with no color codes added, while ordinary prints, bare-expression results, and multi-line pasted code all render bold blue; a triggered traceback still renders in its own red/yellow everforest theme, not blue.

This intentionally still doesn't fill a background behind the output text (closer to what a Jupyter cell or one of pi's own tool-output boxes looks like)--only the text color changes, chunk by chunk, rather than repainting whole padded-to-width lines. A true filled background is a further step from here if wanted, not something currently implemented.

Mirrors the cell-separator virtual text already drawn above every `# %%` marker in nvim (same `vim-slime.lua`)--same visual language, now on the REPL side too.

### Execution timer

`~/.ipython/profile_default/startup/02-execution-timer.py` adds a VSCode-interactive-window-style "still running" indicator and a duration log, both via `pre_execute`/`post_execute`:

- **Live "still running" indicator.** A background thread ticks every 0.5s while a cell runs, writing the elapsed time into the *tmux pane title* (OSC 2, `\033]2;...\007`)--not printed inline, since that would be one more thing racing with whatever the cell's own code writes to stdout. `~/.config/tmux/tmux.conf` already shows `#{pane_title}` in a border line whenever a window has 2+ panes, which is exactly the nvim+ipython split this workflow uses, so the indicator needs no further setup. Written straight to `sys.__stdout__` (the real, original stdout)--`01-output-box.py`'s recoloring wrapper never even sees it, and wouldn't touch it if it did (anything with an ESC byte is passed through untouched).
- **Duration log.** A dim `⏱ N.NNs` line prints once a cell finishes, giving a persistent, scrollback-visible history of how long each cell took. Skipped for cells under 0.2s, so instant one-liners (`2 + 2`) don't get a noisy `⏱ 0.00s` on every cell.

A terminal IPython REPL has no real equivalent of VSCode's *queued* cell indicator--that relies on the async Jupyter kernel protocol letting the frontend track multiple in-flight `execute_request`s, whereas this is a single blocking read-eval-print loop with no queue to report on. The live pane-title indicator is the practical answer here instead: at-a-glance visibility into "something is still running," without needing to read the pane's own scrollback.

Verified directly: polling `tmux display-message -p '#{pane_title}'` externally during a `time.sleep(3)` cell showed it ticking every half-second; interrupting a `time.sleep(10)` cell with `Ctrl-C` still stopped the thread and reset the title correctly (`post_execute` fires on `KeyboardInterrupt` too, effectively a `finally`)--no leaked thread, no stuck "running" title.

### Quiet queued input

vim-slime sends whole cells at once, so it's easy to paste a second cell into this pane while a previous one is still executing. Without `~/.ipython/profile_default/startup/03-quiet-queued-input.py`, that has two separate problems:

1. **Garbled echo.** The terminal is in normal cooked/echoing mode for the duration of cell execution (confirmed directly--reading `termios.tcgetattr` from inside a running cell showed `ECHO` on, whereas the same read at an idle prompt shows it off, since `prompt_toolkit` manages its own raw/no-echo mode only while actively reading), so whatever arrives on stdin gets echoed to the screen immediately, garbled into whatever else is happening, well before IPython is actually ready to read it as the next input.
2. **Silently split cells.** tmux only wraps a paste in bracketed-paste markers (`-p` on `paste-buffer`) "if the destination application has requested bracketed paste mode" (`man tmux`). `prompt_toolkit` only requests that mode while actively reading input--confirmed in its source (`renderer.py`): entering `Application.run()` calls `output.enable_bracketed_paste()`, and `reset()`, called once `run()` returns (i.e. for the entire cell-execution window), calls `output.disable_bracketed_paste()`. So a cell pasted while a previous one is executing arrives *without* bracket markers, and IPython's line-by-line reader treats any blank line in it as "submit now." Reproduced directly: a multi-statement cell (function def, blank line, then a call) queued behind a CPU-bound busy loop came back as two separate `In [n]:` submissions instead of one. (A `time.sleep()`-based busy cell didn't reliably reproduce this in testing--plausibly because it fully releases the GIL and keeps the system otherwise idle, whereas a tight Python loop pins the CPU while tmux is trying to track pane state--but the fix doesn't depend on knowing exactly why; it just keeps bracketed paste mode on throughout, so it can't matter either way.)

This file's `pre_execute`/`post_execute` hooks handle both, for the duration of each cell:

- Clear the `ECHO` bit (only `ECHO`--`ICANON` and everything else are left alone, so normal line editing/buffering still works), restoring the original settings once the cell finishes.
- Write `\033[?2004h`/`\033[?2004l` directly to `sys.__stdout__` (bypassing `prompt_toolkit` entirely) to keep tmux's own bracketed-paste tracking enabled throughout, mirroring exactly what `prompt_toolkit` itself does while it's the active reader.

Verified empirically, including the exact failure case: with the real nvim + vim-slime pipeline (not just raw tmux commands), pasting a multi-statement cell while a CPU-bound busy loop is confirmed still running (checked via the execution-timer's pane title at two points before sending) now arrives as nothing visible until the first cell finishes, then executes as a single `In [n]:` cell with full syntax highlighting--not two. Also verified safe across `Ctrl-C`, for the same reason as the timer above--terminal is never left echo-suppressed or bracket-paste-stuck-on.

> **Known no-prior-art:** searched for existing IPython/prompt_toolkit issues or discussion of this specific problem (queued stdin getting echoed/garbled/split mid-execution) and found none--this appears to be a narrow consequence of the vim-slime-paste-into-a-busy-REPL workflow specifically, not something the broader community has run into or addressed.

One tradeoff: if a cell calls the builtin `input()` while typing directly into this pane (not the vim-slime paste path this is designed for), keystrokes won't be echoed back until Enter is pressed--`ECHO` is off for the whole cell, not just while something happens to be queued, since there's no cheap way to tell those two cases apart ahead of time. Reading still works correctly either way; it's a blind-typing UX quirk, not a functional break, and this workflow doesn't otherwise rely on interactive `input()` calls.

### Local-only IPython state

Everything else under `~/.ipython/profile_default/` is deliberately left untracked (and gitignored in the dotfiles repo, to guard against an accidental `git add -A`):

- **`history.sqlite`**—your entire cross-session command history. Tens of megabytes, constantly changing, and potentially sensitive (anything ever typed or pasted into a REPL can end up here). No reason to carry one machine's history into another.
- **`db/`**—directory-navigation history, keyed on local absolute paths that won't exist on another machine.
- **`log/`, `pid/`, `security/`**—pure runtime state (lock files, PIDs; `security/` holds Jupyter kernel connection files when populated, which are effectively local secrets).
- **`startup/00-databricks-init-<hash>.py`**—auto-generated by Databricks tooling (VS Code extension / `databricks-connect`), not user-authored. Tracking it would fight with the tool that owns it and could go stale or use a different hash on another machine.
- **`startup/README`**—IPython's own boilerplate, recreated automatically the first time the profile exists. No custom content to track.

### tmux configuration

`~/.config/tmux/tmux.conf` must include:

```
set -gq allow-passthrough all
set -g visual-activity off
```

`allow-passthrough all` is required for graphics protocol passthrough in any pane (e.g., image.nvim). Even with it enabled, matplotlib inline rendering falls back to Preview inside tmux due to the upstream limitation described above.

## New device setup

### 1. Global IPython uv tool

```bash
uv tool install --force ipython --with matplotlib --with pandas --with numpy
```

Verify:

```bash
uvx ipython -c "import matplotlib; print('OK')"
```

### 2. tmux configuration

Add to `~/.config/tmux/tmux.conf` (or `~/.tmux.conf`):

```
set -gq allow-passthrough all
set -g visual-activity off
set -as terminal-features "*:sixel"
```

Reload: `tmux source-file ~/.tmux.conf`

### 3. Sixel support

```bash
brew install libsixel   # provides img2sixel for sixel rendering in tmux
```

### 4. IPython config and startup scripts

Already in place if you stowed the dotfiles repo (`ipython_config.py` and everything tracked under `startup/` symlink automatically). No manual step needed.

### 5. Per-project setup

```bash
cd my-project
uv add --dev ipython matplotlib pandas numpy  # whatever the project needs
```

No kernel registration needed—`uv run ipython` picks up `.venv` automatically.

### 6. Open nvim from project root

```bash
cd my-project
nvim .
```

## Workflow

### Starting a session

Open a tmux pane alongside your editor (e.g., `<prefix>+%` for a vertical split), then:

```
<leader>rr    →  send the right `uv run ipython` command to the target pane
<leader>rc    →  run current # %% cell (stay in cell)
<leader>rn    →  run current # %% cell and move to next
                 (creates a new # %% at EOF if on the last cell)
```

The target pane defaults to `{last}` (the pane you were most recently in before switching to nvim). If the target ever gets stale, run `:SlimeConfig` to update it.

### Working with DataFrames

End cells with the bare expression, not `print(df)`, so IPython stores it in `_`:

```python
# %%
df = pd.read_csv("data.csv")
df.head()      # stored in _ by IPython
```

Then `<leader>rb` opens it in the browser as a styled HTML table.

### Working with plots

```python
# %%
import matplotlib.pyplot as plt
plt.plot([1, 2, 3])
# figure auto-displays after the cell completes:
#   - inline via sixel (inside tmux, WezTerm)
#   - inline via kitty protocol (outside tmux, bare WezTerm pane)
```

`<leader>ri` forces macOS Preview regardless of context.

### Multiple files / subdirectories

The REPL inherits cwd from where the shell was when IPython started (usually project root). For files in subdirectories, use `<leader>mcd` to send `os.chdir()` for the current file's directory.

### Visual cell separators

A thin horizontal rule (virtual text, drawn via extmarks) automatically appears above every `# %%` marker in Python buffers, except the first cell. Purely visual—no keybinding, nothing to configure. Implemented in `vim-slime.lua` since it reuses the same cell-marker detection as the REPL commands.

## Keybinding reference

### REPL lifecycle

| Key              | Mode | Action                                        |
|------------------|------|-----------------------------------------------|
| `<leader>rr`     | n    | Send start command to target pane             |
| `<leader>rf`     | n    | Focus REPL pane (`tmux select-pane -l`)       |
| `<leader>p<leader>` | n | Interrupt running code (Ctrl-C)              |
| `<leader>pq`     | n    | Exit REPL (Ctrl-D)                            |
| `<leader>cl`     | n    | Clear REPL screen (Ctrl-L)                    |

### Sending code

| Key          | Mode | Action                                            |
|--------------|------|---------------------------------------------------|
| `<leader>rc` | n    | Run current `# %%` cell, stay                     |
| `<leader>rn` | n    | Run current `# %%` cell, advance (creates new cell at EOF) |
| `<leader>pv` | v    | Send visual selection                             |
| `<leader>pl` | n    | Send current line                                 |
| `<leader>pu` | n    | Send from top of file to cursor                   |

### Output utilities

| Key          | Mode | Action                                            |
|--------------|------|---------------------------------------------------|
| `<leader>rb` | n    | Open last result (`_`) as HTML in browser         |
| `<leader>ri` | n    | Open current matplotlib figure in Preview         |
| `<leader>mcd`| n    | Set REPL cwd to current file's directory          |

### Tips

- The target pane defaults to `{last}`—switch to your IPython pane, do something, then switch back to nvim, and sends will go there automatically.
- `_` in IPython always holds the last evaluated expression—the key to `show_html(_)`.
- `<leader>p<leader>` sends Ctrl-C to interrupt a stuck cell.
- To restart IPython, exit with `<leader>pq` then start fresh with `<leader>rr`.
- `:SlimeConfig` lets you manually update the target pane socket and pane ID if it ever gets stale.

## Known limitations

- **No inline HTML output**—DataFrames show as plain text in the REPL. Use `<leader>rb` for the HTML view.
- **Sixel requires img2sixel**—inline plots in tmux depend on `brew install libsixel`. If not installed, `show_fig` falls back to macOS Preview with a console warning.
- **No auto-start**—unlike iron.nvim, vim-slime does not manage the REPL process. You must start IPython manually (or via `<leader>rr` with a shell in the target pane).
- **No pane toggle from nvim**—use `<prefix>+l` in tmux to switch between the editor and REPL panes. `<leader>rf` wraps this as a convenience but cannot bring a hidden pane back into view.
- **Shared REPL state**—all files in the same nvim session share one IPython process. Exit and restart to get a clean kernel.
