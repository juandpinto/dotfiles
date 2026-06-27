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

This file is tracked in the dotfiles repo at `~/.dotfiles/.config/nvim/` (not applicable—see new device setup for where to place it).

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

### 3. IPython startup script and sixel support

```bash
brew install libsixel   # provides img2sixel for sixel rendering in tmux
mkdir -p ~/.ipython/profile_default/startup
```

Copy `00-nvim-helpers.py` from the nvim dotfiles or recreate it.

### 4. Per-project setup

```bash
cd my-project
uv add --dev ipython matplotlib pandas numpy  # whatever the project needs
```

No kernel registration needed—`uv run ipython` picks up `.venv` automatically.

### 5. Open nvim from project root

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
