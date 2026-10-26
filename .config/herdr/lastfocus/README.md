# lastfocus: tmux-style last pane, tab, and workspace for Herdr

Herdr's built-in `last_pane` jumps to the previously focused pane anywhere, across tabs and workspaces. tmux scopes its equivalents more narrowly, and this plugin reproduces that:

| Key        | tmux               | Action                                           |
| ---------- | ------------------ | ------------------------------------------------ |
| `prefix+;` | `last-pane`        | previous pane in the current tab                 |
| `prefix+l` | `last-window`      | previous tab in the current workspace            |
| `prefix+L` | `switch-client -l` | previous workspace                               |

Each key toggles: pressing it twice returns to where we started. Bindings live in the shared `../config.toml` as `[[keys.command]]` entries, so they also appear in Herdr's keybindings panel (`prefix+?`).

The design follows [pedrobarco/herdr-lastfocus](https://github.com/pedrobarco/herdr-lastfocus), re-implemented in Python so it needs no Go toolchain, keeps separate history per Herdr server, and does not depend on the order Herdr delivers focus events.

## Setup

The plugin is registered by path once per machine. Herdr resolves the path to the real repo location, so the `~/.dotfiles` checkout is what gets linked on both Linux and macOS:

```sh
herdr plugin link ~/.dotfiles/.config/herdr/lastfocus
```

Herdr starts the recorder when its server starts. After the first `plugin link` on a machine whose server is already running, start it once by hand or restart Herdr (which ends its panes):

```sh
cd ~/.dotfiles/.config/herdr/lastfocus && HERDR_SOCKET_PATH=~/.config/herdr/herdr.sock \
    HERDR_PLUGIN_STATE_DIR=~/.local/state/herdr/plugins/lastfocus \
    uv run --offline --no-project --python python3 lastfocus.py daemon --ensure
```

On Linux, `platforms/omarchy/link.sh` links `../config.toml` into `~/.config/herdr/`. On macOS, Stow links it, along with this directory, into the real `~/.config/herdr/` that Herdr created on first run. Run `herdr` once before stowing on a fresh Mac so that directory exists; otherwise Stow would turn `~/.config/herdr` itself into a symlink into the repo and Herdr's sockets and logs would land here. `.gitignore` guards against that too.

Requires Python 3.9 or newer as `python3` on `PATH`; the system Python on macOS is enough.

## How it works

`lastfocus.py daemon --ensure` is the plugin's startup hook. It starts one detached recorder per Herdr server, keyed by the server's socket path, and is idempotent: a file lock means a second `--ensure` does nothing while a recorder is alive. The recorder subscribes to Herdr's `pane.focused`, `tab.focused`, and `workspace.focused` events and, after each one, reads the focused workspace, tab, and pane from `session.snapshot` and appends them to a history file under `HERDR_PLUGIN_STATE_DIR`. Reading the snapshot, rather than the event payloads, is what makes the result independent of event order. The recorder exits when the server's socket disappears.

The three actions never write history. Each reads the current focus, walks the history backwards, and focuses the most recent entry that differs in its scope: a different pane in the same tab, a different tab in the same workspace, or a different workspace. Targets that no longer exist are skipped. Entries equal to the current focus are skipped as well, so a toggle works even if the recorder has not yet written the newest position.

## Limitations

- Herdr's focus events do not say which attached client caused them, and its focus commands move every client attached to the server. With one Herdr window this behaves like tmux; with several windows attached at once, their histories mix.
- Herdr runs startup hooks when a server starts or hands off, not when a plugin is linked or the config reloads; see the setup note above.
- Each Herdr server (the default session and any named one) gets its own recorder and history. Nothing is shared between them.

## Tests

`tests/test_lastfocus.py` starts a throwaway named Herdr session with a client attached in a pseudo-terminal, starts the recorder exactly as the startup hook does, navigates with real keys and CLI calls, and checks where each action lands, including the closed-target fallback and that the recorder exits when the server stops. It never touches the default session.

```sh
uv run --no-project tests/test_lastfocus.py
```
